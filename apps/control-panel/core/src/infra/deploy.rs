//! NixOS deployment management

use crate::error::AppError;
use crate::ssh::SshPool;
use chrono::Utc;
use serde::{Deserialize, Serialize};

/// Deployment status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeploymentStatus {
    pub profile: String,
    pub status: DeployState,
    pub message: String,
    pub started_at: Option<chrono::DateTime<chrono::Utc>>,
    pub finished_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum DeployState {
    Pending,
    DryRun,
    Building,
    Switching,
    Success,
    Failed,
}

impl DeployState {
    pub fn is_success(&self) -> bool {
        matches!(self, DeployState::Success)
    }

    pub fn is_failed(&self) -> bool {
        matches!(self, DeployState::Failed)
    }
}

/// Perform a dry-run build for validation
pub async fn dry_run(
    ssh_pool: &mut SshPool,
    _node_name: &str,
    profile: &str,
    dotfiles_path: &str,
) -> Result<DeploymentStatus, AppError> {
    let started_at = Utc::now();

    // Build command for dry-run
    let command = format!(
        "cd {} && nix build .#nixosConfigurations.{}.config.system.build.toplevel --dry-run 2>&1",
        dotfiles_path, profile
    );

    let output = ssh_pool.execute_on_profile(profile, &command).await?;

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
    _node_name: &str,
    profile: &str,
    dotfiles_path: &str,
) -> Result<DeploymentStatus, AppError> {
    let started_at = Utc::now();
    let profile_name = profile.to_string();

    // Step 1: Pull latest changes
    tracing::info!("Pulling latest changes on {}", profile);
    let pull_cmd = format!("cd {} && git pull", dotfiles_path);
    let pull_output = ssh_pool.execute_on_profile(profile, &pull_cmd).await?;

    if !pull_output.success() {
        return Ok(DeploymentStatus {
            profile: profile_name,
            status: DeployState::Failed,
            message: format!("Git pull failed: {}", pull_output.combined()),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        });
    }

    // Step 2: Build and switch
    tracing::info!("Building and switching on {}", profile);
    let switch_cmd = format!(
        "cd {} && sudo nixos-rebuild switch --flake .#system 2>&1",
        dotfiles_path
    );

    let switch_output = ssh_pool.execute_on_profile(profile, &switch_cmd).await?;

    let status = if switch_output.success() {
        DeploymentStatus {
            profile: profile_name,
            status: DeployState::Success,
            message: "Deployment successful".to_string(),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    } else {
        DeploymentStatus {
            profile: profile_name,
            status: DeployState::Failed,
            message: format!("Deployment failed: {}", switch_output.combined()),
            started_at: Some(started_at),
            finished_at: Some(Utc::now()),
        }
    };

    Ok(status)
}

/// Get deployment log (last N lines of journal)
#[allow(dead_code)]
pub async fn get_deployment_log(
    ssh_pool: &mut SshPool,
    profile: &str,
    lines: u32,
) -> Result<String, AppError> {
    let command = format!(
        "journalctl -u nixos-rebuild --no-pager -n {} 2>/dev/null || echo 'No rebuild logs available'",
        lines
    );

    let output = ssh_pool.execute_on_profile(profile, &command).await?;
    Ok(output.combined())
}

/// Check if a profile is reachable and NixOS
#[allow(dead_code)]
pub async fn check_node_health(
    ssh_pool: &mut SshPool,
    profile: &str,
) -> Result<bool, AppError> {
    let command = "nixos-version 2>/dev/null || echo 'not-nixos'";
    let output = ssh_pool.execute_on_profile(profile, command).await?;

    Ok(output.success() && !output.stdout.contains("not-nixos"))
}

// ============================================================================
// deploy-lxc.sh Workflow
// ============================================================================

/// Result of a single deploy step
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeployStepResult {
    pub step: String,
    pub success: bool,
    pub output: String,
}

/// Deploy an LXC node using the deploy-lxc.sh workflow:
/// 1. SSH connectivity check
/// 2. git fetch origin
/// 3. git reset --hard origin/main
/// 4. ./install.sh {dotfiles_path} {profile} -s -u -q
pub async fn deploy_lxc_node(
    ssh_pool: &mut SshPool,
    profile: &str,
    dotfiles_path: &str,
) -> Result<Vec<DeployStepResult>, AppError> {
    let mut results = Vec::new();

    // Step 1: SSH connectivity check (implicit via first command)
    let check_cmd = "echo ok";
    let check_output = ssh_pool.execute_on_profile(profile, check_cmd).await;
    match check_output {
        Ok(out) if out.success() => {
            results.push(DeployStepResult {
                step: "ssh_check".to_string(),
                success: true,
                output: "SSH connection OK".to_string(),
            });
        }
        Ok(out) => {
            results.push(DeployStepResult {
                step: "ssh_check".to_string(),
                success: false,
                output: format!("SSH check failed: {}", out.combined()),
            });
            return Ok(results);
        }
        Err(e) => {
            results.push(DeployStepResult {
                step: "ssh_check".to_string(),
                success: false,
                output: format!("SSH connection failed: {}", e),
            });
            return Ok(results);
        }
    }

    // Step 2: git fetch origin
    tracing::info!("deploy-lxc: git fetch on {}", profile);
    let fetch_cmd = format!("cd {} && git fetch origin 2>&1", dotfiles_path);
    let fetch_output = ssh_pool.execute_on_profile(profile, &fetch_cmd).await;
    match fetch_output {
        Ok(out) if out.success() || out.exit_code == 0 => {
            results.push(DeployStepResult {
                step: "git_fetch".to_string(),
                success: true,
                output: out.combined(),
            });
        }
        Ok(out) => {
            results.push(DeployStepResult {
                step: "git_fetch".to_string(),
                success: false,
                output: format!("Git fetch failed: {}", out.combined()),
            });
            return Ok(results);
        }
        Err(e) => {
            results.push(DeployStepResult {
                step: "git_fetch".to_string(),
                success: false,
                output: format!("Git fetch error: {}", e),
            });
            return Ok(results);
        }
    }

    // Step 3: git reset --hard origin/main
    tracing::info!("deploy-lxc: git reset on {}", profile);
    let reset_cmd = format!("cd {} && git reset --hard origin/main 2>&1", dotfiles_path);
    let reset_output = ssh_pool.execute_on_profile(profile, &reset_cmd).await;
    match reset_output {
        Ok(out) if out.success() => {
            results.push(DeployStepResult {
                step: "git_reset".to_string(),
                success: true,
                output: out.combined(),
            });
        }
        Ok(out) => {
            results.push(DeployStepResult {
                step: "git_reset".to_string(),
                success: false,
                output: format!("Git reset failed: {}", out.combined()),
            });
            return Ok(results);
        }
        Err(e) => {
            results.push(DeployStepResult {
                step: "git_reset".to_string(),
                success: false,
                output: format!("Git reset error: {}", e),
            });
            return Ok(results);
        }
    }

    // Step 4: ./install.sh
    tracing::info!("deploy-lxc: install.sh on {}", profile);
    let install_cmd = format!(
        "cd {} && ./install.sh {} {} -s -u -q 2>&1",
        dotfiles_path, dotfiles_path, profile
    );
    let install_output = ssh_pool.execute_on_profile(profile, &install_cmd).await;
    match install_output {
        Ok(out) if out.success() => {
            results.push(DeployStepResult {
                step: "install".to_string(),
                success: true,
                output: out.combined(),
            });
        }
        Ok(out) => {
            results.push(DeployStepResult {
                step: "install".to_string(),
                success: false,
                output: format!("install.sh failed: {}", out.combined()),
            });
        }
        Err(e) => {
            results.push(DeployStepResult {
                step: "install".to_string(),
                success: false,
                output: format!("install.sh error: {}", e),
            });
        }
    }

    Ok(results)
}
