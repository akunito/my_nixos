//! Infrastructure HTTP routes

use axum::{
    extract::{Path, Query, State},
    response::Html,
    Json,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::error::AppError;
use crate::infra::{deploy, git, graph, monitoring};
use crate::AppState;

/// Infrastructure dashboard with profile graph
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let graph_data = graph::generate_graph_data(&state.config);
    let d3_script = graph::generate_d3_script(&graph_data);

    let html = format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - Infrastructure</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/docker" class="text-gray-400 hover:text-gray-300">Docker</a>
                <a href="/infra" class="text-blue-400 hover:text-blue-300">Infrastructure</a>
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-semibold">Profile Graph</h2>
            <div class="flex gap-2">
                <button hx-get="/infra/git/status"
                        hx-target="#git-panel"
                        class="px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded">
                    Git Status
                </button>
            </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div class="lg:col-span-2 bg-gray-800 rounded-lg border border-gray-700 p-4">
                <div id="graph-container" class="w-full" style="height: 600px;"></div>
            </div>

            <div class="space-y-4">
                <div id="details-panel" class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                    <h3 class="text-lg font-semibold mb-4">Profile Details</h3>
                    <p class="text-gray-400">Click a node to view details</p>
                </div>

                <div id="git-panel" class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                    <h3 class="text-lg font-semibold mb-4">Git Status</h3>
                    <p class="text-gray-400">Click "Git Status" to load</p>
                </div>
            </div>
        </div>

        <div class="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                <h4 class="text-sm text-gray-400 mb-2">Profile Types</h4>
                <div class="flex flex-wrap gap-2">
                    <span class="px-2 py-1 rounded text-xs" style="background-color: #4f46e5;">Desktop</span>
                    <span class="px-2 py-1 rounded text-xs" style="background-color: #0ea5e9;">Laptop</span>
                    <span class="px-2 py-1 rounded text-xs" style="background-color: #22c55e;">LXC</span>
                    <span class="px-2 py-1 rounded text-xs" style="background-color: #f59e0b;">VM</span>
                    <span class="px-2 py-1 rounded text-xs" style="background-color: #8b5cf6;">Darwin</span>
                </div>
            </div>
            <div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                <h4 class="text-sm text-gray-400 mb-2">Status</h4>
                <div class="flex flex-wrap gap-2">
                    <span class="flex items-center gap-1 text-xs">
                        <span class="w-2 h-2 rounded-full bg-green-500"></span> Online
                    </span>
                    <span class="flex items-center gap-1 text-xs">
                        <span class="w-2 h-2 rounded-full bg-red-500"></span> Offline
                    </span>
                    <span class="flex items-center gap-1 text-xs">
                        <span class="w-2 h-2 rounded-full bg-blue-500"></span> Deploying
                    </span>
                    <span class="flex items-center gap-1 text-xs">
                        <span class="w-2 h-2 rounded-full bg-gray-500"></span> Unknown
                    </span>
                </div>
            </div>
        </div>
    </main>

    <script>
{d3_script}
    </script>
</body>
</html>"##,
        d3_script = d3_script
    );

    Ok(Html(html))
}

