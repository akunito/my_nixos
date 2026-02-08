//! Grafana dashboard embedding

use crate::config::GrafanaDashboard;

/// Generate embedded Grafana dashboard iframe URL
pub fn get_dashboard_url(base_url: &str, dashboard: &GrafanaDashboard) -> String {
    format!(
        "{}/d/{}/{}?orgId=1&kiosk",
        base_url, dashboard.uid, dashboard.slug
    )
}

/// Generate dashboard selector HTML (for web interface)
pub fn render_dashboard_selector(
    dashboards: &[GrafanaDashboard],
    current_uid: &str,
) -> String {
    let options: String = dashboards
        .iter()
        .map(|d| {
            let selected = if d.uid == current_uid { " selected" } else { "" };
            format!(
                r##"<option value="{uid}"{selected}>{name}</option>"##,
                uid = d.uid,
                selected = selected,
                name = d.name
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r##"<select id="dashboard-selector"
            hx-get="/monitoring"
            hx-target="body"
            hx-trigger="change"
            class="bg-gray-700 text-white rounded px-4 py-2 border border-gray-600">
            {options}
        </select>"##,
        options = options
    )
}

/// Get list of available dashboards
pub fn get_available_dashboards(dashboards: &[GrafanaDashboard]) -> Vec<DashboardInfo> {
    dashboards
        .iter()
        .map(|d| DashboardInfo {
            uid: d.uid.clone(),
            name: d.name.clone(),
            slug: d.slug.clone(),
        })
        .collect()
}

/// Dashboard info for UI display
#[derive(Debug, Clone)]
pub struct DashboardInfo {
    pub uid: String,
    pub name: String,
    pub slug: String,
}
