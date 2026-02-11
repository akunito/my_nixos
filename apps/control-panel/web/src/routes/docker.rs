//! Docker routes

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::AppState;

/// Timestamp for console output
fn timestamp() -> String {
    chrono::Local::now().format("%H:%M:%S").to_string()
}

/// Format console output line
fn console_line(status: &str, color: &str, message: &str, output: &str) -> String {
    let ts = timestamp();
    let output_html = if output.is_empty() {
        String::new()
    } else {
        format!(
            "<pre class=\"text-gray-400 ml-4 text-xs whitespace-pre-wrap\">{}</pre>",
            html_escape(output)
        )
    };
    format!(
        r##"<div class="border-b border-gray-700 py-2">
            <span class="text-gray-500">[{}]</span>
            <span class="{}">{}</span> {}
            {}
        </div>"##,
        ts, color, status, html_escape(message), output_html
    )
}

/// Simple HTML escaping
fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Docker dashboard
pub async fn dashboard(State(_state): State<Arc<AppState>>) -> Html<String> {
    Html(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Docker - Control Panel</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>body {{ background-color: #1a1a2e; color: #eee; }}</style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/docker" class="text-blue-400">Docker</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">Docker Container Management</h2>

        <div id="docker-summary" hx-get="/docker/summary" hx-trigger="load, every 60s" hx-swap="innerHTML">
            <div class="text-gray-500">Loading nodes...</div>
        </div>
    </main>
</body>
</html>"##
    ))
}

/// Docker summary fragment (auto-refreshed)
pub async fn summary_fragment(State(state): State<Arc<AppState>>) -> Html<String> {
    let nodes_html = state
        .config
        .docker_nodes
        .iter()
        .map(|node| {
            format!(
                r##"<a href="/docker/{}" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition">
                    <h3 class="text-lg font-semibold">{}</h3>
                    <p class="text-gray-400">{}</p>
                </a>"##,
                node.name, node.name, node.host
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    Html(format!(
        r##"<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">{}</div>"##,
        nodes_html
    ))
}

/// Node containers list
pub async fn node_containers(
    State(_state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Html<String> {
    Html(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{node} - Docker</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>body {{ background-color: #1a1a2e; color: #eee; }}</style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/docker" class="text-blue-400">Docker</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex items-center gap-4 mb-6">
            <a href="/docker" class="text-gray-400 hover:text-gray-300">&larr; Back</a>
            <h2 class="text-xl font-semibold">{node}</h2>
        </div>

        <div id="container-list" hx-get="/docker/{node}/containers" hx-trigger="load, every 60s" hx-swap="innerHTML">
            <div class="text-gray-500">Loading containers...</div>
        </div>

        <!-- Console Output Panel -->
        <div class="mt-6">
            <div class="flex items-center justify-between mb-2">
                <h3 class="text-lg font-semibold">Console Output</h3>
                <button onclick="document.getElementById('console-output').innerHTML=''"
                        class="px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm">Clear</button>
            </div>
            <div id="console-output"
                 class="bg-gray-900 rounded-lg p-4 font-mono text-sm overflow-auto max-h-96 min-h-[4rem] border border-gray-700">
                <div class="text-gray-600">Console ready. Operations will appear here.</div>
            </div>
        </div>
    </main>
</body>
</html>"##,
        node = node
    ))
}

/// Containers list fragment (auto-refreshed)
pub async fn containers_fragment(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    let containers = match control_panel_core::docker::commands::list_containers(&mut ssh_pool, &node).await {
        Ok(c) => c,
        Err(e) => {
            return Html(format!(
                "<div class='text-red-500'>Error loading containers: {}</div>",
                html_escape(&e.to_string())
            ))
        }
    };

    let stacks = control_panel_core::docker::commands::group_by_stack(containers);

    let html = stacks
        .iter()
        .map(|stack| {
            let containers_html = stack
                .containers
                .iter()
                .map(|c| {
                    let status_color = match c.status {
                        control_panel_core::ContainerStatus::Running => "text-green-500",
                        control_panel_core::ContainerStatus::Exited => "text-red-500",
                        _ => "text-gray-500",
                    };
                    format!(
                        r##"<div class="flex items-center justify-between p-2 bg-gray-700 rounded">
                            <div>
                                <span class="{status_color}">{name}</span>
                                <span class="text-gray-400 ml-2 text-sm">{image}</span>
                            </div>
                            <div class="flex gap-1">
                                <button hx-post="/docker/{node}/{name}/start" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-green-700 hover:bg-green-600 rounded text-xs">Start</button>
                                <button hx-post="/docker/{node}/{name}/stop" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-red-700 hover:bg-red-600 rounded text-xs">Stop</button>
                                <button hx-post="/docker/{node}/{name}/restart" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-blue-700 hover:bg-blue-600 rounded text-xs">Restart</button>
                                <button hx-get="/docker/{node}/{name}/logs" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs">Logs</button>
                            </div>
                        </div>"##,
                        status_color = status_color,
                        name = c.name,
                        image = html_escape(&c.image),
                        node = node,
                    )
                })
                .collect::<Vec<_>>()
                .join("\n");

            // Stack-level action buttons (only for compose stacks, not standalone)
            let stack_actions = if stack.name != "standalone" {
                format!(
                    r##"<div class="flex gap-1 ml-auto">
                        <button hx-post="/docker/{node}/stack/{project}/up" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-green-700 hover:bg-green-600 rounded text-xs">Up</button>
                        <button hx-post="/docker/{node}/stack/{project}/stop" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-yellow-700 hover:bg-yellow-600 rounded text-xs">Stop</button>
                        <button hx-post="/docker/{node}/stack/{project}/restart" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-blue-700 hover:bg-blue-600 rounded text-xs">Restart</button>
                        <button hx-post="/docker/{node}/stack/{project}/pull" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-purple-700 hover:bg-purple-600 rounded text-xs">Pull</button>
                        <button hx-post="/docker/{node}/stack/{project}/rebuild" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-orange-700 hover:bg-orange-600 rounded text-xs">Rebuild</button>
                        <button hx-post="/docker/{node}/stack/{project}/down" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-red-800 hover:bg-red-700 rounded text-xs">Down</button>
                        <button hx-get="/docker/{node}/stack/{project}/logs" hx-target="#console-output" hx-swap="beforeend" class="px-2 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs">Logs</button>
                    </div>"##,
                    node = node,
                    project = stack.name,
                )
            } else {
                String::new()
            };

            format!(
                r##"<div class="bg-gray-800 p-4 rounded-lg mb-4">
                    <div class="flex items-center gap-4 mb-2">
                        <h3 class="text-lg font-semibold">{name} ({running}/{total})</h3>
                        {stack_actions}
                    </div>
                    <div class="space-y-2">{containers_html}</div>
                </div>"##,
                name = stack.name,
                running = stack.running_count,
                total = stack.total_count,
                stack_actions = stack_actions,
                containers_html = containers_html,
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    Html(html)
}

/// Start a container
pub async fn start_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::start_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(console_line("OK", "text-green-400", &format!("Start {} on {}", container, node), "")),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Start {} on {}", container, node), &e.to_string())),
    }
}

/// Stop a container
pub async fn stop_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stop_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(console_line("OK", "text-green-400", &format!("Stop {} on {}", container, node), "")),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stop {} on {}", container, node), &e.to_string())),
    }
}

/// Restart a container
pub async fn restart_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::restart_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(console_line("OK", "text-green-400", &format!("Restart {} on {}", container, node), "")),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Restart {} on {}", container, node), &e.to_string())),
    }
}

/// Get container logs
pub async fn container_logs(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::get_container_logs(&mut ssh_pool, &node, &container, 100).await {
        Ok(logs) => Html(console_line("LOGS", "text-cyan-400", &format!("{} on {}", container, node), &logs)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Logs {} on {}", container, node), &e.to_string())),
    }
}

// ============================================================================
// Docker Compose Stack Operations
// ============================================================================

/// Stack up
pub async fn stack_up(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_up(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack up '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack up '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack stop
pub async fn stack_stop(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_stop(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack stop '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack stop '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack down
pub async fn stack_down(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_down(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack down '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack down '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack restart
pub async fn stack_restart(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_restart(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack restart '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack restart '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack rebuild
pub async fn stack_rebuild(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_rebuild(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack rebuild '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack rebuild '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack pull
pub async fn stack_pull(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_pull(&mut ssh_pool, &node, &project).await {
        Ok(output) => Html(console_line("OK", "text-green-400", &format!("Stack pull '{}' on {}", project, node), &output)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack pull '{}' on {}", project, node), &e.to_string())),
    }
}

/// Stack logs
pub async fn stack_logs(
    State(state): State<Arc<AppState>>,
    Path((node, project)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stack_logs(&mut ssh_pool, &node, &project, 100).await {
        Ok(logs) => Html(console_line("LOGS", "text-cyan-400", &format!("Stack '{}' on {}", project, node), &logs)),
        Err(e) => Html(console_line("FAIL", "text-red-400", &format!("Stack logs '{}' on {}", project, node), &e.to_string())),
    }
}
