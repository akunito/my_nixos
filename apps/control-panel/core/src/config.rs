//! Configuration management for the control panel

use serde::{Deserialize, Serialize};
use std::path::Path;

/// Main configuration structure
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Config {
    pub server: ServerConfig,
    pub auth: AuthConfig,
    pub ssh: SshConfig,
    pub proxmox: ProxmoxConfig,
    pub dotfiles: DotfilesConfig,
    #[serde(default)]
    pub docker_nodes: Vec<DockerNode>,
    #[serde(default)]
    pub profiles: Vec<ProfileConfig>,
    #[serde(default)]
    pub grafana: Option<GrafanaConfig>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AuthConfig {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SshConfig {
    pub private_key_path: String,
    pub default_user: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProxmoxConfig {
    pub host: String,
    pub user: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DotfilesConfig {
    pub path: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DockerNode {
    pub name: String,
    pub host: String,
    pub ctid: u32,
    #[serde(default)]
    pub user: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProfileConfig {
    pub name: String,
    #[serde(rename = "type")]
    pub profile_type: String,
    pub hostname: String,
    #[serde(default)]
    pub ip: Option<String>,
    #[serde(default)]
    pub ctid: Option<u32>,
    #[serde(default)]
    pub base_profile: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GrafanaConfig {
    pub base_url: String,
    #[serde(default)]
    pub dashboards: Vec<GrafanaDashboard>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GrafanaDashboard {
    pub name: String,
    pub uid: String,
    pub slug: String,
}

impl Config {
    /// Load configuration from a TOML file
    pub fn load<P: AsRef<Path>>(path: P) -> anyhow::Result<Self> {
        let content = std::fs::read_to_string(path.as_ref())?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    /// Get a docker node by name
    pub fn get_docker_node(&self, name: &str) -> Option<&DockerNode> {
        self.docker_nodes.iter().find(|n| n.name == name)
    }

    /// Get a profile by name
    pub fn get_profile(&self, name: &str) -> Option<&ProfileConfig> {
        self.profiles.iter().find(|p| p.name == name)
    }

    /// Get the SSH user for a docker node
    pub fn get_ssh_user<'a>(&'a self, node: &'a DockerNode) -> &'a str {
        node.user.as_deref().unwrap_or(&self.ssh.default_user)
    }

    /// Get the host IP for a profile (for SSH connections)
    pub fn get_profile_host(&self, profile_name: &str) -> Option<String> {
        // First check if there's a docker node with the same name
        if let Some(node) = self.get_docker_node(profile_name) {
            return Some(node.host.clone());
        }

        // Otherwise look up the profile's IP
        if let Some(profile) = self.get_profile(profile_name) {
            return profile.ip.clone();
        }

        None
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 3100,
        }
    }
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            username: "admin".to_string(),
            password: "admin".to_string(),
        }
    }
}

impl Default for SshConfig {
    fn default() -> Self {
        Self {
            private_key_path: String::new(),
            default_user: "akunito".to_string(),
        }
    }
}

impl Default for ProxmoxConfig {
    fn default() -> Self {
        Self {
            host: "192.168.8.82".to_string(),
            user: "root".to_string(),
        }
    }
}

impl Default for DotfilesConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        Self {
            path: format!("{}/.dotfiles", home),
        }
    }
}

impl Default for GrafanaConfig {
    fn default() -> Self {
        Self {
            base_url: "https://grafana.local.akunito.com".to_string(),
            dashboards: Vec::new(),
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig::default(),
            auth: AuthConfig::default(),
            ssh: SshConfig::default(),
            proxmox: ProxmoxConfig::default(),
            dotfiles: DotfilesConfig::default(),
            docker_nodes: Vec::new(),
            profiles: Vec::new(),
            grafana: Some(GrafanaConfig::default()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_config() {
        let config_str = r#"
[server]
host = "0.0.0.0"
port = 3100

[auth]
username = "admin"
password = "test"

[ssh]
private_key_path = "/home/user/.ssh/id_ed25519"
default_user = "akunito"

[proxmox]
host = "192.168.8.82"
user = "root"

[dotfiles]
path = "/home/akunito/.dotfiles"

[[docker_nodes]]
name = "LXC_HOME"
host = "192.168.8.80"
ctid = 100

[[profiles]]
name = "DESK"
type = "desktop"
hostname = "nixosaku"
ip = "192.168.8.96"
"#;

        let config: Config = toml::from_str(config_str).unwrap();
        assert_eq!(config.server.port, 3100);
        assert_eq!(config.docker_nodes.len(), 1);
        assert_eq!(config.docker_nodes[0].name, "LXC_HOME");
    }
}
