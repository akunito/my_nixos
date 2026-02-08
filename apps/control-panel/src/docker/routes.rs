//! Docker management HTTP routes

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::docker::commands;
use crate::docker::{ComposeStack, Container, ContainerStatus, NodeSummary};
use crate::error::AppError;
use crate::AppState;

/// Dashboard showing all nodes with container summaries
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    use tokio::time::{timeout, Duration};

    let mut summaries = Vec::new();

    for node in &state.config.docker_nodes {
        // Wrap SSH operations in a 5-second timeout
        let summary = match timeout(Duration::from_secs(5), async {
            let mut ssh_pool = state.ssh_pool.write().await;
            commands::get_node_summary(&mut ssh_pool, &node.name, &node.host).await
        }).await {
            Ok(s) => s,
            Err(_) => {
                // Timeout - return offline status
                tracing::warn!("Timeout connecting to node {}", node.name);
                NodeSummary {
                    name: node.name.clone(),
                    host: node.host.clone(),
                    total: 0,
                    running: 0,
                    stopped: 0,
                    online: false,
                }
            }
        };
        summaries.push(summary);
    }

    let html = render_dashboard(&summaries);
    Ok(Html(html))
}

/// Show containers for a specific node (grouped by compose stack)
pub async fn node_containers(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Result<Html<String>, AppError> {
    let node_config = state
        .config
        .get_docker_node(&node)
        .ok_or_else(|| AppError::NodeNotFound(node.clone()))?;

    let mut ssh_pool = state.ssh_pool.write().await;
    let containers = commands::list_containers(&mut ssh_pool, &node).await?;

    // Group containers by compose project/stack
    let stacks = commands::group_by_stack(containers);

    let html = render_node_stacks(&node, &node_config.host, &stacks);
    Ok(Html(html))
}

/// Start a container
pub async fn start_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    commands::start_container(&mut ssh_pool, &node, &container).await?;

    // Return updated container row
    let containers = commands::list_containers(&mut ssh_pool, &node).await?;
    let container_info = containers
        .iter()
        .find(|c| c.name == container || c.id == container)
        .ok_or_else(|| AppError::ContainerNotFound(container.clone()))?;

    Ok(Html(render_container_row(&node, container_info)))
}

/// Stop a container
pub async fn stop_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    commands::stop_container(&mut ssh_pool, &node, &container).await?;

    // Return updated container row
    let containers = commands::list_containers(&mut ssh_pool, &node).await?;
    let container_info = containers
        .iter()
        .find(|c| c.name == container || c.id == container)
        .ok_or_else(|| AppError::ContainerNotFound(container.clone()))?;

    Ok(Html(render_container_row(&node, container_info)))
}

/// Restart a container
pub async fn restart_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    commands::restart_container(&mut ssh_pool, &node, &container).await?;

    // Return updated container row
    let containers = commands::list_containers(&mut ssh_pool, &node).await?;
    let container_info = containers
        .iter()
        .find(|c| c.name == container || c.id == container)
        .ok_or_else(|| AppError::ContainerNotFound(container.clone()))?;

    Ok(Html(render_container_row(&node, container_info)))
}

/// Get container logs
pub async fn container_logs(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let logs = commands::get_container_logs(&mut ssh_pool, &node, &container, 100).await?;

    let html = format!(
        r##"<div class="logs-container">
            <div class="flex justify-between items-center mb-4">
                <h3 class="text-xl font-bold">Logs: {container}</h3>
                <button hx-get="/docker/{node}/{container}/logs"
                        hx-target="#logs-content"
                        hx-swap="innerHTML"
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                    Refresh
                </button>
            </div>
            <pre id="logs-content" class="bg-gray-900 p-4 rounded overflow-auto max-h-96 text-sm font-mono">{logs}</pre>
        </div>"##,
        container = container,
        node = node,
        logs = html_escape(&logs)
    );

    Ok(Html(html))
}

