//! Main application state and logic

use control_panel_core::{Config, SshPool};
use egui::{Context, Ui};
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;
use tokio::sync::RwLock;

// =============================================================================
// Async Command System
// =============================================================================

/// Commands that can be sent to the background async handler
#[derive(Debug, Clone)]
pub enum AsyncCommand {
    // Docker commands
    RefreshDocker,
    RefreshDockerNode { node: String },
    StopContainer { node: String, container: String },
    StartContainer { node: String, container: String },
    RestartContainer { node: String, container: String },
    FetchLogs { node: String, container: String },

    // Proxmox commands
    RefreshProxmox,
    ProxmoxStart { ctid: u32 },
    ProxmoxStop { ctid: u32 },
    ProxmoxRestart { ctid: u32 },
    RefreshBackupJobs,
    RunBackupJob { job_id: String },

    // Infrastructure commands
    GitPull,
    GitPush,
    GitCommit { message: String, files: Vec<String> },
    DeployDryRun { profile: String },
    Deploy { profile: String },
}

/// Results from async operations
#[derive(Debug)]
pub enum AsyncResult {
    // Docker results
    DockerContainers {
        node: String,
        containers: Vec<control_panel_core::Container>,
    },
    DockerNodeSummaries(Vec<control_panel_core::NodeSummary>),
    ContainerLogs {
        node: String,
        container: String,
        logs: String,
    },
    DockerOperationSuccess {
        node: String,
        container: String,
        operation: String,
    },
    DockerOperationError {
        node: String,
        container: String,
        operation: String,
        error: String,
    },

    // Proxmox results
    ProxmoxContainers(Vec<control_panel_core::ProxmoxContainer>),
    BackupJobs(Vec<control_panel_core::BackupJob>),
    ProxmoxOperationSuccess { ctid: u32, operation: String },
    ProxmoxOperationError { ctid: u32, operation: String, error: String },
    BackupJobStarted { job_id: String },
    BackupJobError { job_id: String, error: String },

    // Infrastructure results
    GitPullSuccess,
    GitPushSuccess,
    GitCommitSuccess { branch: String },
    GitOperationError { operation: String, error: String },
    DeploymentStatus(control_panel_core::DeploymentStatus),
}

/// Channel sender for async commands - can be cloned for each panel
pub type CommandSender = mpsc::UnboundedSender<AsyncCommand>;

/// Channel receiver for async results
pub type ResultReceiver = mpsc::UnboundedReceiver<AsyncResult>;

// =============================================================================
// Application State
// =============================================================================

/// Active panel in the UI
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Panel {
    Sway,
    Docker,
    Proxmox,
    Monitoring,
    Editor,
    Infrastructure,
}

impl Panel {
    pub fn label(&self) -> &'static str {
        match self {
            Panel::Sway => "Sway",
            Panel::Docker => "Docker",
            Panel::Proxmox => "Proxmox",
            Panel::Monitoring => "Monitoring",
            Panel::Editor => "Editor",
            Panel::Infrastructure => "Infrastructure",
        }
    }

    pub fn all() -> &'static [Panel] {
        &[
            Panel::Sway,
            Panel::Docker,
            Panel::Proxmox,
            Panel::Monitoring,
            Panel::Editor,
            Panel::Infrastructure,
        ]
    }
}

/// Main application state
pub struct ControlPanelApp {
    /// Application configuration
    config: Arc<Config>,

    /// Active panel
    active_panel: Panel,

    /// Async runtime for SSH operations (kept alive for background tasks)
    #[allow(dead_code)]
    runtime: Runtime,

    /// Sway IPC availability
    sway_available: bool,

    /// Command sender for async operations
    command_tx: CommandSender,

    /// Result receiver for async operations
    result_rx: ResultReceiver,

    /// UI state for each panel
    sway_state: crate::ui::sway::SwayPanelState,
    docker_state: crate::ui::docker::DockerPanelState,
    proxmox_state: crate::ui::proxmox::ProxmoxPanelState,
    monitoring_state: crate::ui::monitoring::MonitoringPanelState,
    editor_state: crate::ui::editor::EditorPanelState,
    infra_state: crate::ui::infra::InfraPanelState,
}