/// Profile details
pub async fn profile_details(
    State(state): State<Arc<AppState>>,
    Path(profile_id): Path<String>,
) -> Result<Html<String>, AppError> {
    let profile = state
        .config
        .get_profile(&profile_id)
        .ok_or_else(|| AppError::NodeNotFound(profile_id.clone()))?;

    let html = format!(
        r##"<div>
            <h3 class="text-lg font-semibold mb-4">{name}</h3>
            <dl class="space-y-2">
                <div>
                    <dt class="text-gray-400 text-sm">Type</dt>
                    <dd>{profile_type}</dd>
                </div>
                <div>
                    <dt class="text-gray-400 text-sm">Hostname</dt>
                    <dd>{hostname}</dd>
                </div>
                {ip_section}
                {ctid_section}
                {base_section}
            </dl>
            <div class="mt-4 flex gap-2">
                <button hx-post="/infra/deploy/{name}/dry-run"
                        hx-target="#deploy-result"
                        class="px-3 py-1 bg-gray-600 hover:bg-gray-700 rounded text-sm">
                    Dry Run
                </button>
                <button hx-post="/infra/deploy/{name}"
                        hx-target="#deploy-result"
                        hx-confirm="Deploy to {name}?"
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                    Deploy
                </button>
            </div>
            <div id="deploy-result" class="mt-4"></div>
        </div>"##,
        name = profile.name,
        profile_type = profile.profile_type,
        hostname = profile.hostname,
        ip_section = profile.ip.as_ref().map(|ip| format!(
            r##"<div>
                <dt class="text-gray-400 text-sm">IP Address</dt>
                <dd>{}</dd>
            </div>"##,
            ip
        )).unwrap_or_default(),
        ctid_section = profile.ctid.map(|ctid| format!(
            r##"<div>
                <dt class="text-gray-400 text-sm">Proxmox CTID</dt>
                <dd>{}</dd>
            </div>"##,
            ctid
        )).unwrap_or_default(),
        base_section = profile.base_profile.as_ref().map(|base| format!(
            r##"<div>
                <dt class="text-gray-400 text-sm">Base Profile</dt>
                <dd>{}</dd>
            </div>"##,
            base
        )).unwrap_or_default(),
    );

    Ok(Html(html))
}

/// Git status panel
pub async fn git_status(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let status = git::get_status(&state.config.dotfiles.path)?;

    let modified_list = if status.modified_files.is_empty() {
        "<li class=\"text-gray-500\">No modified files</li>".to_string()
    } else {
        status.modified_files.iter()
            .map(|f| format!("<li class=\"text-yellow-400\">{}</li>", f))
            .collect::<Vec<_>>()
            .join("\n")
    };

    let untracked_list = if status.untracked_files.is_empty() {
        "".to_string()
    } else {
        format!(
            "<h5 class=\"text-sm text-gray-400 mt-2\">Untracked</h5><ul class=\"text-xs space-y-1\">{}</ul>",
            status.untracked_files.iter()
                .map(|f| format!("<li class=\"text-green-400\">{}</li>", f))
                .collect::<Vec<_>>()
                .join("\n")
        )
    };

    let html = format!(
        r##"<div>
            <h3 class="text-lg font-semibold mb-4">Git Status</h3>
            <div class="flex items-center gap-2 mb-4">
                <span class="px-2 py-1 bg-gray-700 rounded text-sm">{branch}</span>
                {ahead_behind}
            </div>
            <h5 class="text-sm text-gray-400">Modified</h5>
            <ul class="text-xs space-y-1 mb-4">
                {modified_list}
            </ul>
            {untracked_list}
            <div class="mt-4 flex gap-2">
                <button hx-get="/infra/git/diff"
                        hx-target="#diff-output"
                        class="px-3 py-1 bg-gray-600 hover:bg-gray-700 rounded text-sm">
                    View Diff
                </button>
                <button hx-post="/infra/git/pull"
                        hx-target="#git-panel"
                        class="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                    Pull
                </button>
            </div>
            <div id="diff-output" class="mt-4"></div>
        </div>"##,
        branch = status.branch,
        ahead_behind = if status.ahead > 0 || status.behind > 0 {
            format!(
                "<span class=\"text-xs text-gray-400\">↑{} ↓{}</span>",
                status.ahead, status.behind
            )
        } else {
            "".to_string()
        },
        modified_list = modified_list,
        untracked_list = untracked_list
    );

    Ok(Html(html))
}

/// Git diff view
pub async fn git_diff(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let diff = git::get_diff(&state.config.dotfiles.path)?;

    let html = format!(
        r##"<pre class="bg-gray-900 p-4 rounded text-xs overflow-auto max-h-48">{}</pre>"##,
        diff.replace('<', "&lt;").replace('>', "&gt;")
    );

    Ok(Html(html))
}

/// Pull latest changes
pub async fn git_pull(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    git::pull(&state.config.dotfiles.path)?;
    git_status(State(state)).await
}

#[derive(Debug, Deserialize)]
pub struct DashboardQuery {
    pub uid: Option<String>,
}

