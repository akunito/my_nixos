//! Profile graph data generation for D3.js visualization

use crate::config::Config;
use crate::infra::{NodeStatus, ProfileType};
use serde::Serialize;

/// Graph data for D3.js
#[derive(Debug, Clone, Serialize)]
pub struct GraphData {
    pub nodes: Vec<GraphNode>,
    pub links: Vec<GraphLink>,
}

/// Node in the D3.js graph
#[derive(Debug, Clone, Serialize)]
pub struct GraphNode {
    pub id: String,
    pub label: String,
    pub group: String,
    pub color: String,
    pub hostname: String,
    pub ip: Option<String>,
    pub ctid: Option<u32>,
    pub status: String,
}

/// Link in the D3.js graph
#[derive(Debug, Clone, Serialize)]
pub struct GraphLink {
    pub source: String,
    pub target: String,
    pub value: u32,
}

/// Generate graph data from configuration
pub fn generate_graph_data(config: &Config) -> GraphData {
    let mut nodes = Vec::new();
    let mut links = Vec::new();

    // Add central root node - everything connects to this
    nodes.push(GraphNode {
        id: "_root".to_string(),
        label: "Infrastructure".to_string(),
        group: "root".to_string(),
        color: "#3b82f6".to_string(), // blue
        hostname: "".to_string(),
        ip: None,
        ctid: None,
        status: "root".to_string(),
    });

    // Add category nodes for visual hierarchy
    let categories = vec![
        ("_cat_desktop", "Desktops", "#4f46e5", "desktop"),    // indigo
        ("_cat_laptop", "Laptops", "#0ea5e9", "laptop"),       // sky
        ("_cat_lxc", "LXC Containers", "#22c55e", "lxc"),      // green
        ("_cat_vm", "Virtual Machines", "#f59e0b", "vm"),      // amber
        ("_cat_darwin", "macOS", "#8b5cf6", "darwin"),         // violet
    ];

    for (id, label, color, group) in &categories {
        nodes.push(GraphNode {
            id: id.to_string(),
            label: label.to_string(),
            group: format!("category-{}", group),
            color: color.to_string(),
            hostname: "".to_string(),
            ip: None,
            ctid: None,
            status: "category".to_string(),
        });

        // Link category to root
        links.push(GraphLink {
            source: "_root".to_string(),
            target: id.to_string(),
            value: 2,
        });
    }

    // Add base profile nodes (virtual nodes representing base configs)
    let base_profiles = vec![
        ("LXC-base-config", "LXC Base", "_cat_lxc"),
        ("LAPTOP-base", "Laptop Base", "_cat_laptop"),
        ("MACBOOK-base", "MacBook Base", "_cat_darwin"),
    ];

    for (id, label, parent) in &base_profiles {
        nodes.push(GraphNode {
            id: id.to_string(),
            label: label.to_string(),
            group: "base".to_string(),
            color: "#6b7280".to_string(), // gray
            hostname: "".to_string(),
            ip: None,
            ctid: None,
            status: "base".to_string(),
        });

        // Link base to its category
        links.push(GraphLink {
            source: parent.to_string(),
            target: id.to_string(),
            value: 1,
        });
    }

    // Add profile nodes
    for profile in &config.profiles {
        let profile_type = ProfileType::from_str(&profile.profile_type);
        let _status = NodeStatus::Unknown; // Will be updated by health checks

        nodes.push(GraphNode {
            id: profile.name.clone(),
            label: profile.name.clone(),
            group: profile.profile_type.clone(),
            color: profile_type.css_color().to_string(),
            hostname: profile.hostname.clone(),
            ip: profile.ip.clone(),
            ctid: profile.ctid,
            status: "unknown".to_string(),
        });

        // Add link to base profile if specified
        if let Some(ref base) = profile.base_profile {
            links.push(GraphLink {
                source: base.clone(),
                target: profile.name.clone(),
                value: 1,
            });
        } else {
            // Link directly to category if no base profile
            let category = match profile.profile_type.as_str() {
                "desktop" => "_cat_desktop",
                "laptop" => "_cat_laptop",
                "lxc" => "_cat_lxc",
                "vm" => "_cat_vm",
                "darwin" => "_cat_darwin",
                _ => "_root",
            };
            links.push(GraphLink {
                source: category.to_string(),
                target: profile.name.clone(),
                value: 1,
            });
        }
    }

    GraphData { nodes, links }
}

/// Get a simple list of profile info (for non-graph UIs)
pub fn get_profile_list(config: &Config) -> Vec<ProfileInfo> {
    config
        .profiles
        .iter()
        .map(|p| ProfileInfo {
            name: p.name.clone(),
            profile_type: ProfileType::from_str(&p.profile_type),
            hostname: p.hostname.clone(),
            ip: p.ip.clone(),
            ctid: p.ctid,
            base_profile: p.base_profile.clone(),
        })
        .collect()
}

/// Simple profile info for list views
#[derive(Debug, Clone)]
pub struct ProfileInfo {
    pub name: String,
    pub profile_type: ProfileType,
    pub hostname: String,
    pub ip: Option<String>,
    pub ctid: Option<u32>,
    pub base_profile: Option<String>,
}
