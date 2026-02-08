//! SSH connection pool and command execution
//!
//! Supports two authentication methods:
//! 1. Direct key file (unencrypted)
//! 2. SSH agent (for encrypted keys)

use anyhow::Result;
use russh::keys::agent::client::AgentClient;
use russh::keys::decode_secret_key;
use russh::{client, ChannelMsg};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::net::UnixStream;
use tokio::sync::Mutex;

use crate::config::{Config, DockerNode};
use crate::error::AppError;

/// Authentication method for SSH connections
#[derive(Clone)]
enum AuthMethod {
    /// Direct private key
    Key(Arc<ssh_key::PrivateKey>),
    /// Use SSH agent
    Agent,
}

/// SSH connection pool for managing connections to multiple nodes
pub struct SshPool {
    config: Config,
    key_path: PathBuf,
    auth_method: Option<AuthMethod>,
    connections: HashMap<String, Arc<Mutex<Option<SshConnection>>>>,
}

/// A single SSH connection to a node
struct SshConnection {
    session: client::Handle<SshClient>,
}

/// SSH client handler
struct SshClient;

#[async_trait::async_trait]
impl client::Handler for SshClient {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &russh_keys::PublicKey,
    ) -> Result<bool, Self::Error> {
        // Accept all server keys (in production, you'd want to verify)
        Ok(true)
    }
}

impl SshPool {
    /// Create a new SSH connection pool
    ///
    /// Tries to load the key file directly first. If that fails (e.g., key is encrypted),
    /// checks if SSH agent is available and uses that instead.
    pub fn new(config: &Config) -> Result<Self> {
        let key_path = PathBuf::from(&config.ssh.private_key_path);

        // Try to load the key directly first
        let auth_method = match Self::try_load_key(&key_path) {
            Ok(key) => {
                tracing::info!("SSH key loaded successfully from file");
                Some(AuthMethod::Key(Arc::new(key)))
            }
            Err(e) => {
                tracing::warn!("Failed to load SSH key from file: {}", e);

                // Check if SSH agent is available
                if std::env::var("SSH_AUTH_SOCK").is_ok() {
                    tracing::info!("SSH agent detected, will use agent authentication");
                    Some(AuthMethod::Agent)
                } else {
                    tracing::warn!(
                        "No SSH agent available. SSH operations will fail until key is available."
                    );
                    None
                }
            }
        };

        let mut connections = HashMap::new();
        for node in &config.docker_nodes {
            connections.insert(node.name.clone(), Arc::new(Mutex::new(None)));
        }

        Ok(Self {
            config: config.clone(),
            key_path,
            auth_method,
            connections,
        })
    }

    /// Try to load the SSH key from file
    fn try_load_key(key_path: &PathBuf) -> Result<ssh_key::PrivateKey, String> {
        let key_content = std::fs::read_to_string(key_path)
            .map_err(|e| format!("Failed to read key file: {}", e))?;

        decode_secret_key(&key_content, None)
            .map_err(|e| format!("Failed to decode key: {}", e))
    }

    /// Get the authentication method, trying to initialize if not already set
    fn get_auth_method(&mut self) -> Result<AuthMethod, AppError> {
        if let Some(ref method) = self.auth_method {
            return Ok(method.clone());
        }

        // Try to load the key again
        if let Ok(key) = Self::try_load_key(&self.key_path) {
            let method = AuthMethod::Key(Arc::new(key));
            self.auth_method = Some(method.clone());
            return Ok(method);
        }

        // Check for SSH agent
        if std::env::var("SSH_AUTH_SOCK").is_ok() {
            let method = AuthMethod::Agent;
            self.auth_method = Some(method.clone());
            return Ok(method);
        }

        Err(AppError::SshConnection(
            "No SSH authentication available. Either provide an unencrypted key or run with SSH agent (ssh-agent with key added via ssh-add).".to_string()
        ))
    }

