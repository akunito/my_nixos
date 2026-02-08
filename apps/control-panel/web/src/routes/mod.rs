//! Web routes for the control panel

pub mod auth;
pub mod docker;
pub mod editor;
pub mod infra;
pub mod monitoring;
pub mod proxmox;

use axum::response::Html;
use std::sync::Arc;

use crate::AppState;

/// Index page handler
pub async fn index(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> Html<String> {
    let graph_data = control_panel_core::infra::graph::generate_graph_data(&state.config);
    let graph_json = serde_json::to_string(&graph_data).unwrap_or_default();

    Html(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NixOS Control Panel</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .nav-link {{ @apply text-gray-400 hover:text-gray-300 px-3 py-2; }}
        .nav-link.active {{ @apply text-blue-400; }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/" class="nav-link active">Infrastructure</a>
                <a href="/docker" class="nav-link">Docker</a>
                <a href="/proxmox" class="nav-link">Proxmox</a>
                <a href="/monitoring" class="nav-link">Monitoring</a>
                <a href="/editor" class="nav-link">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">Infrastructure Overview</h2>

        <div id="graph-container" class="bg-gray-800 rounded-lg p-4 mb-6" style="height: 500px;">
            <svg id="graph" width="100%" height="100%"></svg>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <a href="/docker" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition">
                <h3 class="text-lg font-semibold text-blue-400">🐳 Docker</h3>
                <p class="text-gray-400">Manage containers across LXC nodes</p>
            </a>
            <a href="/proxmox" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition">
                <h3 class="text-lg font-semibold text-green-400">📦 Proxmox</h3>
                <p class="text-gray-400">Control LXC containers and VMs</p>
            </a>
            <a href="/infra" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition">
                <h3 class="text-lg font-semibold text-amber-400">🏗️ Infrastructure</h3>
                <p class="text-gray-400">Git operations and deployments</p>
            </a>
        </div>
    </main>

    <script>
        const graphData = {graph_json};

        // D3.js force-directed graph
        const svg = d3.select("#graph");
        const width = document.getElementById("graph-container").clientWidth;
        const height = 500;

        const simulation = d3.forceSimulation(graphData.nodes)
            .force("link", d3.forceLink(graphData.links).id(d => d.id).distance(80))
            .force("charge", d3.forceManyBody().strength(-200))
            .force("center", d3.forceCenter(width / 2, height / 2));

        const link = svg.append("g")
            .selectAll("line")
            .data(graphData.links)
            .join("line")
            .attr("stroke", "#555")
            .attr("stroke-opacity", 0.6)
            .attr("stroke-width", d => Math.sqrt(d.value));

        const node = svg.append("g")
            .selectAll("g")
            .data(graphData.nodes)
            .join("g")
            .call(d3.drag()
                .on("start", dragstarted)
                .on("drag", dragged)
                .on("end", dragended));

        node.append("circle")
            .attr("r", d => d.group === "root" ? 20 : d.status === "category" ? 15 : 10)
            .attr("fill", d => d.color);

        node.append("text")
            .attr("x", 15)
            .attr("y", 4)
            .attr("fill", "#eee")
            .attr("font-size", "12px")
            .text(d => d.label);

        node.append("title")
            .text(d => d.hostname ? `${{d.label}} (${{d.hostname}})` : d.label);

        simulation.on("tick", () => {{
            link
                .attr("x1", d => d.source.x)
                .attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x)
                .attr("y2", d => d.target.y);

            node.attr("transform", d => `translate(${{d.x}},${{d.y}})`);
        }});

        function dragstarted(event) {{
            if (!event.active) simulation.alphaTarget(0.3).restart();
            event.subject.fx = event.subject.x;
            event.subject.fy = event.subject.y;
        }}

        function dragged(event) {{
            event.subject.fx = event.x;
            event.subject.fy = event.y;
        }}

        function dragended(event) {{
            if (!event.active) simulation.alphaTarget(0);
            event.subject.fx = null;
            event.subject.fy = null;
        }}
    </script>
</body>
</html>"##,
        graph_json = graph_json
    ))
}
