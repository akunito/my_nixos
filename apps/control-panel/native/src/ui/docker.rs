//! Docker panel - Container management across LXC nodes

use crate::app::{AsyncCommand, CommandSender};
use control_panel_core::Config;
use egui::{Context, Ui};
use std::collections::HashMap;
use std::sync::Arc;

/// State for the Docker panel
#[derive(Default)]
pub struct DockerPanelState {
    /// Selected node
    pub selected_node: Option<String>,
    /// Container data per node
    pub containers: HashMap<String, Vec<control_panel_core::Container>>,
    /// Node summaries
    pub node_summaries: Vec<control_panel_core::NodeSummary>,
    /// Loading state
    pub loading: bool,
    /// Last error
    pub error: Option<String>,
    /// Selected container for logs
    pub selected_container: Option<(String, String)>, // (node, container_name)
    /// Container logs
    pub logs: String,
    /// Last refresh time
    #[allow(dead_code)]
    pub last_refresh: Option<std::time::Instant>,
}

/// Render the Docker panel
pub fn render(
    _ctx: &Context,
    ui: &mut Ui,
    state: &mut DockerPanelState,
    config: &Arc<Config>,
    command_tx: &CommandSender,
) {
    ui.heading("🐳 Docker Container Management");
    ui.add_space(8.0);

    // Refresh button
    ui.horizontal(|ui| {
        if ui.button("🔄 Refresh").clicked() {
            state.loading = true;
            state.error = None;
            let _ = command_tx.send(AsyncCommand::RefreshDocker);
            tracing::info!("Docker refresh requested");
        }

        if state.loading {
            ui.spinner();
        }

        if let Some(ref error) = state.error {
            ui.colored_label(crate::theme::colors::OFFLINE, format!("⚠️ {}", error));
        }
    });

    ui.add_space(12.0);

    // Node selector
    ui.horizontal(|ui| {
        ui.label("Node:");
        egui::ComboBox::from_label("")
            .selected_text(
                state
                    .selected_node
                    .as_deref()
                    .unwrap_or("Select a node..."),
            )
            .show_ui(ui, |ui| {
                ui.selectable_value(&mut state.selected_node, None, "All Nodes");
                for node in &config.docker_nodes {
                    ui.selectable_value(
                        &mut state.selected_node,
                        Some(node.name.clone()),
                        &node.name,
                    );
                }
            });
    });

    ui.add_space(12.0);

    // Node summaries
    if state.selected_node.is_none() {
        ui.group(|ui| {
            ui.heading("Node Overview");
            ui.add_space(4.0);

            if state.node_summaries.is_empty() {
                // Show configured nodes with placeholder data
                for node in &config.docker_nodes {
                    ui.horizontal(|ui| {
                        ui.colored_label(crate::theme::colors::UNKNOWN, "○");
                        ui.label(&node.name);
                        ui.label(format!("({})", node.host));
                        ui.label("- Not loaded");
                    });
                }

                ui.add_space(8.0);
                ui.label("Click Refresh to load container data");
            } else {
                for summary in &state.node_summaries {
                    ui.horizontal(|ui| {
                        let status_color = if summary.online {
                            crate::theme::colors::ONLINE
                        } else {
                            crate::theme::colors::OFFLINE
                        };

                        ui.colored_label(status_color, if summary.online { "●" } else { "○" });
                        ui.strong(&summary.name);
                        ui.label(format!("({})", summary.host));

                        if summary.online {
                            ui.label(format!(
                                "{} running / {} total",
                                summary.running, summary.total
                            ));
                        } else {
                            ui.colored_label(crate::theme::colors::MUTED, "Offline");
                        }
                    });
                }
            }
        });
    }

    // Container list for selected node
    if let Some(ref node_name) = state.selected_node.clone() {
        // Clone containers to avoid borrow issues
        let containers_clone = state.containers.get(node_name.as_str()).cloned();

        ui.group(|ui| {
            ui.heading(format!("Containers on {}", node_name));
            ui.add_space(4.0);

            if let Some(containers) = containers_clone {
                if containers.is_empty() {
                    ui.label("No containers found");
                } else {
                    egui::ScrollArea::vertical()
                        .max_height(400.0)
                        .show(ui, |ui| {
                            for container in &containers {
                                render_container_row(ui, state, &node_name, container, command_tx);
                            }
                        });
                }
            } else {
                ui.label("Container data not loaded. Click Refresh.");
            }
        });
    }

    // Container logs section
    if let Some((ref node, ref container)) = state.selected_container.clone() {
        ui.add_space(12.0);
        ui.group(|ui| {
            ui.horizontal(|ui| {
                ui.heading(format!("Logs: {} ({})", container, node));
                if ui.button("🔄 Refresh Logs").clicked() {
                    let _ = command_tx.send(AsyncCommand::FetchLogs {
                        node: node.clone(),
                        container: container.clone(),
                    });
                }
                if ui.button("✕ Close").clicked() {
                    state.selected_container = None;
                    state.logs.clear();
                }
            });

            ui.add_space(4.0);

            egui::ScrollArea::vertical()
                .max_height(200.0)
                .stick_to_bottom(true)
                .show(ui, |ui| {
                    ui.add(
                        egui::TextEdit::multiline(&mut state.logs.as_str())
                            .font(egui::TextStyle::Monospace)
                            .desired_width(f32::INFINITY)
                            .desired_rows(10),
                    );
                });
        });
    }
}

