//! Editor panel - Profile configuration editing

use control_panel_core::Config;
use egui::{Context, Ui};
use std::sync::Arc;

/// State for the Editor panel
#[derive(Default)]
pub struct EditorPanelState {
    /// Available profiles
    profiles: Vec<String>,
    /// Selected profile
    selected_profile: Option<String>,
    /// Parsed profile config
    profile_config: Option<control_panel_core::ProfileConfig>,
    /// Loading state
    loading: bool,
    /// Error message
    error: Option<String>,
    /// Search filter for settings
    search_filter: String,
}

/// Render the Editor panel
pub fn render(
    _ctx: &Context,
    ui: &mut Ui,
    state: &mut EditorPanelState,
    config: &Arc<Config>,
) {
    ui.heading("📝 Profile Configuration Editor");
    ui.add_space(8.0);

    // Load profiles if not loaded
    if state.profiles.is_empty() {
        if let Ok(profiles) = control_panel_core::editor::list_profiles(&config.dotfiles.path) {
            state.profiles = profiles;
        }
    }

    // Profile selector
    ui.horizontal(|ui| {
        ui.label("Profile:");
        egui::ComboBox::from_label("")
            .selected_text(
                state
                    .selected_profile
                    .as_deref()
                    .unwrap_or("Select a profile..."),
            )
            .show_ui(ui, |ui| {
                for profile in &state.profiles {
                    if ui
                        .selectable_label(
                            state.selected_profile.as_ref() == Some(profile),
                            profile,
                        )
                        .clicked()
                    {
                        state.selected_profile = Some(profile.clone());
                        state.profile_config = None;
                        state.loading = true;
                        state.error = None;

                        // Load profile
                        match control_panel_core::editor::parse_profile(
                            profile,
                            &config.dotfiles.path,
                        ) {
                            Ok(config) => {
                                state.profile_config = Some(config);
                                state.loading = false;
                            }
                            Err(e) => {
                                state.error = Some(format!("Failed to load profile: {}", e));
                                state.loading = false;
                            }
                        }
                    }
                }
            });

        if state.loading {
            ui.spinner();
        }
    });

    if let Some(ref error) = state.error {
        ui.colored_label(crate::theme::colors::OFFLINE, format!("⚠️ {}", error));
    }

    ui.add_space(12.0);

    // Profile content
    if let Some(ref profile_config) = state.profile_config {
        // Search filter
        ui.horizontal(|ui| {
            ui.label("🔍");
            ui.text_edit_singleline(&mut state.search_filter);
            if ui.small_button("✕").clicked() {
                state.search_filter.clear();
            }
        });

        ui.add_space(8.0);

        // System Settings
        ui.collapsing("System Settings", |ui| {
            render_settings_section(
                ui,
                &profile_config.system_settings,
                &state.search_filter,
                &config.dotfiles.path,
                state.selected_profile.as_deref().unwrap_or(""),
            );
        });

        // User Settings
        ui.collapsing("User Settings", |ui| {
            render_settings_section(
                ui,
                &profile_config.user_settings,
                &state.search_filter,
                &config.dotfiles.path,
                state.selected_profile.as_deref().unwrap_or(""),
            );
        });

        // System Packages
        ui.collapsing("System Packages", |ui| {
            render_package_list(ui, &profile_config.system_packages);
        });

        // Home Packages
        ui.collapsing("Home Packages", |ui| {
            render_package_list(ui, &profile_config.home_packages);
        });

        ui.add_space(12.0);

        // Actions
        ui.horizontal(|ui| {
            if ui.button("🔄 Reload").clicked() {
                if let Some(ref profile) = state.selected_profile {
                    match control_panel_core::editor::parse_profile(profile, &config.dotfiles.path)
                    {
                        Ok(config) => {
                            state.profile_config = Some(config);
                            state.error = None;
                        }
                        Err(e) => {
                            state.error = Some(format!("Failed to reload: {}", e));
                        }
                    }
                }
            }

            if ui.button("📄 Duplicate Profile").clicked() {
                // TODO: Show duplication dialog
                tracing::info!("Duplicate profile requested");
            }
        });
    } else if state.selected_profile.is_some() && !state.loading {
        ui.label("Failed to load profile configuration");
    } else {
        ui.label("Select a profile to view and edit its configuration");
    }
}

/// Render a settings section
fn render_settings_section(
    ui: &mut Ui,
    entries: &[control_panel_core::ConfigEntry],
    filter: &str,
    dotfiles_path: &str,
    profile_name: &str,
) {
    let filter_lower = filter.to_lowercase();

    for entry in entries {
        // Apply search filter
        if !filter.is_empty()
            && !entry.key.to_lowercase().contains(&filter_lower)
            && !entry
                .description
                .as_ref()
                .map(|d| d.to_lowercase().contains(&filter_lower))
                .unwrap_or(false)
        {
            continue;
        }

        ui.horizontal(|ui| {
            // Key name
            ui.strong(&entry.key);

            // Value with type-specific rendering
            match &entry.entry_type {
                control_panel_core::EntryType::Boolean => {
                    let mut value = entry.value.as_bool().unwrap_or(false);
                    if ui.checkbox(&mut value, "").changed() {
                        // Toggle the flag
                        match control_panel_core::editor::toggle_flag(
                            profile_name,
                            dotfiles_path,
                            &entry.key,
                        ) {
                            Ok(new_val) => {
                                tracing::info!("Toggled {} to {}", entry.key, new_val);
                            }
                            Err(e) => {
                                tracing::error!("Failed to toggle {}: {}", entry.key, e);
                            }
                        }
                    }
                }
                _ => {
                    ui.label(entry.value.display());
                }
            }

            // Description tooltip
            if let Some(ref desc) = entry.description {
                ui.label(format!("// {}", desc))
                    .on_hover_text(desc);
            }
        });
    }

    if entries.is_empty()
        || (!filter.is_empty()
            && !entries.iter().any(|e| {
                e.key.to_lowercase().contains(&filter_lower)
                    || e.description
                        .as_ref()
                        .map(|d| d.to_lowercase().contains(&filter_lower))
                        .unwrap_or(false)
            }))
    {
        ui.label("No settings found");
    }
}

/// Render a package list
fn render_package_list(ui: &mut Ui, packages: &[String]) {
    if packages.is_empty() {
        ui.label("No packages defined");
    } else {
        egui::ScrollArea::vertical()
            .max_height(150.0)
            .show(ui, |ui| {
                for pkg in packages {
                    ui.horizontal(|ui| {
                        ui.label("•");
                        ui.label(pkg);
                    });
                }
            });
    }
}
