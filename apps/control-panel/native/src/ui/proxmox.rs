//! Proxmox panel - LXC container and VM management

use crate::app::{AsyncCommand, CommandSender};
use control_panel_core::Config;
use egui::{Context, Ui};
use std::sync::Arc;

/// State for the Proxmox panel
#[derive(Default)]
pub struct ProxmoxPanelState {
    /// Container list from Proxmox
    pub containers: Vec<control_panel_core::ProxmoxContainer>,
    /// Backup jobs
    pub backup_jobs: Vec<control_panel_core::BackupJob>,
    /// Loading state
    pub loading: bool,
    /// Error message
    pub error: Option<String>,
    /// Selected container for details
    #[allow(dead_code)]
    pub selected_ctid: Option<u32>,
}

/// Render the Proxmox panel
pub fn render(
    _ctx: &Context,
    ui: &mut Ui,
    state: &mut ProxmoxPanelState,
    config: &Arc<Config>,
    command_tx: &CommandSender,
) {
    ui.heading("📦 Proxmox Container Management");
    ui.add_space(8.0);

    // Connection info
    ui.horizontal(|ui| {
        ui.label("Proxmox Host:");
        ui.strong(&config.proxmox.host);

        ui.separator();

        if ui.button("🔄 Refresh").clicked() {
            state.loading = true;
            state.error = None;
            let _ = command_tx.send(AsyncCommand::RefreshProxmox);
            tracing::info!("Proxmox refresh requested");
        }

        if state.loading {
            ui.spinner();
        }
    });

    if let Some(ref error) = state.error {
        ui.colored_label(crate::theme::colors::OFFLINE, format!("⚠️ {}", error));
    }

    ui.add_space(12.0);

    // Container list
    ui.group(|ui| {
        ui.heading("LXC Containers");
        ui.add_space(4.0);

        if state.containers.is_empty() {
            // Show profiles from config as reference
            ui.label("Configured LXC profiles:");
            for profile in &config.profiles {
                if profile.profile_type == "lxc" {
                    if let Some(ctid) = profile.ctid {
                        ui.horizontal(|ui| {
                            ui.colored_label(crate::theme::colors::UNKNOWN, "○");
                            ui.label(format!(
                                "CTID {}: {} ({})",
                                ctid, profile.name, profile.hostname
                            ));
                        });
                    }
                }
            }
            ui.add_space(8.0);
            ui.label("Click Refresh to load live status");
        } else {
            // Clone to avoid borrow issues
            let containers = state.containers.clone();
            egui::ScrollArea::vertical()
                .max_height(300.0)
                .show(ui, |ui| {
                    for container in &containers {
                        render_container_row(ui, state, container, command_tx);
                    }
                });
        }
    });

    ui.add_space(12.0);

    // Backup jobs section
    ui.group(|ui| {
        ui.heading("Backup Jobs");
        ui.add_space(4.0);

        if state.backup_jobs.is_empty() {
            ui.label("No backup jobs loaded. Click Refresh.");
        } else {
            for job in state.backup_jobs.clone() {
                ui.horizontal(|ui| {
                    let status_color = if job.enabled {
                        crate::theme::colors::ONLINE
                    } else {
                        crate::theme::colors::MUTED
                    };
                    ui.colored_label(status_color, if job.enabled { "●" } else { "○" });

                    ui.strong(&job.id);
                    ui.label(format!("Schedule: {}", job.schedule));
                    ui.label(format!("Storage: {}", job.storage));
                    ui.label(format!("VMs: {}", job.vmids));

                    if ui.small_button("▶ Run Now").clicked() {
                        tracing::info!("Run backup job: {}", job.id);
                        let _ = command_tx.send(AsyncCommand::RunBackupJob {
                            job_id: job.id.clone(),
                        });
                    }
                });
            }
        }
    });

    ui.add_space(12.0);

    // Quick actions
    ui.group(|ui| {
        ui.heading("Quick Actions");
        ui.add_space(4.0);

        ui.horizontal_wrapped(|ui| {
            if ui.button("🔄 Refresh All Status").clicked() {
                state.loading = true;
                let _ = command_tx.send(AsyncCommand::RefreshProxmox);
            }

            if ui.button("📋 Refresh Backup Jobs").clicked() {
                let _ = command_tx.send(AsyncCommand::RefreshBackupJobs);
            }
        });
    });
}

/// Render a single container row
fn render_container_row(
    ui: &mut Ui,
    _state: &mut ProxmoxPanelState,
    container: &control_panel_core::ProxmoxContainer,
    command_tx: &CommandSender,
) {
    ui.horizontal(|ui| {
        // Status indicator
        let status_color = match container.status.as_str() {
            "running" => crate::theme::colors::ONLINE,
            "stopped" => crate::theme::colors::OFFLINE,
            _ => crate::theme::colors::UNKNOWN,
        };
        ui.colored_label(status_color, "●");

        // Container info
        ui.strong(format!("CTID {}", container.ctid));
        ui.label(&container.name);
        ui.label(format!("({})", container.status));

        // Action buttons
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            match container.status.as_str() {
                "running" => {
                    if ui.small_button("⏹ Stop").clicked() {
                        tracing::info!("Stop container CTID {}", container.ctid);
                        let _ = command_tx.send(AsyncCommand::ProxmoxStop {
                            ctid: container.ctid,
                        });
                    }
                    if ui.small_button("🔄 Restart").clicked() {
                        tracing::info!("Restart container CTID {}", container.ctid);
                        let _ = command_tx.send(AsyncCommand::ProxmoxRestart {
                            ctid: container.ctid,
                        });
                    }
                }
                "stopped" => {
                    if ui.small_button("▶ Start").clicked() {
                        tracing::info!("Start container CTID {}", container.ctid);
                        let _ = command_tx.send(AsyncCommand::ProxmoxStart {
                            ctid: container.ctid,
                        });
                    }
                }
                _ => {}
            }
        });
    });
}
