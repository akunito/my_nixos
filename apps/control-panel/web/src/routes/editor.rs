//! Profile editor routes

use axum::{
    extract::{Path, State},
    response::Html,
    Form,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::AppState;

/// List all profiles
pub async fn list_profiles(State(state): State<Arc<AppState>>) -> Html<String> {
    let profiles = control_panel_core::editor::list_profiles(&state.config.dotfiles.path)
        .unwrap_or_default();

    let profiles_html = profiles
        .iter()
        .map(|p| {
            format!(
                r##"<a href="/editor/{}" class="bg-gray-800 p-4 rounded-lg hover:bg-gray-700 transition block">
                    <h3 class="font-semibold">{}</h3>
                </a>"##,
                p, p
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
    <title>Editor - Control Panel</title>
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
                <a href="/editor" class="text-purple-400">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">📝 Profile Configuration Editor</h2>

        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {}
        </div>
    </main>
</body>
</html>"##,
        profiles_html
    ))
}

/// View and edit a profile
pub async fn view_profile(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Html<String> {
    match control_panel_core::editor::parse_profile(&profile, &state.config.dotfiles.path) {
        Ok(config) => {
            let system_settings_html = config
                .system_settings
                .iter()
                .filter(|e| e.entry_type == control_panel_core::EntryType::Boolean)
                .map(|e| {
                    let checked = e.value.as_bool().unwrap_or(false);
                    format!(
                        r##"<div class="flex items-center justify-between p-2 bg-gray-700 rounded">
                            <span>{}</span>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" {} hx-post="/editor/{}/toggle/{}" hx-swap="none" class="sr-only peer">
                                <div class="w-11 h-6 bg-gray-600 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:bg-blue-600 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all"></div>
                            </label>
                        </div>"##,
                        e.key,
                        if checked { "checked" } else { "" },
                        profile,
                        e.key
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
    <title>{} - Editor</title>
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
                <a href="/editor" class="text-purple-400">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex items-center gap-4 mb-6">
            <a href="/editor" class="text-gray-400 hover:text-gray-300">&larr; Back</a>
            <h2 class="text-xl font-semibold">📝 {}</h2>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-lg font-semibold mb-4">System Settings (Boolean Flags)</h3>
                <div class="space-y-2 max-h-96 overflow-y-auto">
                    {}
                </div>
            </div>

            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-lg font-semibold mb-4">System Packages</h3>
                <div class="space-y-1 max-h-96 overflow-y-auto">
                    {}
                </div>
            </div>
        </div>
    </main>
</body>
</html>"##,
                profile,
                profile,
                system_settings_html,
                config
                    .system_packages
                    .iter()
                    .map(|p| format!("<div class='p-1 text-gray-400'>{}</div>", p))
                    .collect::<Vec<_>>()
                    .join("\n")
            ))
        }
        Err(e) => Html(format!(
            "<div class='text-red-500'>Error loading profile: {}</div>",
            e
        )),
    }
}

/// Toggle a flag
pub async fn toggle_flag(
    State(state): State<Arc<AppState>>,
    Path((profile, flag)): Path<(String, String)>,
) -> Html<String> {
    match control_panel_core::editor::toggle_flag(&profile, &state.config.dotfiles.path, &flag) {
        Ok(new_val) => Html(format!(
            "<div class='text-green-500'>{} = {}</div>",
            flag, new_val
        )),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}

#[derive(Deserialize)]
pub struct DuplicateForm {
    new_name: String,
    new_hostname: String,
}

/// Duplicate a profile
pub async fn duplicate_profile(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
    Form(form): Form<DuplicateForm>,
) -> Html<String> {
    match control_panel_core::editor::duplicate_profile(
        &profile,
        &form.new_name,
        &form.new_hostname,
        &state.config.dotfiles.path,
    ) {
        Ok(result) => Html(format!(
            "<div class='text-green-500'>Created profile: {}</div>",
            result.profile_name
        )),
        Err(e) => Html(format!("<div class='text-red-500'>Error: {}</div>", e)),
    }
}
