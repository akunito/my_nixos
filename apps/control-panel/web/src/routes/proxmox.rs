//! Proxmox routes

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::AppState;

/// Proxmox dashboard
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    let containers = control_panel_core::infra::proxmox::list_containers(&mut ssh_pool)
        .await
        .unwrap_or_default();

    let containers_html = containers
        .iter()
        .map(|c| {
            let status_color = match c.status.as_str() {
                "running" => "text-green-500",
                "stopped" => "text-red-500",
                _ => "text-gray-500",
            };
            format!(
                r##"<div class="flex items-center justify-between p-4 bg-gray-800 rounded-lg">
                    <div>
                        <span class="font-semibold">CTID {}</span>
                        <span class="text-gray-400 ml-2">{}</span>
                        <span class="{} ml-2">{}</span>
                    </div>
                    <div class="flex gap-2">
                        <button hx-post="/proxmox/{}/start" hx-swap="none" class="px-3 py-1 bg-green-600 rounded">Start</button>
                        <button hx-post="/proxmox/{}/stop" hx-swap="none" class="px-3 py-1 bg-red-600 rounded">Stop</button>
                        <button hx-post="/proxmox/{}/restart" hx-swap="none" class="px-3 py-1 bg-blue-600 rounded">Restart</button>
                    </div>
                </div>"##,
                c.ctid, c.name, status_color, c.status, c.ctid, c.ctid, c.ctid
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
    <title>Proxmox - Control Panel</title>
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
                <a href="/docker" class="text-gray-400 hover:text-gray-300">Docker</a>
                <a href="/proxmox" class="text-green-400">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">📦 Proxmox Container Management</h2>

        <div class="mb-4 text-gray-400">
            Host: {}
        </div>

        <div class="space-y-4">
            {}
        </div>
    </main>
</body>
</html>"##,
        state.config.proxmox.host, containers_html
    ))
}

/// Start container
pub async fn start(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::proxmox::start_container(&mut ssh_pool, ctid).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Started CTID {}</div>", ctid)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Stop container
pub async fn stop(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::proxmox::stop_container(&mut ssh_pool, ctid).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Stopped CTID {}</div>", ctid)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Restart container
pub async fn restart(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::proxmox::restart_container(&mut ssh_pool, ctid).await {
        Ok(_) => Html(format!("<div class='text-green-500'>Restarted CTID {}</div>", ctid)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Get container status
pub async fn status(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::proxmox::get_container_status(&mut ssh_pool, ctid).await {
        Ok(status) => Html(format!("<div>CTID {}: {}</div>", ctid, status)),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}
