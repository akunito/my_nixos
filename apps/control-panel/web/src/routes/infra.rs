//! Infrastructure routes (git, deploy, graph)

use axum::{
    extract::{Path, State},
    response::{Html, Json},
    Form,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::AppState;

/// Simple HTML escaping
fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Infrastructure dashboard
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Html<String> {
    Html(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Infrastructure - Control Panel</title>
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
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">Infrastructure Management</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div id="git-status-panel" hx-get="/infra/git/status-fragment" hx-trigger="load, every 60s" hx-swap="innerHTML">
                <div class="text-gray-500">Loading git status...</div>
            </div>

            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-lg font-semibold mb-4">Git Operations</h3>
                <div class="flex gap-2">
                    <button hx-post="/infra/git/pull" hx-target="#git-result" class="px-4 py-2 bg-blue-600 rounded">Pull</button>
                    <button hx-post="/infra/git/push" hx-target="#git-result" class="px-4 py-2 bg-green-600 rounded">Push</button>
                </div>
                <div id="git-result" class="mt-4"></div>
            </div>

            <div class="bg-gray-800 p-4 rounded-lg col-span-full">
                <div class="flex items-center justify-between mb-4">
                    <h3 class="text-lg font-semibold">Deploy to Profile</h3>
                    <a href="/infra/deploy-lxc" class="px-4 py-2 bg-amber-600 hover:bg-amber-700 rounded text-sm">
                        LXC Batch Deploy
                    </a>
                </div>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
                    {profiles}
                </div>
                <div id="deploy-result" class="mt-4"></div>
            </div>
        </div>
    </main>
</body>
</html>"##,
        profiles = state
            .config
            .profiles
            .iter()
            .map(|p| format!(
                r##"<button hx-post="/infra/deploy/{}" hx-target="#deploy-result" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded">{}</button>"##,
                p.name, p.name
            ))
            .collect::<Vec<_>>()
            .join("\n")
    ))
}

/// Git status fragment (auto-refreshed)
pub async fn git_status_fragment(State(state): State<Arc<AppState>>) -> Html<String> {
    let git_status = control_panel_core::infra::git::get_status(&state.config.dotfiles.path).ok();

    if let Some(status) = git_status {
        Html(format!(
            r##"<div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-lg font-semibold mb-2">Git Status</h3>
                <p>Branch: <span class="text-blue-400">{}</span></p>
                <p>Ahead: {} | Behind: {}</p>
                <p>Modified: {} | Staged: {} | Untracked: {}</p>
            </div>"##,
            status.branch,
            status.ahead,
            status.behind,
            status.modified_files.len(),
            status.staged_files.len(),
            status.untracked_files.len()
        ))
    } else {
        Html("<div class='text-red-500'>Failed to get git status</div>".to_string())
    }
}

/// Get graph data as JSON
pub async fn graph_data(State(state): State<Arc<AppState>>) -> Json<control_panel_core::GraphData> {
    let data = control_panel_core::infra::graph::generate_graph_data(&state.config);
    Json(data)
}

/// Get git status
pub async fn git_status(State(state): State<Arc<AppState>>) -> Json<Option<control_panel_core::GitStatus>> {
    let status = control_panel_core::infra::git::get_status(&state.config.dotfiles.path).ok();
    Json(status)
}