/// Render a single container row
fn render_container_row(
    ui: &mut Ui,
    state: &mut DockerPanelState,
    node_name: &str,
    container: &control_panel_core::Container,
    command_tx: &CommandSender,
) {
    ui.horizontal(|ui| {
        // Status indicator
        let status_color = match container.status {
            control_panel_core::ContainerStatus::Running => crate::theme::colors::ONLINE,
            control_panel_core::ContainerStatus::Exited => crate::theme::colors::OFFLINE,
            control_panel_core::ContainerStatus::Paused => crate::theme::colors::WARNING,
            _ => crate::theme::colors::UNKNOWN,
        };
        ui.colored_label(status_color, "●");

        // Container name
        ui.strong(&container.name);

        // Image (truncated)
        let image_display = if container.image.len() > 30 {
            format!("{}...", &container.image[..27])
        } else {
            container.image.clone()
        };
        ui.label(image_display);

        // Stack/project if available
        if let Some(ref project) = container.project {
            ui.label(format!("[{}]", project));
        }

        // Action buttons
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.small_button("📋 Logs").clicked() {
                state.selected_container = Some((node_name.to_string(), container.name.clone()));
                state.logs = "Loading logs...".to_string();
                let _ = command_tx.send(AsyncCommand::FetchLogs {
                    node: node_name.to_string(),
                    container: container.name.clone(),
                });
            }

            match container.status {
                control_panel_core::ContainerStatus::Running => {
                    if ui.small_button("⏹ Stop").clicked() {
                        tracing::info!("Stop container: {}", container.name);
                        let _ = command_tx.send(AsyncCommand::StopContainer {
                            node: node_name.to_string(),
                            container: container.name.clone(),
                        });
                    }
                    if ui.small_button("🔄 Restart").clicked() {
                        tracing::info!("Restart container: {}", container.name);
                        let _ = command_tx.send(AsyncCommand::RestartContainer {
                            node: node_name.to_string(),
                            container: container.name.clone(),
                        });
                    }
                }
                _ => {
                    if ui.small_button("▶ Start").clicked() {
                        tracing::info!("Start container: {}", container.name);
                        let _ = command_tx.send(AsyncCommand::StartContainer {
                            node: node_name.to_string(),
                            container: container.name.clone(),
                        });
                    }
                }
            }
        });
    });
}