/// Pull latest image for a container
pub async fn pull_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    use tokio::time::{timeout, Duration};

    let result = timeout(Duration::from_secs(120), async {
        let mut ssh_pool = state.ssh_pool.write().await;
        commands::pull_container(&mut ssh_pool, &node, &container).await
    }).await;

    match result {
        Ok(Ok(output)) => Ok(Html(format!(
            r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Pull complete for {}</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            container,
            html_escape(&output)
        ))),
        Ok(Err(e)) => Ok(Html(format!(
            r##"<div class="bg-red-900 border border-red-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Failed to pull {}</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            container,
            html_escape(&e.to_string())
        ))),
        Err(_) => Ok(Html(format!(
            r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Pull timeout for {} (2 min)</p>
                <p class="text-xs">Operation may still be running. Check manually or refresh later.</p>
            </div>"##,
            container
        ))),
    }
}

/// Recreate a container (pull + restart)
pub async fn recreate_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    use tokio::time::{timeout, Duration};

    let result = timeout(Duration::from_secs(180), async {
        let mut ssh_pool = state.ssh_pool.write().await;
        commands::recreate_container(&mut ssh_pool, &node, &container).await
    }).await;

    match result {
        Ok(Ok(output)) => Ok(Html(format!(
            r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Recreated {}</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            container,
            html_escape(&output)
        ))),
        Ok(Err(e)) => Ok(Html(format!(
            r##"<div class="bg-red-900 border border-red-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Failed to recreate {}</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            container,
            html_escape(&e.to_string())
        ))),
        Err(_) => Ok(Html(format!(
            r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Recreate timeout for {} (3 min)</p>
                <p class="text-xs">Operation may still be running. Check manually or refresh later.</p>
            </div>"##,
            container
        ))),
    }
}

// ============================================================================
// Cleanup Routes
// ============================================================================

/// System prune - remove unused data
pub async fn system_prune(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::system_prune(&mut ssh_pool, &node).await?;

    Ok(Html(format!(
        r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">System Prune Complete</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        html_escape(&output)
    )))
}

/// Volume prune - remove unused volumes
pub async fn volume_prune(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::volume_prune(&mut ssh_pool, &node).await?;

    Ok(Html(format!(
        r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Volume Prune Complete</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        html_escape(&output)
    )))
}

/// Image prune - remove unused images
pub async fn image_prune(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::image_prune(&mut ssh_pool, &node).await?;

    Ok(Html(format!(
        r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Image Prune Complete</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        html_escape(&output)
    )))
}

/// Get disk usage stats
pub async fn disk_usage(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::disk_usage(&mut ssh_pool, &node).await?;

    Ok(Html(format!(
        r##"<div class="bg-gray-900 rounded p-3">
            <p class="font-semibold mb-2">Disk Usage</p>
            <pre class="text-xs overflow-auto">{}</pre>
        </div>"##,
        html_escape(&output)
    )))
}

// ============================================================================
// Stack/Compose Project Routes
// ============================================================================

/// Start all containers in a compose stack
pub async fn stack_up(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::stack_up(&mut ssh_pool, &node, &project).await?;

    Ok(Html(format!(
        r##"<div class="bg-green-900 border border-green-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Stack '{}' started</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        project,
        html_escape(&output)
    )))
}

/// Stop all containers in a compose stack (keeps containers, can restart)
pub async fn stack_stop(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::stack_stop(&mut ssh_pool, &node, &project).await?;

    Ok(Html(format!(
        r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Stack '{}' stopped</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        project,
        html_escape(&output)
    )))
}

/// Remove all containers in a compose stack (containers are removed)
pub async fn stack_down(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::stack_down(&mut ssh_pool, &node, &project).await?;

    Ok(Html(format!(
        r##"<div class="bg-red-900 border border-red-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Stack '{}' removed</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        project,
        html_escape(&output)
    )))
}

