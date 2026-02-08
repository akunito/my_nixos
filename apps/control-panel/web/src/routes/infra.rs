//! Infrastructure routes (git, deploy, graph)

use axum::{
    extract::{Path, State},
    response::{Html, Json},
    Form,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::AppState;

/// Infrastructure dashboard
pub async fn dashboard(State(state): State<Arc<AppState>>) -> Html<String> {
    let git_status = control_panel_core::infra::git::get_status(&state.config.dotfiles.path)
        .ok();

    let status_html = if let Some(status) = git_status {
        format!(
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
        )
    } else {
        "<div class='text-red-500'>Failed to get git status</div>".to_string()
    };

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
        <h2 class="text-xl font-semibold mb-6">🏗️ Infrastructure Management</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            {}

            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-lg font-semibold mb-4">Git Operations</h3>
                <div class="flex gap-2">
                    <button hx-post="/infra/git/pull" hx-target="#git-result" class="px-4 py-2 bg-blue-600 rounded">Pull</button>
                    <button hx-post="/infra/git/push" hx-target="#git-result" class="px-4 py-2 bg-green-600 rounded">Push</button>
                </div>
                <div id="git-result" class="mt-4"></div>
            </div>

            <div class="bg-gray-800 p-4 rounded-lg col-span-full">
                <h3 class="text-lg font-semibold mb-4">Deploy to Profile</h3>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
                    {}
                </div>
            </div>
        </div>
    </main>
</body>
</html>"##,
        status_html,
        state
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

/// Deploy to a profile
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
                    status.message
                ))
            }
        }
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
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
                    status.message
                ))
            }
        }
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}
