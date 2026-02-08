//! NixOS Infrastructure Control Panel - Native Desktop App
//!
//! A native egui application for managing NixOS infrastructure with direct Sway IPC support.

mod app;
mod theme;
mod ui;

use anyhow::Result;
use std::path::PathBuf;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,control_panel=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting NixOS Control Panel");

    // Determine config path
    let config_path = std::env::var("CONFIG_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // Try common locations
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            let dotfiles = format!("{}/.dotfiles", home);
            PathBuf::from(format!("{}/apps/control-panel/config.toml", dotfiles))
        });

    // Load configuration
    let config = if config_path.exists() {
        tracing::info!("Loading config from: {:?}", config_path);
        let content = std::fs::read_to_string(&config_path)?;
        toml::from_str(&content)?
    } else {
        tracing::warn!("Config not found at {:?}, using defaults", config_path);
        control_panel_core::Config::default()
    };

    // Create application state
    let app = app::ControlPanelApp::new(config);

    // Run the native GUI
    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("NixOS Control Panel")
            .with_inner_size([1280.0, 800.0])
            .with_min_inner_size([800.0, 600.0]),
        ..Default::default()
    };

    eframe::run_native(
        "NixOS Control Panel",
        native_options,
        Box::new(|cc| {
            // Setup custom fonts and style
            theme::configure_fonts(&cc.egui_ctx);
            theme::configure_style(&cc.egui_ctx);
            Ok(Box::new(app))
        }),
    )
    .map_err(|e| anyhow::anyhow!("Failed to run native app: {}", e))?;

    Ok(())
}
