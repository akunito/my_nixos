//! Nix profile writing operations
//!
//! Provides safe editing of Nix configuration files using string manipulation.
//! For complex edits, we use pattern matching to preserve formatting.

use crate::error::AppError;
use std::path::Path;

/// Set a string value in a profile
pub fn set_string_value(
    profile_name: &str,
    dotfiles_path: &str,
    key: &str,
    value: &str,
) -> Result<(), AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Find patterns like: key = "old_value";
    let pattern = format!(r#"{} = ""#, key);

    if let Some(start) = content.find(&pattern) {
        let value_start = start + pattern.len();
        if let Some(end_quote) = content[value_start..].find('"') {
            let before = &content[..value_start];
            let after = &content[value_start + end_quote..];
            let new_content = format!("{}{}{}", before, value, after);

            std::fs::write(&profile_path, new_content)
                .map_err(|e| AppError::Internal(format!("Failed to write profile: {}", e)))?;

            tracing::info!("Set {} = \"{}\" in {}", key, value, profile_name);
            return Ok(());
        }
    }

    Err(AppError::NotImplemented(format!(
        "String value not found: {}",
        key
    )))
}

/// Set a numeric value in a profile
pub fn set_number_value(
    profile_name: &str,
    dotfiles_path: &str,
    key: &str,
    value: i64,
) -> Result<(), AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Find pattern: key = old_number;
    // Match key followed by = and a number
    let pattern = format!("{} = ", key);

    if let Some(start) = content.find(&pattern) {
        let value_start = start + pattern.len();
        // Find the semicolon that ends this value
        if let Some(end) = content[value_start..].find(';') {
            let old_value = content[value_start..value_start + end].trim();
            // Verify it's a number
            if old_value.parse::<i64>().is_ok() {
                let before = &content[..value_start];
                let after = &content[value_start + end..];
                let new_content = format!("{}{}{}", before, value, after);

                std::fs::write(&profile_path, new_content)
                    .map_err(|e| AppError::Internal(format!("Failed to write profile: {}", e)))?;

                tracing::info!("Set {} = {} in {}", key, value, profile_name);
                return Ok(());
            }
        }
    }

    Err(AppError::NotImplemented(format!(
        "Number value not found: {}",
        key
    )))
}

/// Add a package to a list in the profile
pub fn add_package(
    profile_name: &str,
    dotfiles_path: &str,
    section: &str,
    package: &str,
) -> Result<(), AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Find the package list section
    let patterns = [
        format!("{} = pkgs: pkgs-unstable: [", section),
        format!("{} = [", section),
    ];

    for pattern in &patterns {
        if let Some(start) = content.find(pattern) {
            let bracket_pos = start + pattern.len();
            // Insert the package after the opening bracket
            let before = &content[..bracket_pos];
            let after = &content[bracket_pos..];

            // Check if the list is empty or has content
            let trimmed_after = after.trim_start();
            let indent = if trimmed_after.starts_with(']') {
                // Empty list, add with newline
                format!("\n      {}\n    ", package)
            } else {
                // Has content, add at the beginning
                format!("\n      {}", package)
            };

            let new_content = format!("{}{}{}", before, indent, after);

            std::fs::write(&profile_path, new_content)
                .map_err(|e| AppError::Internal(format!("Failed to write profile: {}", e)))?;

            tracing::info!("Added package {} to {} in {}", package, section, profile_name);
            return Ok(());
        }
    }

    Err(AppError::NotImplemented(format!(
        "Package list not found: {}",
        section
    )))
}

/// Remove a package from a list in the profile
pub fn remove_package(
    profile_name: &str,
    dotfiles_path: &str,
    section: &str,
    package: &str,
) -> Result<(), AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Find and remove the package line
    // Handle various formats: "pkgs.name", "pkgs-unstable.name", "name"
    let patterns = [
        format!("\n      {}\n", package),
        format!("\n      {},\n", package),
        format!("\n      {}", package),
    ];

    for pattern in &patterns {
        if content.contains(pattern) {
            let new_content = content.replacen(pattern, "\n", 1);

            std::fs::write(&profile_path, new_content)
                .map_err(|e| AppError::Internal(format!("Failed to write profile: {}", e)))?;

            tracing::info!("Removed package {} from {} in {}", package, section, profile_name);
            return Ok(());
        }
    }

    Err(AppError::NotImplemented(format!(
        "Package not found: {}",
        package
    )))
}

/// Validate that a Nix file is syntactically correct
#[allow(dead_code)]
pub fn validate_nix_syntax(file_path: &str) -> Result<bool, AppError> {
    use std::process::Command;

    let output = Command::new("nix-instantiate")
        .args(["--parse", file_path])
        .output()
        .map_err(|e| AppError::Internal(format!("Failed to run nix-instantiate: {}", e)))?;

    Ok(output.status.success())
}

/// Create a backup of a profile before editing
#[allow(dead_code)]
pub fn backup_profile(profile_name: &str, dotfiles_path: &str) -> Result<String, AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let backup_path = format!("{}.backup", profile_path);

    std::fs::copy(&profile_path, &backup_path)
        .map_err(|e| AppError::Internal(format!("Failed to create backup: {}", e)))?;

    Ok(backup_path)
}

/// Restore a profile from backup
#[allow(dead_code)]
pub fn restore_profile(profile_name: &str, dotfiles_path: &str) -> Result<(), AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);
    let backup_path = format!("{}.backup", profile_path);

    if !Path::new(&backup_path).exists() {
        return Err(AppError::NotImplemented("No backup found".to_string()));
    }

    std::fs::copy(&backup_path, &profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to restore backup: {}", e)))?;

    std::fs::remove_file(&backup_path)
        .map_err(|e| AppError::Internal(format!("Failed to remove backup: {}", e)))?;

    Ok(())
}
