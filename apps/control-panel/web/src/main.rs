//! NixOS Infrastructure Control Panel - Web Server
//!
//! Primary web interface using Axum + htmx.
//! Can be wrapped by Tauri for a standalone desktop experience.

use anyhow::Result;
use control_panel_core::Config;
use control_panel_web::{build_router, AppState};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,control_panel_web=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting NixOS Control Panel Web Server");

    // Determine config path
    let config_path = std::env::var("CONFIG_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
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

    let bind_addr = format!("{}:{}", config.server.host, config.server.port);

    // Create SSH pool
    let ssh_pool = control_panel_core::SshPool::new(&config)?;

    // Create shared state
    let state = Arc::new(AppState {
        config: config.clone(),
        ssh_pool: RwLock::new(ssh_pool),
    });

    // Build router using the shared library function
    let app = build_router(state);

    tracing::info!("Listening on {}", bind_addr);

    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;

    Ok(())
}