/// Get git diff
pub async fn git_diff(State(state): State<Arc<AppState>>) -> Html<String> {
    match control_panel_core::infra::git::get_diff(&state.config.dotfiles.path) {
        Ok(diff) => Html(format!(
            "<pre class='bg-gray-900 p-4 rounded overflow-auto text-sm'>{}</pre>",
            diff
        )),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Pull from remote
pub async fn git_pull(State(state): State<Arc<AppState>>) -> Html<String> {
    match control_panel_core::infra::git::pull(&state.config.dotfiles.path) {
        Ok(_) => Html("<div class='text-green-500'>Pull successful</div>".to_string()),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Push to remote
pub async fn git_push(State(state): State<Arc<AppState>>) -> Html<String> {
    match control_panel_core::infra::git::push(&state.config.dotfiles.path) {
        Ok(_) => Html("<div class='text-green-500'>Push successful</div>".to_string()),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

#[derive(Deserialize)]
pub struct CommitForm {
    message: String,
}

/// Commit changes
pub async fn git_commit(
    State(state): State<Arc<AppState>>,
    Form(form): Form<CommitForm>,
) -> Html<String> {
    match control_panel_core::infra::git::commit(&state.config.dotfiles.path, &form.message) {
        Ok(_) => Html("<div class='text-green-500'>Commit successful</div>".to_string()),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

/// Deploy to a profile (Quick Deploy - nixos-rebuild)
pub async fn deploy(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::deploy::deploy(
        &mut ssh_pool,
        &profile,
        &profile,
        &state.config.dotfiles.path,
    )
    .await
    {
        Ok(status) => {
            if status.status.is_success() {
                Html(format!(
                    "<div class='text-green-500'>Deploy to {} successful</div>",
                    profile
                ))
            } else {
                Html(format!(
                    "<div class='text-red-500'>Deploy failed: {}</div>",
                    html_escape(&status.message)
                ))
            }
        }
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", html_escape(&e.to_string()))),
    }
}

/// Dry run deployment
pub async fn dry_run(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;

    match control_panel_core::infra::deploy::dry_run(
        &mut ssh_pool,
        &profile,
        &profile,
        &state.config.dotfiles.path,
    )
    .await
    {
        Ok(status) => {
            if status.status.is_success() {
                Html(format!(
                    "<div class='text-green-500'>Dry-run for {} successful</div>",
                    profile
                ))
            } else {
                Html(format!(
                    "<div class='text-yellow-500'>Dry-run issues: {}</div>",
                    html_escape(&status.message)
                ))
            }
        }
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", html_escape(&e.to_string()))),
    }
}

// ============================================================================
// Deploy-LXC Workflow
// ============================================================================

/// LXC server definition for the deploy page
struct LxcServer {
    profile: &'static str,
    ip: &'static str,
    description: &'static str,
}

/// Static LXC server list matching deploy-lxc.sh SERVERS
const LXC_SERVERS: &[LxcServer] = &[
    LxcServer { profile: "LXC_HOME", ip: "192.168.8.80", description: "Homelab services" },
    LxcServer { profile: "LXC_proxy", ip: "192.168.8.102", description: "Cloudflare tunnel & NPM" },
    LxcServer { profile: "LXC_plane", ip: "192.168.8.86", description: "Production container" },
    LxcServer { profile: "LXC_portfolioprod", ip: "192.168.8.88", description: "Portfolio service" },
    LxcServer { profile: "LXC_mailer", ip: "192.168.8.89", description: "Mail & monitoring" },
    LxcServer { profile: "LXC_liftcraftTEST", ip: "192.168.8.87", description: "Test environment" },
    LxcServer { profile: "LXC_monitoring", ip: "192.168.8.85", description: "Prometheus & Grafana monitoring" },
    LxcServer { profile: "LXC_database", ip: "192.168.8.103", description: "Centralized PostgreSQL, MariaDB & Redis" },
];

/// Deploy-LXC page
pub async fn deploy_lxc_page(State(_state): State<Arc<AppState>>) -> Html<String> {
    let servers_html = LXC_SERVERS
        .iter()
        .map(|s| {
            format!(
                r##"<div class="flex items-center justify-between p-4 bg-gray-800 rounded-lg">
                    <div class="flex items-center gap-4">
                        <input type="checkbox" class="lxc-checkbox w-4 h-4" data-profile="{profile}" checked>
                        <div>
                            <span class="font-semibold">{profile}</span>
                            <span class="text-gray-500 ml-2">{ip}</span>
                            <p class="text-gray-400 text-sm">{desc}</p>
                        </div>
                    </div>
                    <button hx-post="/infra/deploy-lxc/{profile}"
                            hx-target="#deploy-console"
                            hx-swap="beforeend"
                            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm">
                        Deploy
                    </button>
                </div>"##,
                profile = s.profile,
                ip = s.ip,
                desc = s.description,
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
    <title>Deploy LXC - Control Panel</title>
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
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-gray-400 hover:text-gray-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex items-center gap-4 mb-6">
            <a href="/infra" class="text-gray-400 hover:text-gray-300">&larr; Back to Infra</a>
            <h2 class="text-xl font-semibold">LXC Batch Deploy</h2>
        </div>

        <p class="text-gray-400 mb-4">
            Matches <code class="bg-gray-800 px-2 py-1 rounded">deploy-lxc.sh</code> workflow:
            git fetch &rarr; git reset --hard origin/main &rarr; install.sh
        </p>

        <div class="space-y-3 mb-6">
            {servers_html}
        </div>

        <!-- Console Output -->
        <div>
            <div class="flex items-center justify-between mb-2">
                <h3 class="text-lg font-semibold">Deploy Console</h3>
                <button onclick="document.getElementById('deploy-console').innerHTML=''"
                        class="px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm">Clear</button>
            </div>
            <div id="deploy-console"
                 class="bg-gray-900 rounded-lg p-4 font-mono text-sm overflow-auto max-h-[32rem] min-h-[4rem] border border-gray-700">
                <div class="text-gray-600">Deploy console ready.</div>
            </div>
        </div>
    </main>
</body>
</html>"##,
        servers_html = servers_html
    ))
}

/// Execute deploy-lxc workflow for a single profile
pub async fn deploy_lxc_execute(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Html<String> {
    let mut ssh_pool = state.ssh_pool.write().await;
    let ts = chrono::Local::now().format("%H:%M:%S").to_string();

    let results = match control_panel_core::infra::deploy::deploy_lxc_node(
        &mut ssh_pool,
        &profile,
        &state.config.dotfiles.path,
    )
    .await
    {
        Ok(r) => r,
        Err(e) => {
            return Html(format!(
                r##"<div class="border-b border-gray-700 py-2">
                    <span class="text-gray-500">[{ts}]</span>
                    <span class="text-red-400">ERROR</span> Deploy {profile} failed: {err}
                </div>"##,
                ts = ts,
                profile = html_escape(&profile),
                err = html_escape(&e.to_string()),
            ));
        }
    };

    let all_success = results.iter().all(|r| r.success);
    let overall_color = if all_success { "text-green-400" } else { "text-red-400" };
    let overall_status = if all_success { "COMPLETE" } else { "FAILED" };

    let steps_html = results
        .iter()
        .map(|r| {
            let icon = if r.success { "text-green-400" } else { "text-red-400" };
            let status = if r.success { "OK" } else { "FAIL" };
            let output_html = if r.output.is_empty() {
                String::new()
            } else {
                format!(
                    "<pre class=\"text-gray-500 ml-8 text-xs whitespace-pre-wrap\">{}</pre>",
                    html_escape(&r.output)
                )
            };
            format!(
                r##"<div class="ml-4">
                    <span class="{icon}">[{status}]</span> {step}
                    {output_html}
                </div>"##,
                icon = icon,
                status = status,
                step = html_escape(&r.step),
                output_html = output_html,
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    Html(format!(
        r##"<div class="border-b border-gray-700 py-3">
            <span class="text-gray-500">[{ts}]</span>
            <span class="{color}">{status}</span> Deploy <span class="text-blue-400">{profile}</span>
            {steps}
        </div>"##,
        ts = ts,
        color = overall_color,
        status = overall_status,
        profile = html_escape(&profile),
        steps = steps_html,
    ))
}
