//! Infrastructure control module
//!
//! - Proxmox container management
//! - NixOS deployment
//! - Git operations
//! - Profile graph visualization
//! - Grafana embedding

pub mod deploy;
pub mod git;
pub mod graph;
pub mod monitoring;
pub mod proxmox;
pub mod routes;

use serde::{Deserialize, Serialize};

/// Profile node for graph visualization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileNode {
    pub id: String,
    pub profile_type: ProfileType,
    pub hostname: String,
    pub ip: Option<String>,
    pub ctid: Option<u32>,
    pub status: NodeStatus,
    pub base_profile: Option<String>,
}

/// Profile type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ProfileType {
    Desktop,
    Laptop,
    Lxc,
    Vm,
    Darwin,
}

impl ProfileType {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "desktop" => ProfileType::Desktop,
            "laptop" => ProfileType::Laptop,
            "lxc" => ProfileType::Lxc,
            "vm" => ProfileType::Vm,
            "darwin" => ProfileType::Darwin,
            _ => ProfileType::Lxc,
        }
    }

    pub fn css_color(&self) -> &'static str {
        match self {
            ProfileType::Desktop => "#4f46e5", // indigo
            ProfileType::Laptop => "#0ea5e9",  // sky
            ProfileType::Lxc => "#22c55e",     // green
            ProfileType::Vm => "#f59e0b",      // amber
            ProfileType::Darwin => "#8b5cf6",  // violet
        }
    }
}

/// Node status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum NodeStatus {
    Online,
    Offline,
    Deploying,
    Error,
    Unknown,
}

impl NodeStatus {
    pub fn css_class(&self) -> &'static str {
        match self {
            NodeStatus::Online => "bg-green-500",
            NodeStatus::Offline => "bg-red-500",
            NodeStatus::Deploying => "bg-blue-500",
            NodeStatus::Error => "bg-orange-500",
            NodeStatus::Unknown => "bg-gray-500",
        }
    }
}

/// Deployment status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeploymentStatus {
    pub profile: String,
    pub status: DeployState,
    pub message: String,
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub finished_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum DeployState {
    Pending,
    DryRun,
    Building,
    Switching,
    Success,
    Failed,
}

/// Git status information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub branch: String,
    pub ahead: u32,
    pub behind: u32,
    pub modified_files: Vec<String>,
    pub untracked_files: Vec<String>,
    pub staged_files: Vec<String>,
}
