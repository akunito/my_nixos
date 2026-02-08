//! NixOS deployment management

use crate::error::AppError;
use crate::infra::{DeployState, DeploymentStatus};
use crate::ssh::SshPool;
use chrono::Utc;

/// Perform a dry-run build for validation
pub async fn dry_run(
    ssh_pool: &mut SshPool,
    node_name: &str,
    profile: &str,
    dotfiles_path: &str,
) -> Result<DeploymentStatus, AppError> {
    let started_at = Utc::now();

    // Build command for dry-run
    let command = format!(
        "cd {} && nix build .#nixosConfigurations.{}.config.system.build.toplevel --dry-run 2>&1",
        dotfiles_path, profile
    );

    let output = ssh_pool.execute(node_name, &command).await?;

    let status = if output.success() {
        DeploymentStatus {
            profile: profile.to_string(),
            status: DeployState::Success,
            message: "Dry-run successful. Build is valid.".to_string(),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    } else {
        DeploymentStatus {
            profile: profile.to_string(),
            status: DeployState::Failed,
            message: format!("Dry-run failed: {}", output.combined()),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    };

    Ok(status)
}

/// Deploy changes to a node
pub async fn deploy(
    ssh_pool: &mut SshPool,
    node_name: &str,
    _profile: &str,
    dotfiles_path: &str,
) -> Result<DeploymentStatus, AppError> {
    let started_at = Utc::now();
    let profile = _profile.to_string();

    // Step 1: Pull latest changes
    tracing::info!("Pulling latest changes on {}", node_name);
    let pull_cmd = format!("cd {} && git pull", dotfiles_path);
    let pull_output = ssh_pool.execute(node_name, &pull_cmd).await?;

    if !pull_output.success() {
        return Ok(DeploymentStatus {
            profile,
            status: DeployState::Failed,
            message: format!("Git pull failed: {}", pull_output.combined()),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        });
    }

    // Step 2: Build and switch
    tracing::info!("Building and switching on {}", node_name);
    let switch_cmd = format!(
        "cd {} && sudo nixos-rebuild switch --flake .#system 2>&1",
        dotfiles_path
    );

    let switch_output = ssh_pool.execute(node_name, &switch_cmd).await?;

    let status = if switch_output.success() {
        DeploymentStatus {
            profile,
            status: DeployState::Success,
            message: "Deployment successful".to_string(),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    } else {
        DeploymentStatus {
            profile,
            status: DeployState::Failed,
            message: format!("Deployment failed: {}", switch_output.combined()),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    };

    Ok(status)
}

/// Get deployment log (last N lines of journal)
pub async fn get_deployment_log(
    ssh_pool: &mut SshPool,
    node_name: &str,
    lines: u32,
) -> Result<String, AppError> {
    let command = format!(
        "journalctl -u nixos-rebuild --no-pager -n {} 2>/dev/null || echo 'No rebuild logs available'",
        lines
    );

    let output = ssh_pool.execute(node_name, &command).await?;
    Ok(output.combined())
}

/// Check if a node is reachable and NixOS
pub async fn check_node_health(
    ssh_pool: &mut SshPool,
    node_name: &str,
) -> Result<bool, AppError> {
    let command = "nixos-version 2>/dev/null || echo 'not-nixos'";
    let output = ssh_pool.execute(node_name, command).await?;

    Ok(output.success() && !output.stdout.contains("not-nixos"))
}