/// Pull latest images for a compose stack
pub async fn stack_pull(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    use tokio::time::{timeout, Duration};

    let result = timeout(Duration::from_secs(120), async {
        let mut ssh_pool = state.ssh_pool.write().await;
        commands::stack_pull(&mut ssh_pool, &node, &project).await
    }).await;

    match result {
        Ok(Ok(output)) => Ok(Html(format!(
            r##"<div class="bg-blue-900 border border-blue-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Pulled images for stack '{}'</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            project,
            html_escape(&output)
        ))),
        Ok(Err(e)) => Ok(Html(format!(
            r##"<div class="bg-red-900 border border-red-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Failed to pull stack '{}'</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            project,
            html_escape(&e.to_string())
        ))),
        Err(_) => Ok(Html(format!(
            r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Pull timeout for stack '{}' (2 min)</p>
                <p class="text-xs">The operation is likely still running on the server. Check manually or refresh later.</p>
            </div>"##,
            project
        ))),
    }
}

/// Rebuild a compose stack (pull + up --build --force-recreate)
pub async fn stack_rebuild(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    use tokio::time::{timeout, Duration};

    let result = timeout(Duration::from_secs(180), async {
        let mut ssh_pool = state.ssh_pool.write().await;
        commands::stack_rebuild(&mut ssh_pool, &node, &project).await
    }).await;

    match result {
        Ok(Ok(output)) => Ok(Html(format!(
            r##"<div class="bg-purple-900 border border-purple-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Rebuilt stack '{}'</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            project,
            html_escape(&output)
        ))),
        Ok(Err(e)) => Ok(Html(format!(
            r##"<div class="bg-red-900 border border-red-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Failed to rebuild stack '{}'</p>
                <pre class="text-xs overflow-auto max-h-32">{}</pre>
            </div>"##,
            project,
            html_escape(&e.to_string())
        ))),
        Err(_) => Ok(Html(format!(
            r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
                <p class="font-semibold mb-2">Rebuild timeout for stack '{}' (3 min)</p>
                <p class="text-xs">The operation is likely still running on the server. Check manually or refresh later.</p>
            </div>"##,
            project
        ))),
    }
}

/// Restart a compose stack
pub async fn stack_restart(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let output = commands::stack_restart(&mut ssh_pool, &node, &project).await?;

    Ok(Html(format!(
        r##"<div class="bg-yellow-900 border border-yellow-700 rounded p-3 text-sm">
            <p class="font-semibold mb-2">Restarted stack '{}'</p>
            <pre class="text-xs overflow-auto max-h-32">{}</pre>
        </div>"##,
        project,
        html_escape(&output)
    )))
}

/// Get logs for a compose stack
pub async fn stack_logs(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let logs = commands::stack_logs(&mut ssh_pool, &node, &project, 100).await?;

    let html = format!(
        r##"<div class="logs-container">
            <div class="flex justify-between items-center mb-4">
                <h3 class="text-xl font-bold">Logs: Stack '{project}'</h3>
                <button hx-get="/docker/{node}/stack/{project}/logs"
                        hx-target="#logs-content"
                        hx-swap="innerHTML"
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                    Refresh
                </button>
            </div>
            <pre id="logs-content" class="bg-gray-900 p-4 rounded overflow-auto max-h-96 text-sm font-mono">{logs}</pre>
        </div>"##,
        project = project,
        node = node,
        logs = html_escape(&logs)
    );

    Ok(Html(html))
}

// Template rendering functions

fn render_dashboard(summaries: &[NodeSummary]) -> String {
    let nodes_html: String = summaries
        .iter()
        .map(|s| render_node_card(s))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - Docker</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .node-card {{ transition: all 0.2s; }}
        .node-card:hover {{ transform: translateY(-2px); box-shadow: 0 4px 20px rgba(0,0,0,0.3); }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/docker" class="text-blue-400 hover:text-blue-300">Docker</a>
                <a href="/infra" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-semibold">Docker Nodes</h2>
            <button hx-get="/docker"
                    hx-target="body"
                    hx-swap="innerHTML"
                    class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded flex items-center gap-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                          d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
                Refresh
            </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {nodes_html}
        </div>
    </main>

    <script>
        // Auto-refresh every 30 seconds
        setInterval(function() {{
            htmx.trigger(document.body, 'htmx:load');
        }}, 30000);
    </script>
</body>
</html>"##,
        nodes_html = nodes_html
    )
}

