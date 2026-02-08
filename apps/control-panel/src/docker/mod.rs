//! Docker container management module

pub mod commands;
pub mod routes;

use serde::{Deserialize, Serialize};

/// Docker container information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Container {
    pub id: String,
    pub name: String,
    pub image: String,
    pub status: ContainerStatus,
    pub ports: String,
    pub created: String,
    pub project: Option<String>,  // docker-compose project name
}

/// Docker compose stack/project
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposeStack {
    pub name: String,
    pub path: Option<String>,  // path to docker-compose.yml if known
    pub containers: Vec<Container>,
    pub running_count: usize,
    pub total_count: usize,
}

/// Container status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ContainerStatus {
    Running,
    Exited,
    Paused,
    Restarting,
    Dead,
    Unknown,
}

impl ContainerStatus {
    /// Parse status from docker ps output
    pub fn from_str(s: &str) -> Self {
        let s_lower = s.to_lowercase();
        if s_lower.contains("up") || s_lower.starts_with("running") {
            ContainerStatus::Running
        } else if s_lower.contains("exited") {
            ContainerStatus::Exited
        } else if s_lower.contains("paused") {
            ContainerStatus::Paused
        } else if s_lower.contains("restarting") {
            ContainerStatus::Restarting
        } else if s_lower.contains("dead") {
            ContainerStatus::Dead
        } else {
            ContainerStatus::Unknown
        }
    }

    /// Get CSS class for status badge
    #[allow(dead_code)]
    pub fn css_class(&self) -> &'static str {
        match self {
            ContainerStatus::Running => "bg-green-600",
            ContainerStatus::Exited => "bg-red-600",
            ContainerStatus::Paused => "bg-yellow-600",
            ContainerStatus::Restarting => "bg-blue-600",
            ContainerStatus::Dead => "bg-gray-600",
            ContainerStatus::Unknown => "bg-gray-500",
        }
    }

    /// Get display text
    pub fn display(&self) -> &'static str {
        match self {
            ContainerStatus::Running => "Running",
            ContainerStatus::Exited => "Exited",
            ContainerStatus::Paused => "Paused",
            ContainerStatus::Restarting => "Restarting",
            ContainerStatus::Dead => "Dead",
            ContainerStatus::Unknown => "Unknown",
        }
    }
}

/// Node status summary
#[derive(Debug, Clone, Serialize)]
pub struct NodeSummary {
    pub name: String,
    pub host: String,
    pub total: usize,
    pub running: usize,
    pub stopped: usize,
    pub online: bool,
}
