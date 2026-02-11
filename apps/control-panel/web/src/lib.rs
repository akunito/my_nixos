//! NixOS Infrastructure Control Panel - Web Library
//!
//! Exposes the Axum router and AppState so the Tauri desktop wrapper
//! can embed the web server without duplicating routes.

pub mod routes;

use axum::{
    middleware,
    routing::{get, post},
    Router,
};
use control_panel_core::Config;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;

/// Application state shared across handlers
pub struct AppState {
    pub config: Config,
    pub ssh_pool: RwLock<control_panel_core::SshPool>,
}

/// Build the full Axum router with all routes registered.
/// Used by both the standalone web server and the Tauri desktop wrapper.
pub fn build_router(state: Arc<AppState>) -> Router {
    Router::new()
        // Health check (no auth)
        .route("/health", get(|| async { "ok" }))
        // Index/home
        .route("/", get(routes::index))
        // Docker routes
        .route("/docker", get(routes::docker::dashboard))
        .route("/docker/summary", get(routes::docker::summary_fragment))
        .route("/docker/{node}", get(routes::docker::node_containers))
        .route(
            "/docker/{node}/containers",
            get(routes::docker::containers_fragment),
        )
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
        // Docker Compose stack operations
        .route(
            "/docker/{node}/stack/{project}/up",
            post(routes::docker::stack_up),
        )
        .route(
            "/docker/{node}/stack/{project}/stop",
            post(routes::docker::stack_stop),
        )
        .route(
            "/docker/{node}/stack/{project}/down",
            post(routes::docker::stack_down),
        )
        .route(
            "/docker/{node}/stack/{project}/restart",
            post(routes::docker::stack_restart),
        )
        .route(
            "/docker/{node}/stack/{project}/rebuild",
            post(routes::docker::stack_rebuild),
        )
        .route(
            "/docker/{node}/stack/{project}/pull",
            post(routes::docker::stack_pull),
        )
        .route(
            "/docker/{node}/stack/{project}/logs",
            get(routes::docker::stack_logs),
        )
        // Proxmox routes
        .route("/proxmox", get(routes::proxmox::dashboard))
        .route(
            "/proxmox/containers",
            get(routes::proxmox::containers_fragment),
        )
        .route("/proxmox/{ctid}/start", post(routes::proxmox::start))
        .route("/proxmox/{ctid}/stop", post(routes::proxmox::stop))
        .route("/proxmox/{ctid}/restart", post(routes::proxmox::restart))
        .route("/proxmox/{ctid}/status", get(routes::proxmox::status))
        // Infrastructure routes
        .route("/infra", get(routes::infra::dashboard))
        .route("/infra/graph", get(routes::infra::graph_data))
        .route("/infra/git/status", get(routes::infra::git_status))
        .route(
            "/infra/git/status-fragment",
            get(routes::infra::git_status_fragment),
        )
        .route("/infra/git/diff", get(routes::infra::git_diff))
        .route("/infra/git/pull", post(routes::infra::git_pull))
        .route("/infra/git/push", post(routes::infra::git_push))
        .route("/infra/git/commit", post(routes::infra::git_commit))
        .route("/infra/deploy/{profile}", post(routes::infra::deploy))
        .route(
            "/infra/deploy/{profile}/dry-run",
            post(routes::infra::dry_run),
        )
        // Deploy-LXC routes
        .route("/infra/deploy-lxc", get(routes::infra::deploy_lxc_page))
        .route(
            "/infra/deploy-lxc/{profile}",
            post(routes::infra::deploy_lxc_execute),
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
        .with_state(state)
}
