//! SSH connection pool and command execution

use anyhow::Result;
use russh::keys::decode_secret_key;
use russh::{client, ChannelMsg};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::config::{Config, DockerNode};
use crate::error::AppError;

/// SSH connection pool for managing connections to multiple nodes
pub struct SshPool {
    config: Config,
    private_key: Arc<ssh_key::PrivateKey>,
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
    pub fn new(config: &Config) -> Result<Self> {
        let key_path = Path::new(&config.ssh.private_key_path);
        let key_content = std::fs::read_to_string(key_path)?;
        let private_key = decode_secret_key(&key_content, None)?;

        let mut connections = HashMap::new();
        for node in &config.docker_nodes {
            connections.insert(node.name.clone(), Arc::new(Mutex::new(None)));
        }

        Ok(Self {
            config: config.clone(),
            private_key: Arc::new(private_key),
            connections,
        })
    }

    /// Execute a command on a node
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
    async fn connect(&self, node: &DockerNode, user: &str) -> Result<SshConnection, AppError> {
        let config = client::Config::default();
        let config = Arc::new(config);

        let addr = format!("{}:22", node.host);
        tracing::info!("Connecting to {} as {}", addr, user);

        let mut session = client::connect(config, &addr, SshClient)
            .await
            .map_err(|e| AppError::SshConnection(format!("Failed to connect to {}: {}", node.host, e)))?;

        // Authenticate with key
        let auth_result = session
            .authenticate_publickey(user, Arc::new((*self.private_key).clone()))
            .await
            .map_err(|e| AppError::SshConnection(format!("Authentication failed: {}", e)))?;

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