    /// Connect to SSH agent
    async fn connect_agent() -> Result<AgentClient<UnixStream>, AppError> {
        let socket_path = std::env::var("SSH_AUTH_SOCK").map_err(|_| {
            AppError::SshConnection("SSH_AUTH_SOCK not set".to_string())
        })?;

        let stream = UnixStream::connect(&socket_path).await.map_err(|e| {
            AppError::SshConnection(format!("Failed to connect to SSH agent: {}", e))
        })?;

        Ok(AgentClient::connect(stream))
    }

    /// Execute a command on a node (by docker node name)
    pub async fn execute(&mut self, node_name: &str, command: &str) -> Result<CommandOutput, AppError> {
        let node = self
            .config
            .get_docker_node(node_name)
            .ok_or_else(|| AppError::NodeNotFound(node_name.to_string()))?
            .clone();

        let user = self.config.get_ssh_user(&node).to_string();

        // Get or create connection
        let conn = self.get_or_create_connection(&node, &user).await?;

        // Execute command
        Self::run_command(&conn, command).await
    }

    /// Execute a command on a profile (looks up IP from profile or docker node)
    pub async fn execute_on_profile(&mut self, profile_name: &str, command: &str) -> Result<CommandOutput, AppError> {
        // First try as a docker node
        if let Some(node) = self.config.get_docker_node(profile_name) {
            let node = node.clone();
            let user = self.config.get_ssh_user(&node).to_string();
            let conn = self.get_or_create_connection(&node, &user).await?;
            return Self::run_command(&conn, command).await;
        }

        // Otherwise get the profile's IP and create a temporary connection
        let host = self.config.get_profile_host(profile_name)
            .ok_or_else(|| AppError::NodeNotFound(format!("Profile {} not found or has no IP", profile_name)))?;

        let user = self.config.ssh.default_user.clone();

        // Create a temporary DockerNode for this connection
        let temp_node = crate::config::DockerNode {
            name: profile_name.to_string(),
            host,
            ctid: 0,
            user: Some(user.clone()),
        };

        // For profiles not in docker_nodes, we create a one-off connection
        let connection = self.connect(&temp_node, &user).await?;
        let conn_mutex = Arc::new(Mutex::new(Some(connection)));
        Self::run_command(&conn_mutex, command).await
    }

    /// Execute a command on Proxmox host
    pub async fn execute_on_proxmox(&mut self, command: &str) -> Result<CommandOutput, AppError> {
        let host = self.config.proxmox.host.clone();
        let user = self.config.proxmox.user.clone();

        // Create a temporary node for Proxmox
        let temp_node = crate::config::DockerNode {
            name: "proxmox".to_string(),
            host,
            ctid: 0,
            user: Some(user.clone()),
        };

        let connection = self.connect(&temp_node, &user).await?;
        let conn_mutex = Arc::new(Mutex::new(Some(connection)));
        Self::run_command(&conn_mutex, command).await
    }

    /// Get an existing connection or create a new one
    async fn get_or_create_connection(
        &mut self,
        node: &DockerNode,
        user: &str,
    ) -> Result<Arc<Mutex<Option<SshConnection>>>, AppError> {
        let conn_mutex = self
            .connections
            .get(&node.name)
            .ok_or_else(|| AppError::NodeNotFound(node.name.clone()))?
            .clone();

        {
            let mut guard = conn_mutex.lock().await;
            if guard.is_none() {
                // Create new connection
                let connection = self.connect(node, user).await?;
                *guard = Some(connection);
            }
        }

        Ok(conn_mutex)
    }

