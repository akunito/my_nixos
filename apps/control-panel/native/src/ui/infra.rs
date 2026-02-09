//! Infrastructure panel - Git operations and deployments

use crate::app::{AsyncCommand, CommandSender};
use control_panel_core::Config;
use egui::{Context, Ui};
use std::sync::Arc;

/// State for the Infrastructure panel
#[derive(Default)]
pub struct InfraPanelState {
    /// Git status
    pub git_status: Option<control_panel_core::GitStatus>,
    /// Git diff output
    pub git_diff: String,
    /// Deployment status per profile
    pub deployment_status:
        std::collections::HashMap<String, control_panel_core::DeploymentStatus>,
    /// Selected profile for deployment
    pub selected_profile: Option<String>,
    /// Loading state
    pub loading: bool,
    /// Error message
    pub error: Option<String>,
    /// Commit message input
    pub commit_message: String,
}

/// Render the Infrastructure panel
pub fn render(
    _ctx: &Context,
    ui: &mut Ui,
    state: &mut InfraPanelState,
    config: &Arc<Config>,
    command_tx: &CommandSender,
) {
    ui.heading("🏗️ Infrastructure Management");
    ui.add_space(8.0);

    // Refresh button
    ui.horizontal(|ui| {
        if ui.button("🔄 Refresh Status").clicked() {
            state.loading = true;
            state.error = None;

            // Load git status synchronously for now (local operation)
            match control_panel_core::infra::git::get_status(&config.dotfiles.path) {
                Ok(status) => {
                    state.git_status = Some(status);
                }
                Err(e) => {
                    state.error = Some(format!("Failed to get git status: {}", e));
                }
            }

            match control_panel_core::infra::git::get_diff(&config.dotfiles.path) {
                Ok(diff) => {
                    state.git_diff = diff;
                }
                Err(e) => {
                    if state.error.is_none() {
                        state.error = Some(format!("Failed to get diff: {}", e));
                    }
                }
            }

            state.loading = false;
        }

        if state.loading {
            ui.spinner();
        }
    });

    if let Some(ref error) = state.error {
        ui.colored_label(crate::theme::colors::OFFLINE, format!("⚠️ {}", error));
    }

    ui.add_space(12.0);

    // Git Status section
    ui.group(|ui| {
        ui.heading("📂 Git Status");
        ui.add_space(4.0);

        if let Some(ref status) = state.git_status {
            ui.horizontal(|ui| {
                ui.label("Branch:");
                ui.strong(&status.branch);

                if status.ahead > 0 {
                    ui.colored_label(
                        crate::theme::colors::WARNING,
                        format!("↑{} ahead", status.ahead),
                    );
                }
                if status.behind > 0 {
                    ui.colored_label(
                        crate::theme::colors::WARNING,
                        format!("↓{} behind", status.behind),
                    );
                }
            });

            ui.add_space(4.0);

            // File counts
            ui.horizontal(|ui| {
                if !status.modified_files.is_empty() {
                    ui.colored_label(
                        crate::theme::colors::WARNING,
                        format!("{} modified", status.modified_files.len()),
                    );
                }
                if !status.staged_files.is_empty() {
                    ui.colored_label(
                        crate::theme::colors::ONLINE,
                        format!("{} staged", status.staged_files.len()),
                    );
                }
                if !status.untracked_files.is_empty() {
                    ui.colored_label(
                        crate::theme::colors::MUTED,
                        format!("{} untracked", status.untracked_files.len()),
                    );
                }

                if !status.has_changes() {
                    ui.colored_label(crate::theme::colors::ONLINE, "✓ Clean");
                }
            });

            // Show changed files in collapsible
            if status.has_changes() {
                ui.collapsing("Changed Files", |ui| {
                    for file in &status.modified_files {
                        ui.horizontal(|ui| {
                            ui.colored_label(crate::theme::colors::WARNING, "M");
                            ui.label(file);
                        });
                    }
                    for file in &status.staged_files {
                        ui.horizontal(|ui| {
                            ui.colored_label(crate::theme::colors::ONLINE, "S");
                            ui.label(file);
                        });
                    }
                    for file in &status.untracked_files {
                        ui.horizontal(|ui| {
                            ui.colored_label(crate::theme::colors::MUTED, "?");
                            ui.label(file);
                        });
                    }
                });
            }
        } else {
            ui.label("Git status not loaded. Click Refresh.");
        }
    });

    ui.add_space(12.0);

    // Git Operations section
    ui.group(|ui| {
        ui.heading("Git Operations");
        ui.add_space(4.0);

        ui.horizontal(|ui| {
            ui.label("Commit message:");
            ui.text_edit_singleline(&mut state.commit_message);
        });

        ui.add_space(4.0);

        ui.horizontal_wrapped(|ui| {
            if ui.button("📥 Pull").clicked() {
                tracing::info!("Git pull requested");
                state.loading = true;
                let _ = command_tx.send(AsyncCommand::GitPull);
            }

            if ui.button("📤 Push").clicked() {
                tracing::info!("Git push requested");
                state.loading = true;
                let _ = command_tx.send(AsyncCommand::GitPush);
            }

            let can_commit = state
                .git_status
                .as_ref()
                .map(|s| s.has_changes())
                .unwrap_or(false)
                && !state.commit_message.is_empty();

            ui.add_enabled_ui(can_commit, |ui| {
                if ui.button("✓ Commit & Push").clicked() {
                    tracing::info!("Commit: {}", state.commit_message);
                    state.loading = true;
                    let _ = command_tx.send(AsyncCommand::GitCommit {
                        message: state.commit_message.clone(),
                        files: vec![], // Empty = stage all changes
                    });
                }
            });
        });
    });

    ui.add_space(12.0);

    // Deployment section
    ui.group(|ui| {
        ui.heading("🚀 Deployment");
        ui.add_space(4.0);

        // Profile selector for deployment
        ui.horizontal(|ui| {
            ui.label("Target Profile:");
            egui::ComboBox::from_label("")
                .selected_text(
                    state
                        .selected_profile
                        .as_deref()
                        .unwrap_or("Select profile..."),
                )
                .show_ui(ui, |ui| {
                    for profile in &config.profiles {
                        if ui
                            .selectable_label(
                                state.selected_profile.as_ref() == Some(&profile.name),
                                &profile.name,
                            )
                            .clicked()
                        {
                            state.selected_profile = Some(profile.name.clone());
                        }
                    }
                });
        });

        ui.add_space(4.0);

        ui.horizontal_wrapped(|ui| {
            let profile_selected = state.selected_profile.is_some();

            ui.add_enabled_ui(profile_selected, |ui| {
                if ui.button("🔍 Dry Run").clicked() {
                    if let Some(ref profile) = state.selected_profile {
                        tracing::info!("Dry run for profile: {}", profile);
                        state.loading = true;
                        let _ = command_tx.send(AsyncCommand::DeployDryRun {
                            profile: profile.clone(),
                        });
                    }
                }

                if ui.button("🚀 Deploy").clicked() {
                    if let Some(ref profile) = state.selected_profile {
                        tracing::info!("Deploy to profile: {}", profile);
                        state.loading = true;
                        let _ = command_tx.send(AsyncCommand::Deploy {
                            profile: profile.clone(),
                        });
                    }
                }
            });
        });

        // Show deployment status
        if !state.deployment_status.is_empty() {
            ui.add_space(8.0);
            ui.label("Deployment Status:");
            for (profile, status) in &state.deployment_status {
                ui.horizontal(|ui| {
                    let color = if status.status.is_success() {
                        crate::theme::colors::ONLINE
                    } else if status.status.is_failed() {
                        crate::theme::colors::OFFLINE
                    } else {
                        crate::theme::colors::DEPLOYING
                    };

                    ui.colored_label(color, "●");
                    ui.label(profile);
                    ui.label(&status.message);
                });
            }
        }
    });

    ui.add_space(12.0);

    // Profile Overview
    ui.group(|ui| {
        ui.heading("Profile Overview");
        ui.add_space(4.0);

        egui::ScrollArea::vertical()
            .max_height(200.0)
            .show(ui, |ui| {
                for profile in &config.profiles {
                    ui.horizontal(|ui| {
                        // Type indicator color
                        let type_color = match profile.profile_type.as_str() {
                            "desktop" => crate::theme::colors::DESKTOP,
                            "laptop" => crate::theme::colors::LAPTOP,
                            "lxc" => crate::theme::colors::LXC,
                            "vm" => crate::theme::colors::VM,
                            "darwin" => crate::theme::colors::DARWIN,
                            _ => crate::theme::colors::UNKNOWN,
                        };
                        ui.colored_label(type_color, "●");

                        ui.strong(&profile.name);
                        ui.label(format!("({})", profile.hostname));

                        if let Some(ref ip) = profile.ip {
                            ui.label(ip);
                        }

                        if let Some(ctid) = profile.ctid {
                            ui.label(format!("CTID: {}", ctid));
                        }
                    });
                }
            });
    });
}