impl ControlPanelApp {
    pub fn new(config: Config) -> Self {
        let runtime = Runtime::new().expect("Failed to create tokio runtime");

        // Check if Sway is available
        let sway_available = check_sway_available();
        if sway_available {
            tracing::info!("Sway IPC available - enabling Sway panel");
        } else {
            tracing::info!("Sway IPC not available - Sway panel will be disabled");
        }

        // Determine initial panel based on Sway availability
        let initial_panel = if sway_available {
            Panel::Sway
        } else {
            Panel::Docker
        };

        // Create channels for async communication
        let (command_tx, command_rx) = mpsc::unbounded_channel::<AsyncCommand>();
        let (result_tx, result_rx) = mpsc::unbounded_channel::<AsyncResult>();

        let config = Arc::new(config);

        // Spawn the background async handler
        spawn_async_handler(&runtime, config.clone(), command_rx, result_tx);

        Self {
            config,
            active_panel: initial_panel,
            runtime,
            sway_available,
            command_tx,
            result_rx,
            sway_state: Default::default(),
            docker_state: Default::default(),
            proxmox_state: Default::default(),
            monitoring_state: Default::default(),
            editor_state: Default::default(),
            infra_state: Default::default(),
        }
    }

    /// Process any pending async results
    fn process_results(&mut self) {
        // Process all available results without blocking
        while let Ok(result) = self.result_rx.try_recv() {
            match result {
                // Docker results
                AsyncResult::DockerContainers { node, containers } => {
                    self.docker_state.containers.insert(node, containers);
                    self.docker_state.loading = false;
                }
                AsyncResult::DockerNodeSummaries(summaries) => {
                    self.docker_state.node_summaries = summaries;
                    self.docker_state.loading = false;
                }
                AsyncResult::ContainerLogs { node, container, logs } => {
                    if self.docker_state.selected_container
                        == Some((node.clone(), container.clone()))
                    {
                        self.docker_state.logs = logs;
                    }
                }
                AsyncResult::DockerOperationSuccess {
                    node,
                    container,
                    operation,
                } => {
                    tracing::info!("{} {} on {} succeeded", operation, container, node);
                    self.docker_state.error = None;
                    // Trigger a refresh for that node
                    let _ = self
                        .command_tx
                        .send(AsyncCommand::RefreshDockerNode { node });
                }
                AsyncResult::DockerOperationError {
                    node,
                    container,
                    operation,
                    error,
                } => {
                    tracing::error!("{} {} on {} failed: {}", operation, container, node, error);
                    self.docker_state.error = Some(format!("{} failed: {}", operation, error));
                }

                // Proxmox results
                AsyncResult::ProxmoxContainers(containers) => {
                    self.proxmox_state.containers = containers;
                    self.proxmox_state.loading = false;
                }
                AsyncResult::BackupJobs(jobs) => {
                    self.proxmox_state.backup_jobs = jobs;
                }
                AsyncResult::ProxmoxOperationSuccess { ctid, operation } => {
                    tracing::info!("{} CTID {} succeeded", operation, ctid);
                    self.proxmox_state.error = None;
                    // Trigger a refresh
                    let _ = self.command_tx.send(AsyncCommand::RefreshProxmox);
                }
                AsyncResult::ProxmoxOperationError {
                    ctid,
                    operation,
                    error,
                } => {
                    tracing::error!("{} CTID {} failed: {}", operation, ctid, error);
                    self.proxmox_state.error = Some(format!("{} failed: {}", operation, error));
                    self.proxmox_state.loading = false;
                }
                AsyncResult::BackupJobStarted { job_id } => {
                    tracing::info!("Backup job {} started", job_id);
                }
                AsyncResult::BackupJobError { job_id, error } => {
                    tracing::error!("Backup job {} failed: {}", job_id, error);
                    self.proxmox_state.error = Some(format!("Backup {} failed: {}", job_id, error));
                }

                // Infrastructure results
                AsyncResult::GitPullSuccess => {
                    tracing::info!("Git pull succeeded");
                    self.infra_state.loading = false;
                    // Refresh git status
                    if let Ok(status) =
                        control_panel_core::infra::git::get_status(&self.config.dotfiles.path)
                    {
                        self.infra_state.git_status = Some(status);
                    }
                }
                AsyncResult::GitPushSuccess => {
                    tracing::info!("Git push succeeded");
                    self.infra_state.loading = false;
                    // Refresh git status
                    if let Ok(status) =
                        control_panel_core::infra::git::get_status(&self.config.dotfiles.path)
                    {
                        self.infra_state.git_status = Some(status);
                    }
                }
                AsyncResult::GitCommitSuccess { branch } => {
                    tracing::info!("Git commit to {} succeeded", branch);
                    self.infra_state.loading = false;
                    self.infra_state.commit_message.clear();
                    // Refresh git status
                    if let Ok(status) =
                        control_panel_core::infra::git::get_status(&self.config.dotfiles.path)
                    {
                        self.infra_state.git_status = Some(status);
                    }
                }
                AsyncResult::GitOperationError { operation, error } => {
                    tracing::error!("Git {} failed: {}", operation, error);
                    self.infra_state.error = Some(format!("Git {} failed: {}", operation, error));
                    self.infra_state.loading = false;
                }
                AsyncResult::DeploymentStatus(status) => {
                    self.infra_state
                        .deployment_status
                        .insert(status.profile.clone(), status);
                    self.infra_state.loading = false;
                }
            }
        }
    }

