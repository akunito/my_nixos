//! Main application state and logic

use control_panel_core::Config;
use egui::{Context, Ui};
use std::sync::Arc;
use tokio::runtime::Runtime;

/// Active panel in the UI
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Panel {
    Sway,
    Docker,
    Proxmox,
    Monitoring,
    Editor,
    Infrastructure,
}

impl Panel {
    pub fn label(&self) -> &'static str {
        match self {
            Panel::Sway => "Sway",
            Panel::Docker => "Docker",
            Panel::Proxmox => "Proxmox",
            Panel::Monitoring => "Monitoring",
            Panel::Editor => "Editor",
            Panel::Infrastructure => "Infrastructure",
        }
    }

    pub fn all() -> &'static [Panel] {
        &[
            Panel::Sway,
            Panel::Docker,
            Panel::Proxmox,
            Panel::Monitoring,
            Panel::Editor,
            Panel::Infrastructure,
        ]
    }
}

/// Main application state
pub struct ControlPanelApp {
    /// Application configuration
    config: Arc<Config>,

    /// Active panel
    active_panel: Panel,

    /// Async runtime for SSH operations
    runtime: Runtime,

    /// Sway IPC availability
    sway_available: bool,

    /// UI state for each panel
    sway_state: crate::ui::sway::SwayPanelState,
    docker_state: crate::ui::docker::DockerPanelState,
    proxmox_state: crate::ui::proxmox::ProxmoxPanelState,
    monitoring_state: crate::ui::monitoring::MonitoringPanelState,
    editor_state: crate::ui::editor::EditorPanelState,
    infra_state: crate::ui::infra::InfraPanelState,
}

impl ControlPanelApp {
    pub fn new(config: Config) -> Self {
        let runtime = Runtime::new().expect("Failed to create tokio runtime");

        // Check if Sway is available
        let sway_available = check_sway_available();
        if sway_available {
            tracing::info!("Sway IPC available - enabling Sway panel");
        } else {
            tracing::info!("Sway IPC not available - Sway panel will be disabled");
        }

        // Determine initial panel based on Sway availability
        let initial_panel = if sway_available {
            Panel::Sway
        } else {
            Panel::Docker
        };

        Self {
            config: Arc::new(config),
            active_panel: initial_panel,
            runtime,
            sway_available,
            sway_state: Default::default(),
            docker_state: Default::default(),
            proxmox_state: Default::default(),
            monitoring_state: Default::default(),
            editor_state: Default::default(),
            infra_state: Default::default(),
        }
    }

    /// Render the top navigation bar
    fn render_nav_bar(&mut self, ui: &mut Ui) {
        ui.horizontal(|ui| {
            ui.heading("NixOS Control Panel");
            ui.separator();

            for panel in Panel::all() {
                // Skip Sway panel if not available
                if *panel == Panel::Sway && !self.sway_available {
                    continue;
                }

                let is_selected = self.active_panel == *panel;
                if ui
                    .selectable_label(is_selected, panel.label())
                    .clicked()
                {
                    self.active_panel = *panel;
                }
            }

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                // Status indicator
                let status_text = if self.sway_available {
                    "🟢 Local"
                } else {
                    "🔵 Remote"
                };
                ui.label(status_text);
            });
        });
    }

    /// Render the active panel content
    fn render_panel(&mut self, ctx: &Context, ui: &mut Ui) {
        match self.active_panel {
            Panel::Sway => {
                crate::ui::sway::render(ctx, ui, &mut self.sway_state);
            }
            Panel::Docker => {
                crate::ui::docker::render(
                    ctx,
                    ui,
                    &mut self.docker_state,
                    &self.config,
                    &self.runtime,
                );
            }
            Panel::Proxmox => {
                crate::ui::proxmox::render(
                    ctx,
                    ui,
                    &mut self.proxmox_state,
                    &self.config,
                    &self.runtime,
                );
            }
            Panel::Monitoring => {
                crate::ui::monitoring::render(
                    ctx,
                    ui,
                    &mut self.monitoring_state,
                    &self.config,
                );
            }
            Panel::Editor => {
                crate::ui::editor::render(
                    ctx,
                    ui,
                    &mut self.editor_state,
                    &self.config,
                );
            }
            Panel::Infrastructure => {
                crate::ui::infra::render(
                    ctx,
                    ui,
                    &mut self.infra_state,
                    &self.config,
                    &self.runtime,
                );
            }
        }
    }
}

impl eframe::App for ControlPanelApp {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        // Top panel for navigation
        egui::TopBottomPanel::top("nav_bar").show(ctx, |ui| {
            self.render_nav_bar(ui);
        });

        // Central panel for content
        egui::CentralPanel::default().show(ctx, |ui| {
            self.render_panel(ctx, ui);
        });

        // Request repaint for live updates
        ctx.request_repaint_after(std::time::Duration::from_secs(5));
    }
}

/// Check if Sway IPC is available
fn check_sway_available() -> bool {
    match swayipc::Connection::new() {
        Ok(_) => true,
        Err(e) => {
            tracing::debug!("Sway IPC not available: {}", e);
            false
        }
    }
}
