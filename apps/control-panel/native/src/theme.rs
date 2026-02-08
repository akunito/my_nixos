//! Application theme and styling

use egui::{Color32, Context, FontFamily, FontId, Rounding, Stroke, Style, TextStyle, Visuals};

/// Configure custom fonts
pub fn configure_fonts(ctx: &Context) {
    let mut fonts = egui::FontDefinitions::default();

    // Use the default fonts but ensure monospace is available
    fonts
        .families
        .entry(FontFamily::Monospace)
        .or_default()
        .push("Hack".to_owned());

    ctx.set_fonts(fonts);
}

/// Configure the application style (dark theme)
pub fn configure_style(ctx: &Context) {
    let mut style = Style::default();

    // Use dark visuals as base
    style.visuals = Visuals::dark();

    // Customize colors
    style.visuals.window_fill = Color32::from_rgb(26, 26, 46); // #1a1a2e
    style.visuals.panel_fill = Color32::from_rgb(26, 26, 46);
    style.visuals.extreme_bg_color = Color32::from_rgb(16, 16, 32);
    style.visuals.faint_bg_color = Color32::from_rgb(36, 36, 56);

    // Widget styling
    style.visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(45, 55, 72); // gray-700
    style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(55, 65, 81); // gray-600
    style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(75, 85, 99); // gray-500
    style.visuals.widgets.active.bg_fill = Color32::from_rgb(59, 130, 246); // blue-500

    // Accent colors
    style.visuals.selection.bg_fill = Color32::from_rgb(59, 130, 246); // blue-500
    style.visuals.hyperlink_color = Color32::from_rgb(96, 165, 250); // blue-400

    // Borders and rounding
    style.visuals.widgets.noninteractive.rounding = Rounding::same(4.0);
    style.visuals.widgets.inactive.rounding = Rounding::same(4.0);
    style.visuals.widgets.hovered.rounding = Rounding::same(4.0);
    style.visuals.widgets.active.rounding = Rounding::same(4.0);

    style.visuals.window_rounding = Rounding::same(8.0);

    // Strokes
    style.visuals.widgets.noninteractive.bg_stroke = Stroke::new(1.0, Color32::from_rgb(55, 65, 81));
    style.visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, Color32::from_rgb(75, 85, 99));

    // Text styles
    style.text_styles = [
        (TextStyle::Heading, FontId::new(24.0, FontFamily::Proportional)),
        (TextStyle::Body, FontId::new(14.0, FontFamily::Proportional)),
        (TextStyle::Monospace, FontId::new(13.0, FontFamily::Monospace)),
        (TextStyle::Button, FontId::new(14.0, FontFamily::Proportional)),
        (TextStyle::Small, FontId::new(12.0, FontFamily::Proportional)),
    ]
    .into();

    // Spacing
    style.spacing.item_spacing = egui::vec2(8.0, 6.0);
    style.spacing.button_padding = egui::vec2(12.0, 6.0);
    style.spacing.window_margin = egui::Margin::same(12.0);

    ctx.set_style(style);
}

/// Color palette for the application
pub mod colors {
    use egui::Color32;

    // Status colors
    pub const ONLINE: Color32 = Color32::from_rgb(34, 197, 94); // green-500
    pub const OFFLINE: Color32 = Color32::from_rgb(239, 68, 68); // red-500
    pub const WARNING: Color32 = Color32::from_rgb(245, 158, 11); // amber-500
    pub const DEPLOYING: Color32 = Color32::from_rgb(59, 130, 246); // blue-500
    pub const UNKNOWN: Color32 = Color32::from_rgb(107, 114, 128); // gray-500

    // Profile type colors
    pub const DESKTOP: Color32 = Color32::from_rgb(79, 70, 229); // indigo-600
    pub const LAPTOP: Color32 = Color32::from_rgb(14, 165, 233); // sky-500
    pub const LXC: Color32 = Color32::from_rgb(34, 197, 94); // green-500
    pub const VM: Color32 = Color32::from_rgb(245, 158, 11); // amber-500
    pub const DARWIN: Color32 = Color32::from_rgb(139, 92, 246); // violet-500

    // UI colors
    pub const ACCENT: Color32 = Color32::from_rgb(59, 130, 246); // blue-500
    pub const ACCENT_HOVER: Color32 = Color32::from_rgb(37, 99, 235); // blue-600
    pub const MUTED: Color32 = Color32::from_rgb(156, 163, 175); // gray-400
    pub const BORDER: Color32 = Color32::from_rgb(55, 65, 81); // gray-700
}
