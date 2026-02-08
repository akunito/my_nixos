//! NixOS Infrastructure Control Panel - Web Server
//!
//! Web-based fallback interface for mobile/remote access via Tailscale.
//! Uses htmx for interactive UI without full page reloads.

mod routes;

use anyhow::Result;
use axum::{
    middleware,
    routing::{get, post},
    Router,
};
use control_panel_core::Config;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// Application state shared across handlers
pub struct AppState {
    pub config: Config,
    pub ssh_pool: RwLock<control_panel_core::SshPool>,
}

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

    // Build router
    // Note: Axum 0.8+ uses {param} syntax instead of :param for path parameters
    let app = Router::new()
        // Index/home
        .route("/", get(routes::index))
        // Docker routes
        .route("/docker", get(routes::docker::dashboard))
        .route("/docker/{node}", get(routes::docker::node_containers))
        .route(
            "/docker/{node}/{container}/start",
            post(routes::docker::start_container),
        )
        .route(
            "/docker/{node}/{container}/stop",
            post(routes::docker::stop_container),
        )
        .route(
            "/docker/{node}/{container}/restart",
            post(routes::docker::restart_container),
        )
        .route(
            "/docker/{node}/{container}/logs",
            get(routes::docker::container_logs),
        )
        // Proxmox routes
        .route("/proxmox", get(routes::proxmox::dashboard))
        .route("/proxmox/{ctid}/start", post(routes::proxmox::start))
        .route("/proxmox/{ctid}/stop", post(routes::proxmox::stop))
        .route("/proxmox/{ctid}/restart", post(routes::proxmox::restart))
        .route("/proxmox/{ctid}/status", get(routes::proxmox::status))
        // Infrastructure routes
        .route("/infra", get(routes::infra::dashboard))
        .route("/infra/graph", get(routes::infra::graph_data))
        .route("/infra/git/status", get(routes::infra::git_status))
        .route("/infra/git/diff", get(routes::infra::git_diff))
        .route("/infra/git/pull", post(routes::infra::git_pull))
        .route("/infra/git/push", post(routes::infra::git_push))
        .route("/infra/git/commit", post(routes::infra::git_commit))
        .route("/infra/deploy/{profile}", post(routes::infra::deploy))
        .route(
            "/infra/deploy/{profile}/dry-run",
            post(routes::infra::dry_run),
        )
        // Editor routes
        .route("/editor", get(routes::editor::list_profiles))
        .route("/editor/{profile}", get(routes::editor::view_profile))
        .route(
            "/editor/{profile}/toggle/{flag}",
            post(routes::editor::toggle_flag),
        )
        .route(
            "/editor/{profile}/duplicate",
            post(routes::editor::duplicate_profile),
        )
        // Monitoring routes
        .route("/monitoring", get(routes::monitoring::dashboard))
        .route("/monitoring/{uid}", get(routes::monitoring::dashboard))
        // Static files
        .nest_service("/static", ServeDir::new("static"))
        // Add state and middleware
        .layer(TraceLayer::new_for_http())
        .layer(middleware::from_fn_with_state(
            state.clone(),
            routes::auth::basic_auth_middleware,
        ))
        .with_state(state);

    tracing::info!("Listening on {}", bind_addr);

    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
