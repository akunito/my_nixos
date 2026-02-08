//! Git operations for the dotfiles repository

use crate::error::AppError;
use crate::infra::GitStatus;
use std::process::Command;

/// Get current git status
pub fn get_status(dotfiles_path: &str) -> Result<GitStatus, AppError> {
    // Get current branch
    let branch_output = Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to get branch: {}", e)))?;

    let branch = String::from_utf8_lossy(&branch_output.stdout)
        .trim()
        .to_string();

    // Get ahead/behind from remote
    let ab_output = Command::new("git")
        .args(["rev-list", "--left-right", "--count", "HEAD...@{u}"])
        .current_dir(dotfiles_path)
        .output();

    let (ahead, behind) = if let Ok(output) = ab_output {
        let s = String::from_utf8_lossy(&output.stdout);
        let parts: Vec<&str> = s.trim().split_whitespace().collect();
        if parts.len() == 2 {
            (
                parts[0].parse().unwrap_or(0),
                parts[1].parse().unwrap_or(0),
            )
        } else {
            (0, 0)
        }
    } else {
        (0, 0)
    };

    // Get modified files
    let modified_output = Command::new("git")
        .args(["diff", "--name-only"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to get modified files: {}", e)))?;

    let modified_files: Vec<String> = String::from_utf8_lossy(&modified_output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|s| s.to_string())
        .collect();

    // Get untracked files
    let untracked_output = Command::new("git")
        .args(["ls-files", "--others", "--exclude-standard"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to get untracked files: {}", e)))?;

    let untracked_files: Vec<String> = String::from_utf8_lossy(&untracked_output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|s| s.to_string())
        .collect();

    // Get staged files
    let staged_output = Command::new("git")
        .args(["diff", "--cached", "--name-only"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to get staged files: {}", e)))?;

    let staged_files: Vec<String> = String::from_utf8_lossy(&staged_output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|s| s.to_string())
        .collect();

    Ok(GitStatus {
        branch,
        ahead,
        behind,
        modified_files,
        untracked_files,
        staged_files,
    })
}

/// Get diff for pending changes
pub fn get_diff(dotfiles_path: &str) -> Result<String, AppError> {
    let output = Command::new("git")
        .args(["diff", "--stat"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to get diff: {}", e)))?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Stage files for commit
#[allow(dead_code)]
pub fn stage_files(dotfiles_path: &str, files: &[String]) -> Result<(), AppError> {
    let mut args = vec!["add", "--"];
    let file_refs: Vec<&str> = files.iter().map(|s| s.as_str()).collect();
    args.extend(file_refs);

    let output = Command::new("git")
        .args(&args)
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to stage files: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to stage files: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

/// Create a commit
#[allow(dead_code)]
pub fn commit(dotfiles_path: &str, message: &str) -> Result<(), AppError> {
    let full_message = format!(
        "{}\n\nCo-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>",
        message
    );

    let output = Command::new("git")
        .args(["commit", "-m", &full_message])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to commit: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to commit: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    tracing::info!("Created commit: {}", message);
    Ok(())
}

/// Push to remote
#[allow(dead_code)]
pub fn push(dotfiles_path: &str) -> Result<(), AppError> {
    let output = Command::new("git")
        .args(["push"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to push: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to push: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    tracing::info!("Pushed to remote");
    Ok(())
}

/// Create a new branch and switch to it
#[allow(dead_code)]
pub fn create_branch(dotfiles_path: &str, branch_name: &str) -> Result<(), AppError> {
    let output = Command::new("git")
        .args(["checkout", "-b", branch_name])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to create branch: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to create branch: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    tracing::info!("Created and switched to branch: {}", branch_name);
    Ok(())
}

/// Auto-commit to a feature branch
#[allow(dead_code)]
pub fn auto_commit_to_branch(
    dotfiles_path: &str,
    files: &[String],
    message: &str,
) -> Result<String, AppError> {
    // Create timestamped branch name
    let branch_name = format!("auto/{}", chrono::Utc::now().format("%Y%m%d-%H%M%S"));

    // Create new branch
    create_branch(dotfiles_path, &branch_name)?;

    // Stage files
    stage_files(dotfiles_path, files)?;

    // Commit
    commit(dotfiles_path, message)?;

    // Push with upstream
    let output = Command::new("git")
        .args(["push", "-u", "origin", &branch_name])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to push: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to push: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    tracing::info!("Auto-committed to branch: {}", branch_name);
    Ok(branch_name)
}

/// Pull latest changes
#[allow(dead_code)]
pub fn pull(dotfiles_path: &str) -> Result<(), AppError> {
    let output = Command::new("git")
        .args(["pull"])
        .current_dir(dotfiles_path)
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to pull: {}", e)))?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to pull: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}