    /// Create a new SSH connection
    async fn connect(&mut self, node: &DockerNode, user: &str) -> Result<SshConnection, AppError> {
        let auth_method = self.get_auth_method()?;

        let config = client::Config::default();
        let config = Arc::new(config);

        let addr = format!("{}:22", node.host);
        tracing::info!("Connecting to {} as {}", addr, user);

        let mut session = client::connect(config, &addr, SshClient)
            .await
            .map_err(|e| AppError::SshConnection(format!("Failed to connect to {}: {}", node.host, e)))?;

        // Authenticate based on method
        let auth_result = match auth_method {
            AuthMethod::Key(key) => {
                tracing::debug!("Authenticating with key file");
                session
                    .authenticate_publickey(user, Arc::new((*key).clone()))
                    .await
                    .map_err(|e| AppError::SshConnection(format!("Key authentication failed: {}", e)))?
            }
            AuthMethod::Agent => {
                tracing::debug!("Authenticating with SSH agent");
                let mut agent = Self::connect_agent().await?;

                // Get identities from agent
                let identities = agent.request_identities().await.map_err(|e| {
                    AppError::SshConnection(format!("Failed to get identities from agent: {}", e))
                })?;

                if identities.is_empty() {
                    return Err(AppError::SshConnection(
                        "No keys available in SSH agent. Run: ssh-add".to_string(),
                    ));
                }

                // Try each key from the agent
                let mut authenticated = false;
                for identity in identities {
                    match session
                        .authenticate_publickey_with(user, identity.clone(), &mut agent)
                        .await
                    {
                        Ok(true) => {
                            authenticated = true;
                            break;
                        }
                        Ok(false) => continue,
                        Err(e) => {
                            tracing::debug!("Agent key failed: {}", e);
                            continue;
                        }
                    }
                }
                authenticated
            }
        };

        if !auth_result {
            return Err(AppError::SshConnection("Authentication rejected".to_string()));
        }

        tracing::info!("Connected to {}", node.name);

        Ok(SshConnection { session })
    }

    /// Run a command on an established connection
    async fn run_command(
        conn: &Arc<Mutex<Option<SshConnection>>>,
        command: &str,
    ) -> Result<CommandOutput, AppError> {
        let guard = conn.lock().await;
        let connection = guard
            .as_ref()
            .ok_or_else(|| AppError::SshConnection("No connection available".to_string()))?;

        let mut channel = connection
            .session
            .channel_open_session()
            .await
            .map_err(|e| AppError::SshCommand(format!("Failed to open channel: {}", e)))?;

        channel
            .exec(true, command)
            .await
            .map_err(|e| AppError::SshCommand(format!("Failed to execute command: {}", e)))?;

        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let mut exit_code = None;

        loop {
            match channel.wait().await {
                Some(ChannelMsg::Data { data }) => {
                    stdout.extend_from_slice(&data);
                }
                Some(ChannelMsg::ExtendedData { data, ext }) => {
                    if ext == 1 {
                        // stderr
                        stderr.extend_from_slice(&data);
                    }
                }
                Some(ChannelMsg::ExitStatus { exit_status }) => {
                    exit_code = Some(exit_status);
                }
                Some(ChannelMsg::Eof) | None => break,
                _ => {}
            }
        }

        Ok(CommandOutput {
            stdout: String::from_utf8_lossy(&stdout).to_string(),
            stderr: String::from_utf8_lossy(&stderr).to_string(),
            exit_code: exit_code.unwrap_or(0),
        })
    }

    /// Close connection to a specific node (useful for reconnecting)
    #[allow(dead_code)]
    pub async fn close_connection(&mut self, node_name: &str) {
        if let Some(conn) = self.connections.get(node_name) {
            let mut guard = conn.lock().await;
            *guard = None;
        }
    }
}

/// Output from an SSH command
#[derive(Debug, Clone)]
pub struct CommandOutput {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: u32,
}

impl CommandOutput {
    /// Check if the command succeeded (exit code 0)
    pub fn success(&self) -> bool {
        self.exit_code == 0
    }

    /// Get combined output (stdout + stderr)
    pub fn combined(&self) -> String {
        if self.stderr.is_empty() {
            self.stdout.clone()
        } else if self.stdout.is_empty() {
            self.stderr.clone()
        } else {
            format!("{}\n{}", self.stdout, self.stderr)
        }
    }
}