fn render_node_card(summary: &NodeSummary) -> String {
    let status_class = if summary.online {
        "bg-green-600"
    } else {
        "bg-red-600"
    };
    let status_text = if summary.online { "Online" } else { "Offline" };

    format!(
        r##"<div class="node-card bg-gray-800 rounded-lg p-6 border border-gray-700 cursor-pointer"
             hx-get="/docker/{name}"
             hx-target="body"
             hx-swap="innerHTML">
            <div class="flex justify-between items-start mb-4">
                <div>
                    <h3 class="text-lg font-semibold">{name}</h3>
                    <p class="text-gray-400 text-sm">{host}</p>
                </div>
                <span class="px-2 py-1 {status_class} rounded text-xs">{status_text}</span>
            </div>
            <div class="grid grid-cols-3 gap-4 text-center">
                <div>
                    <p class="text-2xl font-bold text-blue-400">{total}</p>
                    <p class="text-xs text-gray-400">Total</p>
                </div>
                <div>
                    <p class="text-2xl font-bold text-green-400">{running}</p>
                    <p class="text-xs text-gray-400">Running</p>
                </div>
                <div>
                    <p class="text-2xl font-bold text-red-400">{stopped}</p>
                    <p class="text-xs text-gray-400">Stopped</p>
                </div>
            </div>
        </div>"##,
        name = summary.name,
        host = summary.host,
        status_class = status_class,
        status_text = status_text,
        total = summary.total,
        running = summary.running,
        stopped = summary.stopped
    )
}