    /// Render the top navigation bar
    fn render_nav_bar(&mut self, ui: &mut Ui) {
        ui.horizontal(|ui| {
            ui.heading("NixOS Control Panel");
            ui.separator();

            for panel in Panel::all() {
                // Skip Sway panel if not available
                if *panel == Panel::Sway && !self.sway_available {
                    continue;
                }

                let is_selected = self.active_panel == *panel;
                if ui
                    .selectable_label(is_selected, panel.label())
                    .clicked()
                {
                    self.active_panel = *panel;
                }
            }

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                // Status indicator
                let status_text = if self.sway_available {
                    "🟢 Local"
                } else {
                    "🔵 Remote"
                };
                ui.label(status_text);
            });
        });
    }

    /// Render the active panel content
    fn render_panel(&mut self, ctx: &Context, ui: &mut Ui) {
        match self.active_panel {
            Panel::Sway => {
                crate::ui::sway::render(ctx, ui, &mut self.sway_state);
            }
            Panel::Docker => {
                crate::ui::docker::render(
                    ctx,
                    ui,
                    &mut self.docker_state,
                    &self.config,
                    &self.command_tx,
                );
            }
            Panel::Proxmox => {
                crate::ui::proxmox::render(
                    ctx,
                    ui,
                    &mut self.proxmox_state,
                    &self.config,
                    &self.command_tx,
                );
            }
            Panel::Monitoring => {
                crate::ui::monitoring::render(
                    ctx,
                    ui,
                    &mut self.monitoring_state,
                    &self.config,
                );
            }
            Panel::Editor => {
                crate::ui::editor::render(
                    ctx,
                    ui,
                    &mut self.editor_state,
                    &self.config,
                );
            }
            Panel::Infrastructure => {
                crate::ui::infra::render(
                    ctx,
                    ui,
                    &mut self.infra_state,
                    &self.config,
                    &self.command_tx,
                );
            }
        }
    }
}

impl eframe::App for ControlPanelApp {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        // Process any pending async results
        self.process_results();

        // Top panel for navigation
        egui::TopBottomPanel::top("nav_bar").show(ctx, |ui| {
            self.render_nav_bar(ui);
        });

        // Central panel for content
        egui::CentralPanel::default().show(ctx, |ui| {
            self.render_panel(ctx, ui);
        });

