//! Docker command execution via SSH

use crate::docker::{Container, ContainerStatus, NodeSummary};
use crate::error::AppError;
use crate::ssh::SshPool;

/// List all containers on a node
pub async fn list_containers(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<Vec<Container>, AppError> {
    // Use docker ps with custom format for easier parsing
    let format = "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}";
    let command = format!("docker ps -a --format '{}'", format);

    let output = ssh_pool.execute(node_name, &command).await?;

    if !output.success() {
        return Err(AppError::Docker(format!(
            "Failed to list containers: {}",
            output.stderr
        )));
    }

    let containers = output
        .stdout
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| parse_container_line(line))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(containers)
}

/// Parse a single container line from docker ps output
fn parse_container_line(line: &str) -> Result<Container, AppError> {
    let parts: Vec<&str> = line.split('|').collect();

    if parts.len() < 6 {
        return Err(AppError::Docker(format!(
            "Invalid container line format: {}",
            line
        )));
    }

    Ok(Container {
        id: parts[0].to_string(),
        name: parts[1].to_string(),
        image: parts[2].to_string(),
        status: ContainerStatus::from_str(parts[3]),
        ports: parts[4].to_string(),
        created: parts[5].to_string(),
    })
}

/// Start a container
pub async fn start_container(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<(), AppError> {
    let command = format!("docker start {}", container);
    let output = ssh_pool.execute(node_name, &command).await?;

    if !output.success() {
        return Err(AppError::Docker(format!(
            "Failed to start container: {}",
            output.stderr
        )));
    }

    tracing::info!("Started container {} on {}", container, node_name);
    Ok(())
}

/// Stop a container
pub async fn stop_container(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<(), AppError> {
    let command = format!("docker stop {}", container);
    let output = ssh_pool.execute(node_name, &command).await?;

    if !output.success() {
        return Err(AppError::Docker(format!(
            "Failed to stop container: {}",
            output.stderr
        )));
    }

    tracing::info!("Stopped container {} on {}", container, node_name);
    Ok(())
}

/// Restart a container
pub async fn restart_container(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<(), AppError> {
    let command = format!("docker restart {}", container);
    let output = ssh_pool.execute(node_name, &command).await?;

    if !output.success() {
        return Err(AppError::Docker(format!(
            "Failed to restart container: {}",
            output.stderr
        )));
    }

    tracing::info!("Restarted container {} on {}", container, node_name);
    Ok(())
}

/// Get container logs (last N lines)
pub async fn get_container_logs(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
    tail: u32,
) -> Result<String, AppError> {
    let command = format!("docker logs --tail {} {}", tail, container);
    let output = ssh_pool.execute(node_name, &command).await?;

    // Docker logs output goes to stderr for log output
    Ok(output.combined())
}

/// Get node summary (container counts)
pub async fn get_node_summary(
    ssh_pool: &mut SshPool,
    node_name: &str,
    host: &str,
) -> NodeSummary {
    match list_containers(ssh_pool, node_name).await {
        Ok(containers) => {
            let running = containers
                .iter()
                .filter(|c| c.status == ContainerStatus::Running)
                .count();

            NodeSummary {
                name: node_name.to_string(),
                host: host.to_string(),
                total: containers.len(),
                running,
                stopped: containers.len() - running,
                online: true,
            }
        }
        Err(e) => {
            tracing::warn!("Failed to get node summary for {}: {}", node_name, e);
            NodeSummary {
                name: node_name.to_string(),
                host: host.to_string(),
                total: 0,
                running: 0,
                stopped: 0,
                online: false,
            }
        }
    }
}

/// Check if a container exists on a node
#[allow(dead_code)]
pub async fn container_exists(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<bool, AppError> {
    let containers = list_containers(ssh_pool, node_name).await?;
    Ok(containers.iter().any(|c| c.name == container || c.id == container))
}

/// Pull latest image for a container
pub async fn pull_container(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<String, AppError> {
    // First get the image name from the container
    let inspect_cmd = format!("docker inspect --format '{{{{.Config.Image}}}}' {}", container);
    let inspect_output = ssh_pool.execute(node_name, &inspect_cmd).await?;

    if !inspect_output.success() {
        return Err(AppError::Docker(format!(
            "Failed to get image for container: {}",
            inspect_output.stderr
        )));
    }

    let image = inspect_output.stdout.trim();
    let command = format!("docker pull {}", image);
    let output = ssh_pool.execute(node_name, &command).await?;

    if !output.success() {
        return Err(AppError::Docker(format!(
            "Failed to pull image: {}",
            output.stderr
        )));
    }

    tracing::info!("Pulled image {} for container {} on {}", image, container, node_name);
    Ok(output.combined())
}

/// Recreate a container (pull + stop + rm + up)
/// This assumes docker-compose is used
pub async fn recreate_container(
    ssh_pool: &mut SshPool,
    node_name: &str,
    container: &str,
) -> Result<String, AppError> {
    // Try docker-compose first, fall back to docker commands
    let command = format!(
        "docker-compose pull {} && docker-compose up -d --force-recreate {} 2>&1 || \
         (docker pull $(docker inspect --format '{{{{.Config.Image}}}}' {}) && \
          docker stop {} && docker rm {} && docker start {})",
        container, container, container, container, container, container
    );

    let output = ssh_pool.execute(node_name, &command).await?;

    tracing::info!("Recreated container {} on {}", container, node_name);
    Ok(output.combined())
}

// ============================================================================
// Cleanup Commands
// ============================================================================

/// Prune unused Docker resources
pub async fn system_prune(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<String, AppError> {
    let command = "docker system prune -f 2>&1";
    let output = ssh_pool.execute(node_name, command).await?;

    tracing::info!("System prune on {}", node_name);
    Ok(output.combined())
}

/// Remove unused volumes
pub async fn volume_prune(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<String, AppError> {
    let command = "docker volume prune -f 2>&1";
    let output = ssh_pool.execute(node_name, command).await?;

    tracing::info!("Volume prune on {}", node_name);
    Ok(output.combined())
}

/// Remove unused images
pub async fn image_prune(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<String, AppError> {
    let command = "docker image prune -af 2>&1";
    let output = ssh_pool.execute(node_name, command).await?;

    tracing::info!("Image prune on {}", node_name);
    Ok(output.combined())
}

/// Get disk usage stats
pub async fn disk_usage(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<String, AppError> {
    let command = "docker system df 2>&1";
    let output = ssh_pool.execute(node_name, command).await?;

    Ok(output.combined())
}