fn render_node_stacks(node: &str, host: &str, stacks: &[ComposeStack]) -> String {
    let stacks_html: String = stacks
        .iter()
        .map(|s| render_stack_section(node, s))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - {node} Containers</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .htmx-request {{ opacity: 0.5; }}
        .stack-section {{ transition: all 0.2s; }}
        .stack-section:hover {{ border-color: #4b5563; }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/docker" class="text-blue-400 hover:text-blue-300">Docker</a>
                <a href="/infra" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex items-center gap-4 mb-6">
            <a href="/docker" class="text-blue-400 hover:text-blue-300">&larr; Back</a>
            <h2 class="text-xl font-semibold">{node}</h2>
            <span class="text-gray-400">({host})</span>
            <div class="ml-auto flex gap-2">
                <button hx-get="/docker/{node}/disk-usage"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        class="px-3 py-2 bg-gray-600 hover:bg-gray-700 rounded text-sm">
                    Disk Usage
                </button>
                <button hx-get="/docker/{node}"
                        hx-target="body"
                        hx-swap="innerHTML"
                        class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded flex items-center gap-2">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                    </svg>
                    Refresh
                </button>
            </div>
        </div>

        <!-- Cleanup Actions -->
        <div class="bg-gray-800 rounded-lg border border-gray-700 p-4 mb-6">
            <div class="flex items-center justify-between">
                <div>
                    <h3 class="font-semibold">Cleanup Actions</h3>
                    <p class="text-gray-400 text-sm">Remove unused Docker resources to free up disk space</p>
                </div>
                <div class="flex gap-2">
                    <button hx-post="/docker/{node}/prune/images"
                            hx-target="#action-result"
                            hx-swap="innerHTML"
                            hx-confirm="Remove all unused images?"
                            class="px-3 py-2 bg-orange-600 hover:bg-orange-700 rounded text-sm">
                        Prune Images
                    </button>
                    <button hx-post="/docker/{node}/prune/volumes"
                            hx-target="#action-result"
                            hx-swap="innerHTML"
                            hx-confirm="Remove all unused volumes? This may delete data!"
                            class="px-3 py-2 bg-red-600 hover:bg-red-700 rounded text-sm">
                        Prune Volumes
                    </button>
                    <button hx-post="/docker/{node}/prune/system"
                            hx-target="#action-result"
                            hx-swap="innerHTML"
                            hx-confirm="Run system prune? This removes unused containers, networks, and images."
                            class="px-3 py-2 bg-red-700 hover:bg-red-800 rounded text-sm">
                        System Prune
                    </button>
                </div>
            </div>
        </div>

        <!-- Stacks/Projects -->
        <div class="space-y-6">
            {stacks_html}
        </div>

        <!-- Floating Console Panel -->
        <div id="console-panel" class="fixed bottom-0 right-4 w-[500px] z-50 transition-all duration-300">
            <!-- Console Header (always visible) -->
            <div id="console-header"
                 onclick="toggleConsole()"
                 class="bg-gray-900 border border-gray-600 border-b-0 rounded-t-lg px-4 py-2 flex items-center justify-between cursor-pointer hover:bg-gray-800">
                <div class="flex items-center gap-2">
                    <span id="console-indicator" class="w-2 h-2 rounded-full bg-gray-500"></span>
                    <span class="font-semibold text-sm">Console</span>
                    <span id="console-badge" class="hidden px-2 py-0.5 bg-blue-600 rounded-full text-xs">new</span>
                </div>
                <div class="flex items-center gap-2">
                    <button onclick="event.stopPropagation(); clearConsole()"
                            class="text-gray-400 hover:text-white text-xs px-2 py-1">
                        Clear
                    </button>
                    <svg id="console-chevron" class="w-4 h-4 text-gray-400 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7"></path>
                    </svg>
                </div>
            </div>
            <!-- Console Body (collapsible) -->
            <div id="console-body" class="bg-gray-900 border border-gray-600 border-t-0 rounded-b-lg overflow-hidden transition-all duration-300 max-h-0">
                <div id="console-content" class="p-4 max-h-64 overflow-auto text-sm font-mono space-y-2">
                    <p class="text-gray-500 italic">No actions yet...</p>
                </div>
            </div>
        </div>

        <!-- Hidden target for htmx responses -->
        <div id="action-result" class="hidden"></div>

        <div id="logs-modal" class="hidden fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-40">
            <div class="bg-gray-800 rounded-lg p-6 w-full max-w-4xl max-h-[80vh] overflow-auto">
                <div id="logs-content"></div>
                <button onclick="document.getElementById('logs-modal').classList.add('hidden')"
                        class="mt-4 px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded">
                    Close
                </button>
            </div>
        </div>
    </main>

    <script>
        let consoleOpen = false;
        let hasNewContent = false;
        let pendingOperations = new Set();

        function toggleConsole() {{
            consoleOpen = !consoleOpen;
            const body = document.getElementById('console-body');
            const chevron = document.getElementById('console-chevron');
            const badge = document.getElementById('console-badge');

            if (consoleOpen) {{
                body.style.maxHeight = '16rem';
                chevron.style.transform = 'rotate(180deg)';
                badge.classList.add('hidden');
                hasNewContent = false;
                // Scroll to bottom
                const content = document.getElementById('console-content');
                content.scrollTop = content.scrollHeight;
            }} else {{
                body.style.maxHeight = '0';
                chevron.style.transform = 'rotate(0deg)';
            }}
        }}

        function openConsole() {{
            if (!consoleOpen) {{
                toggleConsole();
            }}
        }}

        function clearConsole() {{
            document.getElementById('console-content').innerHTML = '<p class="text-gray-500 italic">No actions yet...</p>';
            document.getElementById('console-indicator').className = 'w-2 h-2 rounded-full bg-gray-500';
        }}

        function addToConsole(html, status, id) {{
            const content = document.getElementById('console-content');
            const indicator = document.getElementById('console-indicator');
            const badge = document.getElementById('console-badge');
            const time = new Date().toLocaleTimeString('en-US', {{ hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }});

            // Remove "no actions" message
            const noActions = content.querySelector('.italic');
            if (noActions) noActions.remove();

            // If id provided, try to update existing entry
            if (id) {{
                const existing = document.getElementById('console-entry-' + id);
                if (existing) {{
                    existing.className = 'border-l-2 pl-3 py-1 ' + (status === 'success' ? 'border-green-500' : status === 'error' ? 'border-red-500' : status === 'warning' ? 'border-yellow-500' : 'border-blue-500');
                    existing.innerHTML = '<span class="text-gray-400 text-xs">' + time + '</span> ' + html;
                    content.scrollTop = content.scrollHeight;
                    // Update indicator
                    indicator.className = 'w-2 h-2 rounded-full ' + (status === 'success' ? 'bg-green-500' : status === 'error' ? 'bg-red-500' : status === 'warning' ? 'bg-yellow-500' : 'bg-blue-500');
                    return;
                }}
            }}

            // Add new entry
            const entry = document.createElement('div');
            entry.className = 'border-l-2 pl-3 py-1 ' + (status === 'success' ? 'border-green-500' : status === 'error' ? 'border-red-500' : status === 'warning' ? 'border-yellow-500' : 'border-blue-500');
            if (id) entry.id = 'console-entry-' + id;
            entry.innerHTML = '<span class="text-gray-400 text-xs">' + time + '</span> ' + html;
            content.appendChild(entry);

            // Update indicator
            indicator.className = 'w-2 h-2 rounded-full animate-pulse ' + (status === 'success' ? 'bg-green-500' : status === 'error' ? 'bg-red-500' : status === 'warning' ? 'bg-yellow-500' : 'bg-blue-500');

            // Show badge if closed
            if (!consoleOpen) {{
                badge.classList.remove('hidden');
                hasNewContent = true;
            }}

            // Auto-open and scroll
            openConsole();
            content.scrollTop = content.scrollHeight;
        }}

        // Intercept htmx before request to show "Starting..." message
        document.body.addEventListener('htmx:beforeRequest', function(evt) {{
            const target = evt.detail.target;
            if (target && target.id === 'action-result') {{
                const path = evt.detail.pathInfo.requestPath;
                const opId = Date.now().toString();
                evt.detail.opId = opId;

                // Parse action from path
                let actionName = 'Operation';
                if (path.includes('/pull')) actionName = 'Pulling';
                else if (path.includes('/rebuild')) actionName = 'Rebuilding';
                else if (path.includes('/restart')) actionName = 'Restarting';
                else if (path.includes('/stop')) actionName = 'Stopping';
                else if (path.includes('/up')) actionName = 'Starting';
                else if (path.includes('/down')) actionName = 'Removing';
                else if (path.includes('/prune')) actionName = 'Pruning';
                else if (path.includes('/recreate')) actionName = 'Recreating';

                // Extract target name from path
                const parts = path.split('/');
                let targetName = parts[parts.length - 2] || 'containers';

                // Store operation ID on the element
                evt.detail.elt.dataset.opId = opId;
                pendingOperations.add(opId);

                // Disable button
                evt.detail.elt.disabled = true;
                evt.detail.elt.classList.add('opacity-50', 'cursor-wait');

                addToConsole(
                    '<span class="animate-pulse">' + actionName + ' <strong>' + targetName + '</strong>...</span>',
                    'pending',
                    opId
                );
            }}
        }});

        // Intercept htmx responses to action-result
        document.body.addEventListener('htmx:afterRequest', function(evt) {{
            const target = evt.detail.target;
            if (target && target.id === 'action-result') {{
                const opId = evt.detail.elt.dataset.opId;

                // Re-enable button
                evt.detail.elt.disabled = false;
                evt.detail.elt.classList.remove('opacity-50', 'cursor-wait');

                if (pendingOperations.has(opId)) {{
                    pendingOperations.delete(opId);
                    const html = target.innerHTML;
                    const status = html.includes('bg-green') ? 'success' : html.includes('bg-red') ? 'error' : html.includes('bg-yellow') ? 'warning' : 'info';
                    addToConsole(html, status, opId);
                }}
            }}
        }});

        // Handle request errors
        document.body.addEventListener('htmx:responseError', function(evt) {{
            const target = evt.detail.target;
            if (target && target.id === 'action-result') {{
                const opId = evt.detail.elt.dataset.opId;

                // Re-enable button
                evt.detail.elt.disabled = false;
                evt.detail.elt.classList.remove('opacity-50', 'cursor-wait');

                if (pendingOperations.has(opId)) {{
                    pendingOperations.delete(opId);
                    addToConsole(
                        '<div class="bg-red-900 border border-red-700 rounded p-2 text-sm">Request failed: ' + evt.detail.error + '</div>',
                        'error',
                        opId
                    );
                }}
            }}
        }});

        function showLogs(node, container) {{
            document.getElementById('logs-modal').classList.remove('hidden');
            htmx.ajax('GET', '/docker/' + node + '/' + container + '/logs', '#logs-content');
        }}
        function showStackLogs(node, project) {{
            document.getElementById('logs-modal').classList.remove('hidden');
            htmx.ajax('GET', '/docker/' + node + '/stack/' + project + '/logs', '#logs-content');
        }}
    </script>
</body>
</html>"##,
        node = node,
        host = host,
        stacks_html = stacks_html
    )
}

fn render_stack_section(node: &str, stack: &ComposeStack) -> String {
    let is_standalone = stack.name == "standalone";
    let status_color = if stack.running_count == stack.total_count {
        "bg-green-600"
    } else if stack.running_count == 0 {
        "bg-red-600"
    } else {
        "bg-yellow-600"
    };

    let containers_html: String = stack.containers
        .iter()
        .map(|c| render_container_row(node, c))
        .collect::<Vec<_>>()
        .join("\n");

    // Stack actions - only for compose stacks, not standalone
    let stack_actions = if !is_standalone {
        format!(
            r##"<div class="flex gap-2">
                <button hx-post="/docker/{node}/stack/{project}/up"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        class="px-3 py-1 bg-green-600 hover:bg-green-700 rounded text-sm">
                    Start
                </button>
                <button hx-post="/docker/{node}/stack/{project}/stop"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        hx-confirm="Stop all containers in '{project}'?"
                        class="px-3 py-1 bg-yellow-600 hover:bg-yellow-700 rounded text-sm">
                    Stop
                </button>
                <button hx-post="/docker/{node}/stack/{project}/restart"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        class="px-3 py-1 bg-orange-600 hover:bg-orange-700 rounded text-sm">
                    Restart
                </button>
                <button hx-post="/docker/{node}/stack/{project}/pull"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                    Pull
                </button>
                <button hx-post="/docker/{node}/stack/{project}/rebuild"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        hx-confirm="Rebuild '{project}'? This will pull and recreate all containers."
                        class="px-3 py-1 bg-purple-600 hover:bg-purple-700 rounded text-sm">
                    Rebuild
                </button>
                <button hx-post="/docker/{node}/stack/{project}/down"
                        hx-target="#action-result"
                        hx-swap="innerHTML"
                        hx-confirm="REMOVE stack '{project}'? Containers will be deleted and disappear from this list!"
                        class="px-3 py-1 bg-red-700 hover:bg-red-800 rounded text-sm">
                    Remove
                </button>
                <button onclick="showStackLogs('{node}', '{project}')"
                        class="px-3 py-1 bg-gray-600 hover:bg-gray-700 rounded text-sm">
                    Logs
                </button>
            </div>"##,
            node = node,
            project = stack.name
        )
    } else {
        String::new()
    };

    let stack_title = if is_standalone {
        "Standalone Containers".to_string()
    } else {
        format!("Stack: {}", stack.name)
    };

    format!(
        r##"<div class="stack-section bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
            <div class="bg-gray-900 px-6 py-4 flex items-center justify-between">
                <div class="flex items-center gap-4">
                    <h3 class="font-semibold text-lg">{stack_title}</h3>
                    <span class="px-2 py-1 {status_color} rounded text-xs">
                        {running}/{total} running
                    </span>
                </div>
                {stack_actions}
            </div>
            <div class="overflow-x-auto">
                <table class="w-full min-w-[900px]">
                    <thead class="bg-gray-850">
                        <tr>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-400 uppercase">Name</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-400 uppercase">Status</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-400 uppercase">Actions</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-400 uppercase">Image</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-400 uppercase">Ports</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-700">
                        {containers_html}
                    </tbody>
                </table>
            </div>
        </div>"##,
        stack_title = stack_title,
        status_color = status_color,
        running = stack.running_count,
        total = stack.total_count,
        stack_actions = stack_actions,
        containers_html = containers_html
    )
}

fn render_container_row(node: &str, container: &Container) -> String {
    let is_running = container.status == ContainerStatus::Running;
    let status_class = container.status.css_class();
    let status_text = container.status.display();
    let short_id = if container.id.len() > 12 {
        &container.id[..12]
    } else {
        &container.id
    };

    let action_buttons = if is_running {
        format!(
            r##"<button hx-post="/docker/{node}/{name}/stop"
                       hx-target="closest tr"
                       hx-swap="outerHTML"
                       class="px-2 py-1 bg-red-600 hover:bg-red-700 rounded text-xs mr-1">
                Stop
            </button>
            <button hx-post="/docker/{node}/{name}/restart"
                       hx-target="closest tr"
                       hx-swap="outerHTML"
                       class="px-2 py-1 bg-yellow-600 hover:bg-yellow-700 rounded text-xs mr-1">
                Restart
            </button>
            <button hx-post="/docker/{node}/{name}/pull"
                       hx-target="#action-result"
                       hx-swap="innerHTML"
                       class="px-2 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs mr-1">
                Pull
            </button>
            <button hx-post="/docker/{node}/{name}/recreate"
                       hx-target="#action-result"
                       hx-swap="innerHTML"
                       hx-confirm="Recreate {name}? This will pull latest image and restart."
                       class="px-2 py-1 bg-purple-600 hover:bg-purple-700 rounded text-xs mr-1">
                Recreate
            </button>"##,
            node = node,
            name = container.name
        )
    } else {
        format!(
            r##"<button hx-post="/docker/{node}/{name}/start"
                       hx-target="closest tr"
                       hx-swap="outerHTML"
                       class="px-2 py-1 bg-green-600 hover:bg-green-700 rounded text-xs mr-1">
                Start
            </button>
            <button hx-post="/docker/{node}/{name}/pull"
                       hx-target="#action-result"
                       hx-swap="innerHTML"
                       class="px-2 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs mr-1">
                Pull
            </button>"##,
            node = node,
            name = container.name
        )
    };

    format!(
        r##"<tr id="container-{name}" class="hover:bg-gray-700">
            <td class="px-4 py-3 whitespace-nowrap">
                <div class="font-medium">{name}</div>
                <div class="text-xs text-gray-400">{short_id}</div>
            </td>
            <td class="px-4 py-3 whitespace-nowrap">
                <span class="px-2 py-1 {status_class} rounded text-xs">{status_text}</span>
            </td>
            <td class="px-4 py-3 whitespace-nowrap text-sm">
                {action_buttons}
                <button onclick="showLogs('{node}', '{name}')"
                        class="px-2 py-1 bg-gray-600 hover:bg-gray-700 rounded text-xs">
                    Logs
                </button>
            </td>
            <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300 max-w-xs truncate" title="{image}">{image}</td>
            <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300">{ports}</td>
        </tr>"##,
        name = container.name,
        short_id = short_id,
        image = html_escape(&container.image),
        status_class = status_class,
        status_text = status_text,
        ports = html_escape(&container.ports),
        action_buttons = action_buttons,
        node = node
    )
}

/// Escape HTML special characters
pub fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