        // Request repaint for live updates
        ctx.request_repaint_after(std::time::Duration::from_millis(100));
    }
}

/// Check if Sway IPC is available
fn check_sway_available() -> bool {
    match swayipc::Connection::new() {
        Ok(_) => true,
        Err(e) => {
            tracing::debug!("Sway IPC not available: {}", e);
            false
        }
    }
}

// =============================================================================
// Background Async Handler
// =============================================================================

/// Spawn the background task handler for async operations
fn spawn_async_handler(
    runtime: &Runtime,
    config: Arc<Config>,
    mut command_rx: mpsc::UnboundedReceiver<AsyncCommand>,
    result_tx: mpsc::UnboundedSender<AsyncResult>,
) {
    let config = config.clone();

    runtime.spawn(async move {
        // Create SSH pool for remote operations
        let ssh_pool = match SshPool::new(&config) {
            Ok(pool) => Arc::new(RwLock::new(pool)),
            Err(e) => {
                tracing::error!("Failed to create SSH pool: {}. SSH operations will fail.", e);
                // Create a dummy pool that will fail on first use
                match SshPool::new(&config) {
                    Ok(pool) => Arc::new(RwLock::new(pool)),
                    Err(_) => return, // Give up if we can't create a pool at all
                }
            }
        };

        tracing::info!("Async handler started, waiting for commands...");

        while let Some(command) = command_rx.recv().await {
            let config = config.clone();
            let ssh_pool = ssh_pool.clone();
            let result_tx = result_tx.clone();

            // Spawn a task for each command to allow concurrent operations
            tokio::spawn(async move {
                match command {
                    // Docker commands
                    AsyncCommand::RefreshDocker => {
                        handle_refresh_docker(&config, &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::RefreshDockerNode { node } => {
                        handle_refresh_docker_node(&node, &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::StopContainer { node, container } => {
                        handle_docker_operation(
                            &node,
                            &container,
                            "Stop",
                            &ssh_pool,
                            &result_tx,
                        )
                        .await;
                    }
                    AsyncCommand::StartContainer { node, container } => {
                        handle_docker_operation(
                            &node,
                            &container,
                            "Start",
                            &ssh_pool,
                            &result_tx,
                        )
                        .await;
                    }
                    AsyncCommand::RestartContainer { node, container } => {
                        handle_docker_operation(
                            &node,
                            &container,
                            "Restart",
                            &ssh_pool,
                            &result_tx,
                        )
                        .await;
                    }
                    AsyncCommand::FetchLogs { node, container } => {
                        handle_fetch_logs(&node, &container, &ssh_pool, &result_tx).await;
                    }

                    // Proxmox commands
                    AsyncCommand::RefreshProxmox => {
                        handle_refresh_proxmox(&ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::ProxmoxStart { ctid } => {
                        handle_proxmox_operation(ctid, "Start", &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::ProxmoxStop { ctid } => {
                        handle_proxmox_operation(ctid, "Stop", &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::ProxmoxRestart { ctid } => {
                        handle_proxmox_operation(ctid, "Restart", &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::RefreshBackupJobs => {
                        handle_refresh_backup_jobs(&ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::RunBackupJob { job_id } => {
                        handle_run_backup_job(&job_id, &ssh_pool, &result_tx).await;
                    }

                    // Infrastructure commands
                    AsyncCommand::GitPull => {
                        handle_git_pull(&config, &result_tx).await;
                    }
                    AsyncCommand::GitPush => {
                        handle_git_push(&config, &result_tx).await;
                    }
                    AsyncCommand::GitCommit { message, files } => {
                        handle_git_commit(&config, &message, &files, &result_tx).await;
                    }
                    AsyncCommand::DeployDryRun { profile } => {
                        handle_deploy_dry_run(&config, &profile, &ssh_pool, &result_tx).await;
                    }
                    AsyncCommand::Deploy { profile } => {
                        handle_deploy(&config, &profile, &ssh_pool, &result_tx).await;
                    }
                }
            });
        }
    });
}

// =============================================================================
// Docker Handlers
// =============================================================================

async fn handle_refresh_docker(
    config: &Config,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut summaries = Vec::new();

    for node in &config.docker_nodes {
        let mut pool = ssh_pool.write().await;
        let summary =
            control_panel_core::docker::commands::get_node_summary(&mut pool, &node.name, &node.host)
                .await;
        summaries.push(summary);
    }

    let _ = result_tx.send(AsyncResult::DockerNodeSummaries(summaries));

    // Also fetch containers for each online node
    for node in &config.docker_nodes {
        let mut pool = ssh_pool.write().await;
        match control_panel_core::docker::commands::list_containers(&mut pool, &node.name).await {
            Ok(containers) => {
                let _ = result_tx.send(AsyncResult::DockerContainers {
                    node: node.name.clone(),
                    containers,
                });
            }
            Err(e) => {
                tracing::warn!("Failed to list containers on {}: {}", node.name, e);
            }
        }
    }
}

async fn handle_refresh_docker_node(
    node: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::docker::commands::list_containers(&mut pool, node).await {
        Ok(containers) => {
            let _ = result_tx.send(AsyncResult::DockerContainers {
                node: node.to_string(),
                containers,
            });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::DockerOperationError {
                node: node.to_string(),
                container: "".to_string(),
                operation: "Refresh".to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_docker_operation(
    node: &str,
    container: &str,
    operation: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;

    let result = match operation {
        "Stop" => control_panel_core::docker::commands::stop_container(&mut pool, node, container)
            .await,
        "Start" => {
            control_panel_core::docker::commands::start_container(&mut pool, node, container).await
        }
        "Restart" => {
            control_panel_core::docker::commands::restart_container(&mut pool, node, container)
                .await
        }
        _ => return,
    };

    match result {
        Ok(()) => {
            let _ = result_tx.send(AsyncResult::DockerOperationSuccess {
                node: node.to_string(),
                container: container.to_string(),
                operation: operation.to_string(),
            });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::DockerOperationError {
                node: node.to_string(),
                container: container.to_string(),
                operation: operation.to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_fetch_logs(
    node: &str,
    container: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::docker::commands::get_container_logs(&mut pool, node, container, 100)
        .await
    {
        Ok(logs) => {
            let _ = result_tx.send(AsyncResult::ContainerLogs {
                node: node.to_string(),
                container: container.to_string(),
                logs,
            });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::ContainerLogs {
                node: node.to_string(),
                container: container.to_string(),
                logs: format!("Error fetching logs: {}", e),
            });
        }
    }
}

// =============================================================================
// Proxmox Handlers
// =============================================================================

async fn handle_refresh_proxmox(
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;

    match control_panel_core::infra::proxmox::list_containers(&mut pool).await {
        Ok(containers) => {
            let _ = result_tx.send(AsyncResult::ProxmoxContainers(containers));
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::ProxmoxOperationError {
                ctid: 0,
                operation: "Refresh".to_string(),
                error: e.to_string(),
            });
        }
    }

    // Also fetch backup jobs
    match control_panel_core::infra::proxmox::list_backup_jobs(&mut pool).await {
        Ok(jobs) => {
            let _ = result_tx.send(AsyncResult::BackupJobs(jobs));
        }
        Err(e) => {
            tracing::warn!("Failed to list backup jobs: {}", e);
        }
    }
}

async fn handle_proxmox_operation(
    ctid: u32,
    operation: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;

    let result = match operation {
        "Start" => control_panel_core::infra::proxmox::start_container(&mut pool, ctid).await,
        "Stop" => control_panel_core::infra::proxmox::stop_container(&mut pool, ctid).await,
        "Restart" => control_panel_core::infra::proxmox::restart_container(&mut pool, ctid).await,
        _ => return,
    };

    match result {
        Ok(()) => {
            let _ = result_tx.send(AsyncResult::ProxmoxOperationSuccess {
                ctid,
                operation: operation.to_string(),
            });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::ProxmoxOperationError {
                ctid,
                operation: operation.to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_refresh_backup_jobs(
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::infra::proxmox::list_backup_jobs(&mut pool).await {
        Ok(jobs) => {
            let _ = result_tx.send(AsyncResult::BackupJobs(jobs));
        }
        Err(e) => {
            tracing::warn!("Failed to list backup jobs: {}", e);
        }
    }
}

async fn handle_run_backup_job(
    job_id: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::infra::proxmox::run_backup_job(&mut pool, job_id).await {
        Ok(_) => {
            let _ = result_tx.send(AsyncResult::BackupJobStarted {
                job_id: job_id.to_string(),
            });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::BackupJobError {
                job_id: job_id.to_string(),
                error: e.to_string(),
            });
        }
    }
}

// =============================================================================
// Infrastructure Handlers
// =============================================================================

async fn handle_git_pull(config: &Config, result_tx: &mpsc::UnboundedSender<AsyncResult>) {
    match control_panel_core::infra::git::pull(&config.dotfiles.path) {
        Ok(()) => {
            let _ = result_tx.send(AsyncResult::GitPullSuccess);
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::GitOperationError {
                operation: "pull".to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_git_push(config: &Config, result_tx: &mpsc::UnboundedSender<AsyncResult>) {
    match control_panel_core::infra::git::push(&config.dotfiles.path) {
        Ok(()) => {
            let _ = result_tx.send(AsyncResult::GitPushSuccess);
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::GitOperationError {
                operation: "push".to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_git_commit(
    config: &Config,
    message: &str,
    files: &[String],
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    // If files empty, stage all modified files
    let files_to_stage = if files.is_empty() {
        match control_panel_core::infra::git::get_status(&config.dotfiles.path) {
            Ok(status) => {
                let mut all_files = status.modified_files;
                all_files.extend(status.untracked_files);
                all_files
            }
            Err(e) => {
                let _ = result_tx.send(AsyncResult::GitOperationError {
                    operation: "commit".to_string(),
                    error: format!("Failed to get status: {}", e),
                });
                return;
            }
        }
    } else {
        files.to_vec()
    };

    match control_panel_core::infra::git::auto_commit_to_branch(
        &config.dotfiles.path,
        &files_to_stage,
        message,
    ) {
        Ok(branch) => {
            let _ = result_tx.send(AsyncResult::GitCommitSuccess { branch });
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::GitOperationError {
                operation: "commit".to_string(),
                error: e.to_string(),
            });
        }
    }
}

async fn handle_deploy_dry_run(
    config: &Config,
    profile: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::infra::deploy::dry_run(
        &mut pool,
        profile,
        profile,
        &config.dotfiles.path,
    )
    .await
    {
        Ok(status) => {
            let _ = result_tx.send(AsyncResult::DeploymentStatus(status));
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::DeploymentStatus(
                control_panel_core::DeploymentStatus {
                    profile: profile.to_string(),
                    status: control_panel_core::DeployState::Failed,
                    message: format!("Dry run failed: {}", e),
                    started_at: None,
                    finished_at: None,
                },
            ));
        }
    }
}

async fn handle_deploy(
    config: &Config,
    profile: &str,
    ssh_pool: &Arc<RwLock<SshPool>>,
    result_tx: &mpsc::UnboundedSender<AsyncResult>,
) {
    let mut pool = ssh_pool.write().await;
    match control_panel_core::infra::deploy::deploy(
        &mut pool,
        profile,
        profile,
        &config.dotfiles.path,
    )
    .await
    {
        Ok(status) => {
            let _ = result_tx.send(AsyncResult::DeploymentStatus(status));
        }
        Err(e) => {
            let _ = result_tx.send(AsyncResult::DeploymentStatus(
                control_panel_core::DeploymentStatus {
                    profile: profile.to_string(),
                    status: control_panel_core::DeployState::Failed,
                    message: format!("Deploy failed: {}", e),
                    started_at: None,
                    finished_at: None,
                },
            ));
        }
    }
}
