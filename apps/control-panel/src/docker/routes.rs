//! Docker management HTTP routes

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::docker::commands;
use crate::docker::{Container, ContainerStatus, NodeSummary};
use crate::error::AppError;
use crate::AppState;

/// Dashboard showing all nodes with container summaries
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let mut summaries = Vec::new();

    for node in &state.config.docker_nodes {
        let mut ssh_pool = state.ssh_pool.write().await;
        let summary = commands::get_node_summary(&mut ssh_pool, &node.name, &node.host).await;
        summaries.push(summary);
    }

    let html = render_dashboard(&summaries);
    Ok(Html(html))
}

/// Show containers for a specific node
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

    let html = render_node_containers(&node, &node_config.host, &containers);
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

fn render_node_containers(node: &str, host: &str, containers: &[Container]) -> String {
    let containers_html: String = containers
        .iter()
        .map(|c| render_container_row(node, c))
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
            <button hx-get="/docker/{node}"
                    hx-target="body"
                    hx-swap="innerHTML"
                    class="ml-auto px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded flex items-center gap-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                          d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
                Refresh
            </button>
        </div>

        <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
            <table class="w-full">
                <thead class="bg-gray-900">
                    <tr>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase">Name</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase">Image</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase">Status</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase">Ports</th>
                        <th class="px-6 py-3 text-left text-xs font-medium text-gray-400 uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                    {containers_html}
                </tbody>
            </table>
        </div>

        <div id="logs-modal" class="hidden fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
            <div class="bg-gray-800 rounded-lg p-6 w-full max-w-4xl max-h-screen-80 overflow-auto">
                <div id="logs-content"></div>
                <button onclick="document.getElementById('logs-modal').classList.add('hidden')"
                        class="mt-4 px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded">
                    Close
                </button>
            </div>
        </div>
    </main>

    <script>
        function showLogs(node, container) {{
            document.getElementById('logs-modal').classList.remove('hidden');
            htmx.ajax('GET', '/docker/' + node + '/' + container + '/logs', '#logs-content');
        }}
    </script>
</body>
</html>"##,
        node = node,
        host = host,
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
            </button>"##,
            node = node,
            name = container.name
        )
    };

    format!(
        r##"<tr id="container-{name}" class="hover:bg-gray-700">
            <td class="px-6 py-4 whitespace-nowrap">
                <div class="font-medium">{name}</div>
                <div class="text-xs text-gray-400">{short_id}</div>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300">{image}</td>
            <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 py-1 {status_class} rounded text-xs">{status_text}</span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300">{ports}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm">
                {action_buttons}
                <button onclick="showLogs('{node}', '{name}')"
                        class="px-2 py-1 bg-gray-600 hover:bg-gray-700 rounded text-xs">
                    Logs
                </button>
            </td>
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
fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
