//! Control Panel Core Library
//!
//! Shared functionality for the NixOS Infrastructure Control Panel.
//! Used by both the native egui application and web server.
//!
//! # Modules
//!
//! - `config` - Configuration management and parsing
//! - `ssh` - SSH connection pool for remote command execution
//! - `error` - Error types for the application
//! - `docker` - Docker container management
//! - `infra` - Infrastructure control (Proxmox, deploy, git, graph)
//! - `editor` - Profile configuration editing

pub mod config;
pub mod docker;
pub mod editor;
pub mod error;
pub mod infra;
pub mod ssh;

// Re-export commonly used types
pub use config::{Config, DockerNode, GrafanaDashboard, GrafanaConfig, ProfileConfig as ProfileEntry};
pub use docker::{ComposeStack, Container, ContainerStatus, NodeSummary};
pub use editor::{ConfigEntry, ConfigValue, EntryType, ProfileConfig};
pub use error::AppError;
pub use infra::{
    BackupJob, ContainerInfo as ProxmoxContainer, DeployState, DeployStepResult, DeploymentStatus,
    GitStatus, GraphData, GraphLink, GraphNode, NodeStatus, ProfileNode, ProfileType,
};
pub use ssh::{CommandOutput, SshPool};
