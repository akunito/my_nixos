//! Proxmox VE integration via SSH

use crate::error::AppError;
use crate::ssh::SshPool;
use serde::Serialize;

/// Container status from Proxmox
#[derive(Debug, Clone, Serialize)]
pub struct ContainerInfo {
    pub ctid: u32,
    pub name: String,
    pub status: String,
}

/// Start a container on Proxmox
pub async fn start_container(ssh_pool: &mut SshPool, ctid: u32) -> Result<(), AppError> {
    let command = format!("pct start {}", ctid);
    let output = ssh_pool.execute_on_proxmox(&command).await?;
    if !output.success() {
        return Err(AppError::SshCommand(format!(
            "Failed to start container {}: {}",
            ctid,
            output.combined()
        )));
    }
    tracing::info!("Started container {} on Proxmox", ctid);
    Ok(())
}

/// Stop a container on Proxmox
pub async fn stop_container(ssh_pool: &mut SshPool, ctid: u32) -> Result<(), AppError> {
    let command = format!("pct stop {}", ctid);
    let output = ssh_pool.execute_on_proxmox(&command).await?;
    if !output.success() {
        return Err(AppError::SshCommand(format!(
            "Failed to stop container {}: {}",
            ctid,
            output.combined()
        )));
    }
    tracing::info!("Stopped container {} on Proxmox", ctid);
    Ok(())
}

/// Restart a container on Proxmox
pub async fn restart_container(ssh_pool: &mut SshPool, ctid: u32) -> Result<(), AppError> {
    let command = format!("pct restart {}", ctid);
    let output = ssh_pool.execute_on_proxmox(&command).await?;
    if !output.success() {
        return Err(AppError::SshCommand(format!(
            "Failed to restart container {}: {}",
            ctid,
            output.combined()
        )));
    }
    tracing::info!("Restarted container {} on Proxmox", ctid);
    Ok(())
}

/// Get container status from Proxmox
pub async fn get_container_status(ssh_pool: &mut SshPool, ctid: u32) -> Result<String, AppError> {
    let command = format!("pct status {}", ctid);
    let output = ssh_pool.execute_on_proxmox(&command).await?;

    // Parse "status: running" or "status: stopped"
    let status = output
        .stdout
        .lines()
        .find(|l| l.starts_with("status:"))
        .map(|l| l.trim_start_matches("status:").trim().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    Ok(status)
}

/// List all LXC containers on Proxmox
pub async fn list_containers(ssh_pool: &mut SshPool) -> Result<Vec<ContainerInfo>, AppError> {
    let command = "pct list";
    let output = ssh_pool.execute_on_proxmox(command).await?;

    let containers = output
        .stdout
        .lines()
        .skip(1) // Skip header
        .filter(|l| !l.trim().is_empty())
        .filter_map(parse_pct_list_line)
        .collect();

    Ok(containers)
}

/// List all VMs on Proxmox
#[allow(dead_code)]
pub async fn list_vms(ssh_pool: &mut SshPool) -> Result<Vec<ContainerInfo>, AppError> {
    let command = "qm list";
    let output = ssh_pool.execute_on_proxmox(command).await?;

    let vms = output
        .stdout
        .lines()
        .skip(1) // Skip header
        .filter(|l| !l.trim().is_empty())
        .filter_map(parse_qm_list_line)
        .collect();

    Ok(vms)
}

/// Parse a line from `pct list` output
/// Format: VMID Status Lock Name
fn parse_pct_list_line(line: &str) -> Option<ContainerInfo> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 3 {
        return None;
    }

    let ctid = parts[0].parse().ok()?;
    let status = parts[1].to_string();
    // Name might be at index 3 if there's a Lock column, otherwise at index 2
    let name = if parts.len() > 3 {
        parts[3].to_string()
    } else {
        parts[2].to_string()
    };

    Some(ContainerInfo { ctid, name, status })
}

/// Parse a line from `qm list` output
/// Format: VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID
fn parse_qm_list_line(line: &str) -> Option<ContainerInfo> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 3 {
        return None;
    }

    let ctid = parts[0].parse().ok()?;
    let name = parts[1].to_string();
    let status = parts[2].to_string();

    Some(ContainerInfo { ctid, name, status })
}

/// Check if a container is running
#[allow(dead_code)]
pub async fn is_container_running(ssh_pool: &mut SshPool, ctid: u32) -> Result<bool, AppError> {
    let status = get_container_status(ssh_pool, ctid).await?;
    Ok(status == "running")
}
