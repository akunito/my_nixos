//! Grafana dashboard embedding

use crate::config::GrafanaDashboard;

/// Generate embedded Grafana dashboard iframe URL
pub fn get_dashboard_url(base_url: &str, dashboard: &GrafanaDashboard) -> String {
    format!(
        "{}/d/{}/{}?orgId=1&kiosk",
        base_url, dashboard.uid, dashboard.slug
    )
}

/// Generate dashboard selector HTML
pub fn render_dashboard_selector(
    dashboards: &[GrafanaDashboard],
    current_uid: &str,
) -> String {
    let options: String = dashboards
        .iter()
        .map(|d| {
            let selected = if d.uid == current_uid { " selected" } else { "" };
            format!(
                r##"<option value="{uid}"{selected}>{name}</option>"##,
                uid = d.uid,
                selected = selected,
                name = d.name
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<select id="dashboard-selector"
                hx-get="/monitoring"
                hx-target="body"
                hx-trigger="change"
                class="bg-gray-700 text-white rounded px-4 py-2 border border-gray-600">
            {options}
        </select>"##,
        options = options
    )
}

/// Render the monitoring page with embedded Grafana
pub fn render_monitoring_page(
    dashboards: &[GrafanaDashboard],
    base_url: &str,
    current_uid: Option<&str>,
) -> String {
    let current = current_uid.unwrap_or_else(|| {
        dashboards.first().map(|d| d.uid.as_str()).unwrap_or("")
    });

    let dashboard = dashboards.iter().find(|d| d.uid == current);

    let iframe_url = dashboard
        .map(|d| get_dashboard_url(base_url, d))
        .unwrap_or_default();

    let dashboard_name = dashboard.map(|d| d.name.as_str()).unwrap_or("Dashboard");
    let selector = render_dashboard_selector(dashboards, current);

    format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - Monitoring</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .grafana-frame {{
            width: 100%;
            height: calc(100vh - 180px);
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
                <a href="/docker" class="text-gray-400 hover:text-gray-300">Docker</a>
                <a href="/infra" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/monitoring" class="text-blue-400 hover:text-blue-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex justify-between items-center mb-6">
            <div class="flex items-center gap-4">
                <h2 class="text-xl font-semibold">{dashboard_name}</h2>
                {selector}
            </div>
            <div class="flex gap-2">
                <button onclick="document.querySelector('.grafana-frame').requestFullscreen()"
                        class="px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded flex items-center gap-2">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                              d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"></path>
                    </svg>
                    Full Screen
                </button>
                <a href="{base_url}" target="_blank"
                   class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded flex items-center gap-2">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                              d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                    </svg>
                    Open Grafana
                </a>
            </div>
        </div>

        <iframe
            id="grafana-frame"
            class="grafana-frame"
            src="{iframe_url}"
            frameborder="0"
            allowfullscreen>
        </iframe>
    </main>
</body>
</html>"##,
        dashboard_name = dashboard_name,
        selector = selector,
        base_url = base_url,
        iframe_url = iframe_url
    )
}
