//! NixOS Control Panel - Tauri Desktop Wrapper
//!
//! Opens a native desktop window for the control panel web UI.
//!
//! Behavior:
//! - If the control-panel-web systemd service is already running (port 3100),
//!   the window simply connects to it.
//! - Otherwise, it starts an embedded web server on an available port.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use anyhow::Result;
use control_panel_core::Config;
use control_panel_web::{build_router, AppState};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::Manager;
use tokio::sync::RwLock;

/// Default port used by the systemd service
const DEFAULT_PORT: u16 = 3100;
/// Fallback port if the default is already taken
const FALLBACK_PORT: u16 = 3101;

fn main() {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter("info,control_panel=debug")
        .init();

    tracing::info!("Starting NixOS Control Panel Desktop");

    // Check if the web server is already running before Tauri starts
    let server_url = if check_server_running(DEFAULT_PORT) {
        tracing::info!(
            "Web server already running on port {}, connecting to it",
            DEFAULT_PORT
        );
        format!("http://localhost:{}", DEFAULT_PORT)
    } else {
        tracing::info!(
            "No web server detected, will start embedded server on port {}",
            FALLBACK_PORT
        );
        format!("http://localhost:{}", FALLBACK_PORT)
    };

    let need_server = !check_server_running(DEFAULT_PORT);
    let url_for_tauri = server_url.clone();

    tauri::Builder::default()
        .setup(move |app| {
            // Only start the embedded server if the service isn't already running
            if need_server {
                tauri::async_runtime::spawn(async move {
                    if let Err(e) = start_web_server(FALLBACK_PORT).await {
                        tracing::error!("Embedded web server failed: {}", e);
                    }
                });
            }

            // Navigate the main window to the correct URL
            if let Some(window) = app.get_webview_window("main") {
                let url: tauri::Url = url_for_tauri.parse().expect("valid URL");
                let _ = window.navigate(url);
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Check if a server is already listening on the given port
fn check_server_running(port: u16) -> bool {
    std::net::TcpStream::connect_timeout(
        &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
        std::time::Duration::from_millis(200),
    )
    .is_ok()
}

async fn start_web_server(port: u16) -> Result<()> {
    // Determine config path (check multiple locations)
    let config_path = std::env::var("CONFIG_PATH")
        .or_else(|_| std::env::var("CONTROL_PANEL_CONFIG"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // Check /etc first (NixOS managed), then home
            let etc_path = PathBuf::from("/etc/control-panel/config.toml");
            if etc_path.exists() {
                return etc_path;
            }
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            PathBuf::from(format!("{}/.dotfiles/apps/control-panel/config.toml", home))
        });

    // Load configuration
    let config: Config = if config_path.exists() {
        tracing::info!("Loading config from: {:?}", config_path);
        let content = std::fs::read_to_string(&config_path)?;
        toml::from_str(&content)?
    } else {
        tracing::warn!("Config not found at {:?}, using defaults", config_path);
        Config::default()
    };

    // Create SSH pool
    let ssh_pool = control_panel_core::SshPool::new(&config)?;

    // Create shared state
    let state = Arc::new(AppState {
        config,
        ssh_pool: RwLock::new(ssh_pool),
    });

    // Build router using the shared web library
    let app = build_router(state);

    let bind = format!("127.0.0.1:{}", port);
    tracing::info!("Embedded web server listening on {}", bind);

    let listener = tokio::net::TcpListener::bind(&bind).await?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;

    Ok(())
}
