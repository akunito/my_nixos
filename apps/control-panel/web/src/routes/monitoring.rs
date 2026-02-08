//! Monitoring routes (Grafana embedding)

use axum::{
    extract::{Path, State},
    response::Html,
};
use std::sync::Arc;

use crate::AppState;

/// Monitoring dashboard
pub async fn dashboard(
    State(state): State<Arc<AppState>>,
    path: Option<Path<String>>,
) -> Html<String> {
    // Get grafana config with fallback to empty
    let grafana = state.config.grafana.as_ref();
    let empty_dashboards = Vec::new();
    let dashboards = grafana.map(|g| &g.dashboards).unwrap_or(&empty_dashboards);
    let base_url = grafana.map(|g| g.base_url.as_str()).unwrap_or("");

    let current_uid = path
        .as_ref()
        .map(|p| p.0.as_str())
        .or_else(|| dashboards.first().map(|d| d.uid.as_str()))
        .unwrap_or("");

    let dashboard = dashboards.iter().find(|d| d.uid == current_uid);

    let iframe_url = dashboard
        .map(|d| control_panel_core::infra::get_dashboard_url(base_url, d))
        .unwrap_or_default();

    let dashboard_name = dashboard.map(|d| d.name.as_str()).unwrap_or("Dashboard");

    let selector_html = dashboards
        .iter()
        .map(|d| {
            let selected = if d.uid == current_uid { " selected" } else { "" };
            format!(
                r##"<option value="{}" {}>{}</option>"##,
                d.uid, selected, d.name
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
    <title>Monitoring - Control Panel</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .grafana-frame {{
            width: 100%;
            height: calc(100vh - 200px);
            border: 1px solid #374151;
            border-radius: 8px;
        }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/docker" class="text-gray-400 hover:text-gray-300">Docker</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-amber-400">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex justify-between items-center mb-6">
            <div class="flex items-center gap-4">
                <h2 class="text-xl font-semibold">📊 {}</h2>
                <select onchange="window.location.href='/monitoring/' + this.value"
                        class="bg-gray-700 text-white rounded px-4 py-2 border border-gray-600">
                    {}
                </select>
            </div>
            <div class="flex gap-2">
                <button onclick="document.querySelector('.grafana-frame').requestFullscreen()"
                        class="px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded flex items-center gap-2">
                    Full Screen
                </button>
                <a href="{}" target="_blank"
                   class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded flex items-center gap-2">
                    Open Grafana
                </a>
            </div>
        </div>

        <iframe
            id="grafana-frame"
            class="grafana-frame"
            src="{}"
            frameborder="0"
            allowfullscreen>
        </iframe>
    </main>
</body>
</html>"##,
        dashboard_name, selector_html, base_url, iframe_url
    ))
}
