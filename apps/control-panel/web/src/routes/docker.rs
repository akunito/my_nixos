//! Docker routes

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::AppState;

/// Docker dashboard
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Html<String> {
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
        <h2 class="text-xl font-semibold mb-6">🐳 Docker Container Management</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {}
        </div>
    </main>
</body>
</html>"##,
        state
            .config
            .docker_nodes
            .iter()
            .map(|node| format!(
                r##"<a href="/docker/{}" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition">
                    <h3 class="text-lg font-semibold">{}</h3>
                    <p class="text-gray-400">{}</p>
                </a>"##,
                node.name, node.name, node.host
            ))
            .collect::<Vec<_>>()
            .join("\n")
    ))
}

/// Node containers list
pub async fn node_containers(
    State(state): State<Arc<AppState>>,
    Path(node): Path<String>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    let containers = match control_panel_core::docker::commands::list_containers(&mut ssh_pool, &node).await {
        Ok(c) => c,
        Err(e) => {
            return Html(format!(
                "<div class='text-red-500'>Error loading containers: {}</div>",
                e
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
                                <span class="{}">{}</span>
                                <span class="text-gray-400 ml-2">{}</span>
                            </div>
                            <div class="flex gap-2">
                                <button hx-post="/docker/{}/{}/start" hx-swap="none" class="px-2 py-1 bg-green-600 rounded text-sm">Start</button>
                                <button hx-post="/docker/{}/{}/stop" hx-swap="none" class="px-2 py-1 bg-red-600 rounded text-sm">Stop</button>
                                <button hx-post="/docker/{}/{}/restart" hx-swap="none" class="px-2 py-1 bg-blue-600 rounded text-sm">Restart</button>
                            </div>
                        </div>"##,
                        status_color, c.name, c.image, node, c.name, node, c.name, node, c.name
                    )
                })
                .collect::<Vec<_>>()
                .join("\n");

            format!(
                r##"<div class="bg-gray-800 p-4 rounded-lg mb-4">
                    <h3 class="text-lg font-semibold mb-2">{} ({}/{})</h3>
                    <div class="space-y-2">{}</div>
                </div>"##,
                stack.name, stack.running_count, stack.total_count, containers_html
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    Html(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{} - Docker</title>
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
            <h2 class="text-xl font-semibold">🐳 {}</h2>
        </div>

        {}
    </main>
</body>
</html>"##,
        node, node, html
    ))
}

/// Start a container
pub async fn start_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::start_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Started {}</div>", container)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Stop a container
pub async fn stop_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::stop_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Stopped {}</div>", container)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Restart a container
pub async fn restart_container(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::restart_container(&mut ssh_pool, &node, &container).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Restarted {}</div>", container)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Get container logs
pub async fn container_logs(
    State(state): State<Arc<AppState>>,
    Path((node, container)): Path<(String, String)>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::docker::commands::get_container_logs(&mut ssh_pool, &node, &container, 100).await {
        Ok(logs) => Html(format!(
            "<pre class='bg-gray-900 p-4 rounded overflow-auto max-h-96 text-sm'>{}</pre>",
            logs
        )),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}
