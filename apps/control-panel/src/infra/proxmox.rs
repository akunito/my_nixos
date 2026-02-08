//! Proxmox VE integration via SSH

use crate::error::AppError;
use crate::ssh::{CommandOutput, SshPool};

/// Container status from Proxmox
#[derive(Debug, Clone)]
pub struct ContainerInfo {
    pub ctid: u32,
    pub name: String,
    pub status: String,
    pub cpu: f64,
    pub memory_used: u64,
    pub memory_total: u64,
}

/// Start a container on Proxmox
pub async fn start_container(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    ctid: u32,
) -> Result<(), AppError> {
    let command = format!("pct start {}", ctid);
    execute_proxmox_command(ssh_pool, proxmox_host, &command).await?;
    tracing::info!("Started container {} on Proxmox", ctid);
    Ok(())
}

/// Stop a container on Proxmox
pub async fn stop_container(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    ctid: u32,
) -> Result<(), AppError> {
    let command = format!("pct stop {}", ctid);
    execute_proxmox_command(ssh_pool, proxmox_host, &command).await?;
    tracing::info!("Stopped container {} on Proxmox", ctid);
    Ok(())
}

/// Restart a container on Proxmox
pub async fn restart_container(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    ctid: u32,
) -> Result<(), AppError> {
    let command = format!("pct restart {}", ctid);
    execute_proxmox_command(ssh_pool, proxmox_host, &command).await?;
    tracing::info!("Restarted container {} on Proxmox", ctid);
    Ok(())
}

/// Get container status from Proxmox
pub async fn get_container_status(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    ctid: u32,
) -> Result<String, AppError> {
    let command = format!("pct status {}", ctid);
    let output = execute_proxmox_command(ssh_pool, proxmox_host, &command).await?;

    // Parse "status: running" or "status: stopped"
    let status = output
        .stdout
        .lines()
        .find(|l| l.starts_with("status:"))
        .map(|l| l.trim_start_matches("status:").trim().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    Ok(status)
}

/// List all containers on Proxmox
pub async fn list_containers(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
) -> Result<Vec<ContainerInfo>, AppError> {
    let command = "pct list";
    let output = execute_proxmox_command(ssh_pool, proxmox_host, command).await?;

    let containers = output
        .stdout
        .lines()
        .skip(1) // Skip header
        .filter(|l| !l.trim().is_empty())
        .filter_map(|line| parse_pct_list_line(line))
        .collect();

    Ok(containers)
}

/// Parse a line from `pct list` output
/// Format: VMID Status Lock Name
fn parse_pct_list_line(line: &str) -> Option<ContainerInfo> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 4 {
        return None;
    }

    let ctid = parts[0].parse().ok()?;
    let status = parts[1].to_string();
    let name = parts[3].to_string();

    Some(ContainerInfo {
        ctid,
        name,
        status,
        cpu: 0.0,
        memory_used: 0,
        memory_total: 0,
    })
}

/// Execute a command on Proxmox host
async fn execute_proxmox_command(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    command: &str,
) -> Result<CommandOutput, AppError> {
    // For Proxmox, we need to add the node to the pool dynamically
    // This is a workaround since Proxmox isn't in docker_nodes
    ssh_pool.execute(proxmox_host, command).await
}

/// Check if a container is running
pub async fn is_container_running(
    ssh_pool: &mut SshPool,
    proxmox_host: &str,
    ctid: u32,
) -> Result<bool, AppError> {
    let status = get_container_status(ssh_pool, proxmox_host, ctid).await?;
    Ok(status == "running")
}