/// Monitoring page with Grafana embedding
pub async fn monitoring_dashboard(
    State(state): State<Arc<AppState>>,
    Query(query): Query<DashboardQuery>,
) -> Result<Html<String>, AppError> {
    let grafana = state.config.grafana.as_ref().ok_or_else(|| {
        AppError::Config("Grafana not configured".to_string())
    })?;

    let html = monitoring::render_monitoring_page(
        &grafana.dashboards,
        &grafana.base_url,
        query.uid.as_deref(),
    );

    Ok(Html(html))
}

/// Deploy dry-run
pub async fn deploy_dry_run(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Result<Html<String>, AppError> {
    let profile_config = state
        .config
        .get_profile(&profile)
        .ok_or_else(|| AppError::NodeNotFound(profile.clone()))?;

    // For dry-run, we need to execute on the target node or locally
    let node_name = if profile_config.profile_type == "lxc" {
        profile.clone()
    } else {
        // For non-LXC profiles, we might need different handling
        profile.clone()
    };

    let mut ssh_pool = state.ssh_pool.write().await;
    let status = deploy::dry_run(
        &mut ssh_pool,
        &node_name,
        &profile,
        &state.config.dotfiles.path,
    ).await?;

    let status_class = if status.status == crate::infra::DeployState::Success {
        "bg-green-900 border-green-700"
    } else {
        "bg-red-900 border-red-700"
    };

    let html = format!(
        r##"<div class="{} border rounded p-3">
            <p class="text-sm">{}</p>
        </div>"##,
        status_class,
        status.message
    );

    Ok(Html(html))
}

/// Deploy to profile
pub async fn deploy_profile(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Result<Html<String>, AppError> {
    let profile_config = state
        .config
        .get_profile(&profile)
        .ok_or_else(|| AppError::NodeNotFound(profile.clone()))?;

    let node_name = if profile_config.profile_type == "lxc" {
        profile.clone()
    } else {
        profile.clone()
    };

    let mut ssh_pool = state.ssh_pool.write().await;
    let status = deploy::deploy(
        &mut ssh_pool,
        &node_name,
        &profile,
        &state.config.dotfiles.path,
    ).await?;

    let status_class = if status.status == crate::infra::DeployState::Success {
        "bg-green-900 border-green-700"
    } else {
        "bg-red-900 border-red-700"
    };

    let html = format!(
        r##"<div class="{} border rounded p-3">
            <p class="text-sm">{}</p>
        </div>"##,
        status_class,
        status.message
    );

    Ok(Html(html))
}

/// Get graph data as JSON (for AJAX updates)
pub async fn graph_data(State(state): State<Arc<AppState>>) -> Json<graph::GraphData> {
    let data = graph::generate_graph_data(&state.config);
    Json(data)
}

/// Health check for all profiles - returns status for each
pub async fn health_check(State(state): State<Arc<AppState>>) -> Json<std::collections::HashMap<String, String>> {
    use std::collections::HashMap;

    let mut statuses = HashMap::new();

    // Check each profile that has an IP
    for profile in &state.config.profiles {
        if let Some(ip) = &profile.ip {
            // Quick ping check (1 second timeout)
            let status = match tokio::time::timeout(
                tokio::time::Duration::from_secs(1),
                check_host_reachable(ip),
            )
            .await
            {
                Ok(Ok(true)) => "online",
                Ok(Ok(false)) | Ok(Err(_)) => "offline",
                Err(_) => "offline", // timeout
            };
            statuses.insert(profile.name.clone(), status.to_string());
        } else {
            statuses.insert(profile.name.clone(), "unknown".to_string());
        }
    }

    Json(statuses)
}

/// Check if a host is reachable via TCP port 22
async fn check_host_reachable(host: &str) -> Result<bool, std::io::Error> {
    let addr = format!("{}:22", host);
    match tokio::net::TcpStream::connect(&addr).await {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

// ============================================================================
// Proxmox Routes
// ============================================================================

use crate::infra::proxmox;

/// Proxmox dashboard showing all containers and VMs
pub async fn proxmox_dashboard(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;

    let containers = proxmox::list_containers(&mut ssh_pool).await.unwrap_or_default();
    let vms = proxmox::list_vms(&mut ssh_pool).await.unwrap_or_default();

    let containers_html: String = containers
        .iter()
        .map(|c| render_proxmox_row(c, "lxc"))
        .collect::<Vec<_>>()
        .join("\n");

    let vms_html: String = vms
        .iter()
        .map(|v| render_proxmox_row(v, "vm"))
        .collect::<Vec<_>>()
        .join("\n");

    let html = format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - Proxmox</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
    </style>
</head>
<body class="min-h-screen">
    <nav class="bg-gray-800 border-b border-gray-700 px-6 py-4">
        <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-blue-400">NixOS Control Panel</h1>
            <div class="flex gap-4">
                <a href="/docker" class="text-gray-400 hover:text-gray-300">Docker</a>
                <a href="/infra" class="text-gray-400 hover:text-gray-300">Infrastructure</a>
                <a href="/proxmox" class="text-blue-400 hover:text-blue-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-xl font-semibold">Proxmox Virtual Environment</h2>
            <div class="flex items-center gap-4">
                <span class="text-gray-400 text-sm">Host: {proxmox_host}</span>
                <button hx-get="/proxmox"
                        hx-target="body"
                        class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded">
                    Refresh
                </button>
            </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- LXC Containers -->
            <div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                    <span class="w-3 h-3 bg-green-500 rounded-full"></span>
                    LXC Containers ({container_count})
                </h3>
                <table class="w-full">
                    <thead>
                        <tr class="text-left text-gray-400 text-sm">
                            <th class="pb-2">CTID</th>
                            <th class="pb-2">Name</th>
                            <th class="pb-2">Status</th>
                            <th class="pb-2">Actions</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-700">
                        {containers_html}
                    </tbody>
                </table>
            </div>

            <!-- VMs -->
            <div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
                <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                    <span class="w-3 h-3 bg-amber-500 rounded-full"></span>
                    Virtual Machines ({vm_count})
                </h3>
                <table class="w-full">
                    <thead>
                        <tr class="text-left text-gray-400 text-sm">
                            <th class="pb-2">VMID</th>
                            <th class="pb-2">Name</th>
                            <th class="pb-2">Status</th>
                            <th class="pb-2">Actions</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-700">
                        {vms_html}
                    </tbody>
                </table>
            </div>
        </div>
    </main>

    <script>
        // Auto-refresh every 30 seconds
        setInterval(() => htmx.ajax('GET', '/proxmox/containers', '#containers-body'), 30000);
    </script>
</body>
</html>"##,
        proxmox_host = state.config.proxmox.host,
        container_count = containers.len(),
        vm_count = vms.len(),
        containers_html = if containers_html.is_empty() {
            "<tr><td colspan=\"4\" class=\"py-4 text-gray-500 text-center\">No containers found</td></tr>".to_string()
        } else {
            containers_html
        },
        vms_html = if vms_html.is_empty() {
            "<tr><td colspan=\"4\" class=\"py-4 text-gray-500 text-center\">No VMs found</td></tr>".to_string()
        } else {
            vms_html
        }
    );

    Ok(Html(html))
}

fn render_proxmox_row(info: &proxmox::ContainerInfo, vm_type: &str) -> String {
    let status_class = if info.status == "running" {
        "bg-green-500"
    } else {
        "bg-red-500"
    };

    let can_start = info.status != "running";
    let can_stop = info.status == "running";

    format!(
        r##"<tr id="pve-{ctid}" class="hover:bg-gray-700">
            <td class="py-2 font-mono text-sm">{ctid}</td>
            <td class="py-2">{name}</td>
            <td class="py-2">
                <span class="inline-flex items-center gap-1">
                    <span class="w-2 h-2 rounded-full {status_class}"></span>
                    {status}
                </span>
            </td>
            <td class="py-2">
                <div class="flex gap-1">
                    <button hx-post="/proxmox/{ctid}/start"
                            hx-target="#pve-{ctid}"
                            hx-swap="outerHTML"
                            class="px-2 py-1 text-xs rounded {start_class}"
                            {start_disabled}>
                        Start
                    </button>
                    <button hx-post="/proxmox/{ctid}/stop"
                            hx-target="#pve-{ctid}"
                            hx-swap="outerHTML"
                            hx-confirm="Stop {name}?"
                            class="px-2 py-1 text-xs rounded {stop_class}"
                            {stop_disabled}>
                        Stop
                    </button>
                    <button hx-post="/proxmox/{ctid}/restart"
                            hx-target="#pve-{ctid}"
                            hx-swap="outerHTML"
                            hx-confirm="Restart {name}?"
                            class="px-2 py-1 text-xs rounded bg-yellow-600 hover:bg-yellow-700">
                        Restart
                    </button>
                </div>
            </td>
        </tr>"##,
        ctid = info.ctid,
        name = info.name,
        status = info.status,
        status_class = status_class,
        start_class = if can_start { "bg-green-600 hover:bg-green-700" } else { "bg-gray-600 cursor-not-allowed" },
        stop_class = if can_stop { "bg-red-600 hover:bg-red-700" } else { "bg-gray-600 cursor-not-allowed" },
        start_disabled = if can_start { "" } else { "disabled" },
        stop_disabled = if can_stop { "" } else { "disabled" },
    )
}

/// Get containers list (for AJAX refresh)
pub async fn proxmox_containers(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let containers = proxmox::list_containers(&mut ssh_pool).await.unwrap_or_default();

    let html: String = containers
        .iter()
        .map(|c| render_proxmox_row(c, "lxc"))
        .collect::<Vec<_>>()
        .join("\n");

    Ok(Html(html))
}

/// Start a Proxmox container
pub async fn proxmox_start(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    proxmox::start_container(&mut ssh_pool, ctid).await?;

    // Get updated status
    let status = proxmox::get_container_status(&mut ssh_pool, ctid).await?;
    let containers = proxmox::list_containers(&mut ssh_pool).await.unwrap_or_default();
    let info = containers.iter().find(|c| c.ctid == ctid);

    if let Some(info) = info {
        Ok(Html(render_proxmox_row(info, "lxc")))
    } else {
        Ok(Html(format!(
            r##"<tr id="pve-{ctid}"><td colspan="4" class="py-2 text-green-400">Started (status: {status})</td></tr>"##,
            ctid = ctid,
            status = status
        )))
    }
}

/// Stop a Proxmox container
pub async fn proxmox_stop(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    proxmox::stop_container(&mut ssh_pool, ctid).await?;

    // Get updated status
    let containers = proxmox::list_containers(&mut ssh_pool).await.unwrap_or_default();
    let info = containers.iter().find(|c| c.ctid == ctid);

    if let Some(info) = info {
        Ok(Html(render_proxmox_row(info, "lxc")))
    } else {
        Ok(Html(format!(
            r##"<tr id="pve-{ctid}"><td colspan="4" class="py-2 text-red-400">Stopped</td></tr>"##,
            ctid = ctid
        )))
    }
}

/// Restart a Proxmox container
pub async fn proxmox_restart(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Result<Html<String>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    proxmox::restart_container(&mut ssh_pool, ctid).await?;

    // Get updated status
    let containers = proxmox::list_containers(&mut ssh_pool).await.unwrap_or_default();
    let info = containers.iter().find(|c| c.ctid == ctid);

    if let Some(info) = info {
        Ok(Html(render_proxmox_row(info, "lxc")))
    } else {
        Ok(Html(format!(
            r##"<tr id="pve-{ctid}"><td colspan="4" class="py-2 text-yellow-400">Restarted</td></tr>"##,
            ctid = ctid
        )))
    }
}

/// Get status of a specific container
pub async fn proxmox_status(
    State(state): State<Arc<AppState>>,
    Path(ctid): Path<u32>,
) -> Result<Json<serde_json::Value>, AppError> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let status = proxmox::get_container_status(&mut ssh_pool, ctid).await?;

    Ok(Json(serde_json::json!({
        "ctid": ctid,
        "status": status
    })))
}
