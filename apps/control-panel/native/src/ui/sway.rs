//! Sway panel - Direct IPC integration for local Sway sessions

use egui::{Context, Ui};
use swayipc::{Connection, Output, Workspace};

/// State for the Sway panel
#[derive(Default)]
pub struct SwayPanelState {
    /// Cached workspaces
    workspaces: Vec<Workspace>,
    /// Cached outputs (monitors)
    outputs: Vec<Output>,
    /// Currently focused window title
    focused_title: Option<String>,
    /// Last refresh time
    last_refresh: Option<std::time::Instant>,
    /// Error message if any
    error: Option<String>,
}

impl SwayPanelState {
    fn refresh(&mut self) {
        let now = std::time::Instant::now();

        // Only refresh every second
        if let Some(last) = self.last_refresh {
            if now.duration_since(last) < std::time::Duration::from_secs(1) {
                return;
            }
        }

        self.last_refresh = Some(now);
        self.error = None;

        match Connection::new() {
            Ok(mut conn) => {
                // Get workspaces
                match conn.get_workspaces() {
                    Ok(ws) => self.workspaces = ws,
                    Err(e) => self.error = Some(format!("Failed to get workspaces: {}", e)),
                }

                // Get outputs
                match conn.get_outputs() {
                    Ok(outs) => self.outputs = outs,
                    Err(e) => {
                        if self.error.is_none() {
                            self.error = Some(format!("Failed to get outputs: {}", e));
                        }
                    }
                }

                // Get focused window
                match conn.get_tree() {
                    Ok(tree) => {
                        self.focused_title = find_focused_window(&tree);
                    }
                    Err(_) => {}
                }
            }
            Err(e) => {
                self.error = Some(format!("Failed to connect to Sway: {}", e));
            }
        }
    }
}

/// Find the focused window in the tree
fn find_focused_window(node: &swayipc::Node) -> Option<String> {
    if node.focused {
        return node.name.clone();
    }

    for child in &node.nodes {
        if let Some(name) = find_focused_window(child) {
            return Some(name);
        }
    }

    for child in &node.floating_nodes {
        if let Some(name) = find_focused_window(child) {
            return Some(name);
        }
    }

    None
}

/// Run a Sway command
fn run_sway_command(cmd: &str) -> Result<(), String> {
    match Connection::new() {
        Ok(mut conn) => {
            conn.run_command(cmd)
                .map_err(|e| format!("Command failed: {}", e))?;
            Ok(())
        }
        Err(e) => Err(format!("Failed to connect: {}", e)),
    }
}

/// Launch an application using app-toggle.sh
fn launch_app(app_id: &str, cmd: &str) {
    let full_cmd = format!(
        "exec ~/.config/sway/scripts/app-toggle.sh {} {}",
        app_id, cmd
    );
    if let Err(e) = run_sway_command(&full_cmd) {
        tracing::error!("Failed to launch {}: {}", app_id, e);
    }
}

/// Render the Sway panel
pub fn render(_ctx: &Context, ui: &mut Ui, state: &mut SwayPanelState) {
    state.refresh();

    ui.heading("🖥️ Sway Session Control");
    ui.add_space(8.0);

    if let Some(ref error) = state.error {
        ui.colored_label(crate::theme::colors::OFFLINE, format!("⚠️ {}", error));
        ui.add_space(8.0);
    }

    // Quick Launch section
    ui.group(|ui| {
        ui.heading("Quick Launch");
        ui.add_space(4.0);

        ui.horizontal_wrapped(|ui| {
            if ui.button("🖥️ Displays\nHyper+⇧+D").clicked() {
                launch_app("nwg-displays", "nwg-displays");
            }

            if ui.button("🔊 Audio\nHyper+S").clicked() {
                launch_app("pavucontrol", "pavucontrol");
            }

            if ui.button("📶 Bluetooth\nHyper+A").clicked() {
                launch_app("blueman-manager", "blueman-manager");
            }

            if ui.button("🔒 Tailscale\nHyper+⇧+T").clicked() {
                launch_app("trayscale", "trayscale --gapplication-service");
            }

            if ui.button("📁 Files\nHyper+E").clicked() {
                launch_app("thunar", "thunar");
            }

            if ui.button("🌐 Browser\nHyper+B").clicked() {
                launch_app("firefox", "firefox");
            }
        });
    });

    ui.add_space(12.0);

    // Workspaces section
    ui.group(|ui| {
        ui.heading("Workspaces");
        ui.add_space(4.0);

        ui.horizontal_wrapped(|ui| {
            for i in 1..=10 {
                let ws = state.workspaces.iter().find(|w| w.num == i);
                let is_focused = ws.map(|w| w.focused).unwrap_or(false);
                let is_visible = ws.map(|w| w.visible).unwrap_or(false);

                let label = if is_focused {
                    format!("[{}●]", i)
                } else if is_visible {
                    format!("[{}]", i)
                } else if ws.is_some() {
                    format!("[{}]", i)
                } else {
                    format!(" {} ", i)
                };

                let button = egui::Button::new(label);
                let response = if is_focused {
                    ui.add(button.fill(crate::theme::colors::ACCENT))
                } else if ws.is_some() {
                    ui.add(button.fill(crate::theme::colors::BORDER))
                } else {
                    ui.add(button)
                };

                if response.clicked() {
                    let _ = run_sway_command(&format!("workspace {}", i));
                }
            }
        });
    });

    ui.add_space(12.0);

    // Monitors section
    ui.group(|ui| {
        ui.heading("Monitors");
        ui.add_space(4.0);

        for output in &state.outputs {
            ui.horizontal(|ui| {
                let status_color = if output.active {
                    crate::theme::colors::ONLINE
                } else {
                    crate::theme::colors::OFFLINE
                };

                ui.colored_label(
                    status_color,
                    if output.active { "●" } else { "○" },
                );

                ui.label(&output.name);

                if let Some(mode) = &output.current_mode {
                    ui.label(format!(
                        "{}x{} @ {}Hz",
                        mode.width, mode.height, mode.refresh / 1000
                    ));
                }

                if output.focused {
                    ui.label("(focused)");
                }
            });
        }

        if state.outputs.is_empty() {
            ui.label("No outputs detected");
        }
    });

    ui.add_space(12.0);

    // Focused window section
    ui.group(|ui| {
        ui.heading("Focused Window");
        ui.add_space(4.0);

        if let Some(ref title) = state.focused_title {
            ui.label(title);
        } else {
            ui.label("No window focused");
        }
    });

    ui.add_space(12.0);

    // Keyboard shortcuts reference
    ui.collapsing("⌨️ Keyboard Shortcuts", |ui| {
        ui.horizontal_wrapped(|ui| {
            ui.label("Mod+Enter: Terminal");
            ui.separator();
            ui.label("Mod+D: App Launcher");
            ui.separator();
            ui.label("Mod+Shift+Q: Close");
        });
        ui.horizontal_wrapped(|ui| {
            ui.label("Mod+1-0: Workspaces");
            ui.separator();
            ui.label("Mod+Shift+1-0: Move to Workspace");
        });
        ui.horizontal_wrapped(|ui| {
            ui.label("Mod+H/J/K/L: Focus Direction");
            ui.separator();
            ui.label("Mod+Shift+H/J/K/L: Move Window");
        });
        ui.horizontal_wrapped(|ui| {
            ui.label("Mod+F: Fullscreen");
            ui.separator();
            ui.label("Mod+V: Split Vertical");
            ui.separator();
            ui.label("Mod+B: Split Horizontal");
        });
    });
}
