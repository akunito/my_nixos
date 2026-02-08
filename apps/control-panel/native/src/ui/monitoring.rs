//! Monitoring panel - Grafana dashboard integration

use control_panel_core::Config;
use egui::{Context, Ui};
use std::sync::Arc;

/// State for the Monitoring panel
#[derive(Default)]
pub struct MonitoringPanelState {
    /// Selected dashboard UID
    selected_dashboard: Option<String>,
}

/// Render the Monitoring panel
pub fn render(
    _ctx: &Context,
    ui: &mut Ui,
    state: &mut MonitoringPanelState,
    config: &Arc<Config>,
) {
    ui.heading("📊 Monitoring Dashboards");
    ui.add_space(8.0);

    // Get grafana config with fallback
    let grafana = config.grafana.as_ref();
    let empty_dashboards = Vec::new();
    let dashboards = grafana.map(|g| &g.dashboards).unwrap_or(&empty_dashboards);
    let base_url = grafana.map(|g| g.base_url.as_str()).unwrap_or("");

    // Dashboard selector
    ui.horizontal(|ui| {
        ui.label("Dashboard:");
        egui::ComboBox::from_label("")
            .selected_text(
                state
                    .selected_dashboard
                    .as_ref()
                    .and_then(|uid| {
                        dashboards
                            .iter()
                            .find(|d| &d.uid == uid)
                            .map(|d| d.name.as_str())
                    })
                    .unwrap_or("Select a dashboard..."),
            )
            .show_ui(ui, |ui| {
                for dashboard in dashboards {
                    let is_selected = state.selected_dashboard.as_ref() == Some(&dashboard.uid);
                    if ui
                        .selectable_label(is_selected, &dashboard.name)
                        .clicked()
                    {
                        state.selected_dashboard = Some(dashboard.uid.clone());
                    }
                }
            });
    });

    ui.add_space(12.0);

    // Dashboard info and links
    if let Some(ref uid) = state.selected_dashboard {
        if let Some(dashboard) = dashboards.iter().find(|d| &d.uid == uid) {
            ui.group(|ui| {
                ui.heading(&dashboard.name);
                ui.add_space(4.0);

                let url = control_panel_core::infra::get_dashboard_url(
                    base_url,
                    dashboard,
                );

                ui.label(format!("URL: {}", url));

                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    if ui.button("🌐 Open in Browser").clicked() {
                        if let Err(e) = open::that(&url) {
                            tracing::error!("Failed to open browser: {}", e);
                        }
                    }

                    if ui.button("📋 Copy URL").clicked() {
                        ui.output_mut(|o| o.copied_text = url.clone());
                    }
                });
            });
        }
    }

    ui.add_space(12.0);

    // Quick links to all dashboards
    ui.group(|ui| {
        ui.heading("Available Dashboards");
        ui.add_space(4.0);

        if dashboards.is_empty() {
            ui.label("No dashboards configured");
        } else {
            for dashboard in dashboards {
                ui.horizontal(|ui| {
                    ui.label(&dashboard.name);

                    if ui.small_button("Open").clicked() {
                        let url = control_panel_core::infra::get_dashboard_url(
                            base_url,
                            dashboard,
                        );
                        if let Err(e) = open::that(&url) {
                            tracing::error!("Failed to open browser: {}", e);
                        }
                    }
                });
            }
        }
    });

    ui.add_space(12.0);

    // Direct Grafana link
    ui.group(|ui| {
        ui.heading("Grafana Access");
        ui.add_space(4.0);

        ui.horizontal(|ui| {
            ui.label("Base URL:");
            ui.strong(base_url);
        });

        ui.add_space(4.0);

        if ui.button("🌐 Open Grafana Home").clicked() {
            if let Err(e) = open::that(base_url) {
                tracing::error!("Failed to open browser: {}", e);
            }
        }
    });

    ui.add_space(12.0);

    // Note about native embedding
    ui.group(|ui| {
        ui.heading("ℹ️ Note");
        ui.label("Dashboard embedding is available in the web interface.");
        ui.label("Use the buttons above to open dashboards in your browser.");
    });
}
