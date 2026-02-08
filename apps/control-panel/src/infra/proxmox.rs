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

// ============================================================================
// Backup Functions
// ============================================================================

/// Backup job information
#[derive(Debug, Clone, Serialize)]
pub struct BackupJob {
    pub id: String,
    pub schedule: String,
    pub storage: String,
    pub vmids: String,
    pub enabled: bool,
    pub mode: String,
    pub comment: Option<String>,
}

/// List all backup jobs
pub async fn list_backup_jobs(ssh_pool: &mut SshPool) -> Result<Vec<BackupJob>, AppError> {
    // Read vzdump.cron and /etc/pve/jobs.cfg for scheduled backups
    let command = "cat /etc/pve/jobs.cfg 2>/dev/null || echo ''";
    let output = ssh_pool.execute_on_proxmox(command).await?;

    let mut jobs = Vec::new();
    let mut current_job: Option<BackupJob> = None;

    for line in output.stdout.lines() {
        let line = line.trim();

        if line.starts_with("vzdump:") {
            // Save previous job if exists
            if let Some(job) = current_job.take() {
                jobs.push(job);
            }
            // Start new job
            let id = line.trim_start_matches("vzdump:").trim().to_string();
            current_job = Some(BackupJob {
                id,
                schedule: String::new(),
                storage: String::new(),
                vmids: String::new(),
                enabled: true,
                mode: "snapshot".to_string(),
                comment: None,
            });
        } else if let Some(ref mut job) = current_job {
            if let Some((key, value)) = line.split_once(' ') {
                match key {
                    "schedule" => job.schedule = value.to_string(),
                    "storage" => job.storage = value.to_string(),
                    "vmid" | "pool" | "all" => job.vmids = if key == "all" { "all".to_string() } else { value.to_string() },
                    "enabled" => job.enabled = value != "0",
                    "mode" => job.mode = value.to_string(),
                    "comment" => job.comment = Some(value.to_string()),
                    _ => {}
                }
            }
        }
    }

    // Don't forget the last job
    if let Some(job) = current_job {
        jobs.push(job);
    }

    Ok(jobs)
}

/// Run a backup job manually
pub async fn run_backup_job(ssh_pool: &mut SshPool, job_id: &str) -> Result<String, AppError> {
    // Trigger the vzdump job
    let command = format!("pvesh create /cluster/backup/{}/run", job_id);
    let output = ssh_pool.execute_on_proxmox(&command).await?;

    if !output.success() {
        return Err(AppError::SshCommand(format!(
            "Failed to run backup job {}: {}",
            job_id,
            output.combined()
        )));
    }

    tracing::info!("Started backup job {} on Proxmox", job_id);
    Ok(output.combined())
}

/// Backup a specific container/VM immediately
#[allow(dead_code)]
pub async fn backup_container(
    ssh_pool: &mut SshPool,
    ctid: u32,
    storage: &str,
    mode: &str,
) -> Result<String, AppError> {
    let command = format!("vzdump {} --storage {} --mode {} --compress zstd", ctid, storage, mode);
    let output = ssh_pool.execute_on_proxmox(&command).await?;

    if !output.success() {
        return Err(AppError::SshCommand(format!(
            "Failed to backup container {}: {}",
            ctid,
            output.combined()
        )));
    }

    tracing::info!("Started backup for container {} on Proxmox", ctid);
    Ok(output.combined())
}

/// List recent backups for a container/VM
#[allow(dead_code)]
pub async fn list_backups(ssh_pool: &mut SshPool, storage: &str) -> Result<Vec<String>, AppError> {
    let command = format!("pvesm list {} --content backup 2>/dev/null | tail -20", storage);
    let output = ssh_pool.execute_on_proxmox(&command).await?;

    let backups: Vec<String> = output
        .stdout
        .lines()
        .skip(1) // Skip header
        .filter(|l| !l.trim().is_empty())
        .map(|l| l.to_string())
        .collect();

    Ok(backups)
}
