//! NixOS Infrastructure Control Panel
//!
//! A web-based control panel for managing NixOS infrastructure:
//! - Phase 1: Docker container management across LXC nodes
//! - Phase 2: Infrastructure control (Proxmox, deployment, profile visualization)
//! - Phase 3: Profile configuration editor

mod auth;
mod config;
mod docker;
mod editor;
mod error;
mod infra;
mod ssh;

use axum::{
    middleware,
    routing::{get, post},
    Router,
};
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::{services::ServeDir, trace::TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;
use crate::ssh::SshPool;

/// Application state shared across handlers
pub struct AppState {
    pub config: Config,
    pub ssh_pool: RwLock<SshPool>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "control_panel=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config_path = std::env::var("CONFIG_PATH")
        .unwrap_or_else(|_| "config.toml".to_string());

    let config = Config::load(&config_path)?;
    tracing::info!("Loaded configuration from {}", config_path);

    // Create SSH connection pool
    let ssh_pool = SshPool::new(&config)?;

    // Create shared state
    let state = Arc::new(AppState {
        config: config.clone(),
        ssh_pool: RwLock::new(ssh_pool),
    });

    // Build router
    let app = Router::new()
        // Home/overview page
        .route("/", get(infra::routes::home))

        // Docker routes (Phase 1)
        .route("/docker", get(docker::routes::dashboard))
        .route("/docker/{node}", get(docker::routes::node_containers))
        .route("/docker/{node}/{container}/start", post(docker::routes::start_container))
        .route("/docker/{node}/{container}/stop", post(docker::routes::stop_container))
        .route("/docker/{node}/{container}/restart", post(docker::routes::restart_container))
        .route("/docker/{node}/{container}/logs", get(docker::routes::container_logs))
        .route("/docker/{node}/{container}/pull", post(docker::routes::pull_container))
        .route("/docker/{node}/{container}/recreate", post(docker::routes::recreate_container))
        // Docker cleanup routes
        .route("/docker/{node}/prune/system", post(docker::routes::system_prune))
        .route("/docker/{node}/prune/volumes", post(docker::routes::volume_prune))
        .route("/docker/{node}/prune/images", post(docker::routes::image_prune))
        .route("/docker/{node}/disk-usage", get(docker::routes::disk_usage))
        // Docker compose stack routes
        .route("/docker/{node}/stack/{project}/up", post(docker::routes::stack_up))
        .route("/docker/{node}/stack/{project}/stop", post(docker::routes::stack_stop))
        .route("/docker/{node}/stack/{project}/down", post(docker::routes::stack_down))
        .route("/docker/{node}/stack/{project}/pull", post(docker::routes::stack_pull))
        .route("/docker/{node}/stack/{project}/rebuild", post(docker::routes::stack_rebuild))
        .route("/docker/{node}/stack/{project}/restart", post(docker::routes::stack_restart))
        .route("/docker/{node}/stack/{project}/logs", get(docker::routes::stack_logs))

        // Infrastructure routes (Phase 2)
        .route("/infra", get(infra::routes::dashboard))
        .route("/infra/profile/{profile}", get(infra::routes::profile_details))
        .route("/infra/graph/data", get(infra::routes::graph_data))
        .route("/infra/health", get(infra::routes::health_check))
        .route("/infra/git/status", get(infra::routes::git_status))
        .route("/infra/git/diff", get(infra::routes::git_diff))
        .route("/infra/git/pull", post(infra::routes::git_pull))
        .route("/infra/git/commit", post(infra::routes::git_commit))
        .route("/infra/git/push", post(infra::routes::git_push))
        .route("/infra/git/auto-commit", post(infra::routes::git_auto_commit))
        .route("/infra/deploy/{profile}/dry-run", post(infra::routes::deploy_dry_run))
        .route("/infra/deploy/{profile}", post(infra::routes::deploy_profile))

        // Proxmox routes
        .route("/proxmox", get(infra::routes::proxmox_dashboard))
        .route("/proxmox/containers", get(infra::routes::proxmox_containers))
        .route("/proxmox/{ctid}/start", post(infra::routes::proxmox_start))
        .route("/proxmox/{ctid}/stop", post(infra::routes::proxmox_stop))
        .route("/proxmox/{ctid}/restart", post(infra::routes::proxmox_restart))
        .route("/proxmox/{ctid}/status", get(infra::routes::proxmox_status))
        .route("/proxmox/backup/{job_id}/run", post(infra::routes::proxmox_backup_run))

        // Monitoring routes
        .route("/monitoring", get(infra::routes::monitoring_dashboard))

        // Editor routes (Phase 3)
        .route("/editor", get(editor::routes::profile_list))
        .route("/editor/packages", get(editor::routes::package_browser))
        .route("/editor/{profile}", get(editor::routes::profile_editor))
        .route("/editor/{profile}/toggle/{flag}", post(editor::routes::toggle_flag))
        .route("/editor/{profile}/json", get(editor::routes::profile_json))
        .route("/editor/{profile}/duplicate", get(editor::routes::duplicate_form))
        .route("/editor/{profile}/duplicate", post(editor::routes::duplicate_profile))
        .route("/editor/{profile}/add-package", post(editor::routes::add_package))
        .route("/editor/{profile}/remove-package", post(editor::routes::remove_package))
        .route("/editor/{profile}/set/{key}", post(editor::routes::set_value))

        // Health check (no auth required)
        .route("/health", get(|| async { "OK" }))

        // Static files
        .nest_service("/static", ServeDir::new("static"))

        // Add authentication middleware
        .layer(middleware::from_fn_with_state(state.clone(), auth::auth_middleware))

        // Add tracing
        .layer(TraceLayer::new_for_http())

        // Add state
        .with_state(state.clone());

    // Bind and serve
    let addr = format!("{}:{}", config.server.host, config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("Control panel listening on http://{}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}
