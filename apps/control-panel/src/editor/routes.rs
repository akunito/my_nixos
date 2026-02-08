//! Profile editor HTTP routes (Phase 3)

use axum::{
    extract::{Path, State},
    response::Html,
    Json,
};
use std::sync::Arc;

use crate::editor::{parser, ConfigEntry, EntryType, ProfileConfig};
use crate::error::AppError;
use crate::AppState;

/// Profile editor list
pub async fn profile_list(State(state): State<Arc<AppState>>) -> Result<Html<String>, AppError> {
    let profiles = parser::list_profiles(&state.config.dotfiles.path)?;

    let profile_cards: String = profiles
        .iter()
        .map(|p| {
            format!(
                r##"<div class="bg-gray-800 rounded-lg p-4 border border-gray-700 hover:border-gray-600 cursor-pointer"
                         hx-get="/editor/{name}"
                         hx-target="body"
                         hx-swap="innerHTML">
                    <h3 class="font-semibold">{name}</h3>
                    <p class="text-gray-400 text-sm">{name}-config.nix</p>
                </div>"##,
                name = p
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let html = format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - Editor</title>
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
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-blue-400 hover:text-blue-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <h2 class="text-xl font-semibold mb-6">Profile Editor</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {profile_cards}
        </div>
    </main>
</body>
</html>"##,
        profile_cards = profile_cards
    );

    Ok(Html(html))
}

/// Profile editor for a specific profile
pub async fn profile_editor(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Result<Html<String>, AppError> {
    let config = parser::parse_profile(&profile, &state.config.dotfiles.path)?;

    let system_flags = render_flag_section("System Settings", &config.system_settings, &profile);
    let user_flags = render_flag_section("User Settings", &config.user_settings, &profile);
    let packages = render_packages_section(&config);

    let html = format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Control Panel - {profile}</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {{ background-color: #1a1a2e; color: #eee; }}
        .toggle-switch {{
            position: relative;
            width: 48px;
            height: 24px;
        }}
        .toggle-switch input {{
            opacity: 0;
            width: 0;
            height: 0;
        }}
        .toggle-slider {{
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: #374151;
            transition: 0.3s;
            border-radius: 24px;
        }}
        .toggle-slider:before {{
            position: absolute;
            content: "";
            height: 18px;
            width: 18px;
            left: 3px;
            bottom: 3px;
            background-color: white;
            transition: 0.3s;
            border-radius: 50%;
        }}
        input:checked + .toggle-slider {{
            background-color: #22c55e;
        }}
        input:checked + .toggle-slider:before {{
            transform: translateX(24px);
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
                <a href="/proxmox" class="text-gray-400 hover:text-gray-300">Proxmox</a>
                <a href="/monitoring" class="text-gray-400 hover:text-gray-300">Monitoring</a>
                <a href="/editor" class="text-blue-400 hover:text-blue-300">Editor</a>
            </div>
        </div>
    </nav>

    <main class="container mx-auto px-6 py-8">
        <div class="flex items-center gap-4 mb-6">
            <a href="/editor" class="text-blue-400 hover:text-blue-300">&larr; Back</a>
            <h2 class="text-xl font-semibold">{profile}</h2>
            <span class="text-gray-400 text-sm">{path}</span>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {system_flags}
            {user_flags}
        </div>

        <div class="mt-6">
            {packages}
        </div>
    </main>
</body>
</html>"##,
        profile = profile,
        path = config.path,
        system_flags = system_flags,
        user_flags = user_flags,
        packages = packages
    );

    Ok(Html(html))
}

/// Toggle a flag
pub async fn toggle_flag(
    State(state): State<Arc<AppState>>,
    Path((profile, flag)): Path<(String, String)>,
) -> Result<Html<String>, AppError> {
    let new_value = parser::toggle_flag(&profile, &state.config.dotfiles.path, &flag)?;

    let html = render_toggle(&profile, &flag, new_value);
    Ok(Html(html))
}

// Helper functions

fn render_flag_section(title: &str, entries: &[ConfigEntry], profile: &str) -> String {
    let flags: String = entries
        .iter()
        .filter(|e| e.entry_type == EntryType::Boolean)
        .map(|e| {
            let checked = e.value.as_bool().unwrap_or(false);
            render_flag_row(profile, &e.key, checked, e.description.as_deref())
        })
        .collect::<Vec<_>>()
        .join("\n");

    let other_settings: String = entries
        .iter()
        .filter(|e| e.entry_type != EntryType::Boolean)
        .take(10) // Limit to 10 non-boolean entries
        .map(|e| {
            format!(
                r##"<div class="flex justify-between py-2 border-b border-gray-700">
                    <span class="text-sm">{key}</span>
                    <span class="text-gray-400 text-sm">{value}</span>
                </div>"##,
                key = e.key,
                value = e.value.display()
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
            <h3 class="text-lg font-semibold mb-4">{title}</h3>
            <div class="space-y-2">
                {flags}
            </div>
            {other}
        </div>"##,
        title = title,
        flags = flags,
        other = if other_settings.is_empty() {
            "".to_string()
        } else {
            format!(
                r##"<div class="mt-4 pt-4 border-t border-gray-700">
                    <h4 class="text-sm text-gray-400 mb-2">Other Settings</h4>
                    {}
                </div>"##,
                other_settings
            )
        }
    )
}

fn render_flag_row(profile: &str, key: &str, checked: bool, description: Option<&str>) -> String {
    let checked_attr = if checked { "checked" } else { "" };
    let desc = description.unwrap_or("");

    format!(
        r##"<div id="flag-{key}" class="flex items-center justify-between py-2 border-b border-gray-700">
            <div>
                <span class="text-sm">{key}</span>
                <p class="text-xs text-gray-500">{desc}</p>
            </div>
            <label class="toggle-switch">
                <input type="checkbox"
                       {checked_attr}
                       hx-post="/editor/{profile}/toggle/{key}"
                       hx-target="#flag-{key}"
                       hx-swap="outerHTML">
                <span class="toggle-slider"></span>
            </label>
        </div>"##,
        key = key,
        desc = desc,
        checked_attr = checked_attr,
        profile = profile
    )
}

fn render_toggle(profile: &str, key: &str, checked: bool) -> String {
    render_flag_row(profile, key, checked, None)
}

fn render_packages_section(config: &ProfileConfig) -> String {
    let system_pkgs: String = config
        .system_packages
        .iter()
        .take(20)
        .map(|p| format!("<span class=\"px-2 py-1 bg-gray-700 rounded text-xs\">{}</span>", p))
        .collect::<Vec<_>>()
        .join("\n");

    let home_pkgs: String = config
        .home_packages
        .iter()
        .take(20)
        .map(|p| format!("<span class=\"px-2 py-1 bg-gray-700 rounded text-xs\">{}</span>", p))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<div class="bg-gray-800 rounded-lg border border-gray-700 p-4">
            <h3 class="text-lg font-semibold mb-4">Packages</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                    <h4 class="text-sm text-gray-400 mb-2">System Packages ({count_sys})</h4>
                    <div class="flex flex-wrap gap-2">
                        {system_pkgs}
                        {system_more}
                    </div>
                </div>
                <div>
                    <h4 class="text-sm text-gray-400 mb-2">Home Packages ({count_home})</h4>
                    <div class="flex flex-wrap gap-2">
                        {home_pkgs}
                        {home_more}
                    </div>
                </div>
            </div>
        </div>"##,
        count_sys = config.system_packages.len(),
        count_home = config.home_packages.len(),
        system_pkgs = system_pkgs,
        home_pkgs = home_pkgs,
        system_more = if config.system_packages.len() > 20 {
            format!("<span class=\"text-gray-500 text-xs\">+{} more</span>", config.system_packages.len() - 20)
        } else {
            "".to_string()
        },
        home_more = if config.home_packages.len() > 20 {
            format!("<span class=\"text-gray-500 text-xs\">+{} more</span>", config.home_packages.len() - 20)
        } else {
            "".to_string()
        }
    )
}

/// Get profile config as JSON
pub async fn profile_json(
    State(state): State<Arc<AppState>>,
    Path(profile): Path<String>,
) -> Result<Json<ProfileConfig>, AppError> {
    let config = parser::parse_profile(&profile, &state.config.dotfiles.path)?;
    Ok(Json(config))
}
