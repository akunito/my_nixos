//! Profile duplication functionality
//!
//! Allows creating new profiles by copying and modifying existing ones.

use crate::error::AppError;
use std::path::Path;

/// Duplicate a profile with new name and hostname
pub fn duplicate_profile(
    source_profile: &str,
    new_name: &str,
    new_hostname: &str,
    dotfiles_path: &str,
) -> Result<DuplicationResult, AppError> {
    // Validate inputs
    if new_name.is_empty() || new_hostname.is_empty() {
        return Err(AppError::Validation(
            "Profile name and hostname are required".to_string(),
        ));
    }

    // Check source exists
    let source_path = format!("{}/profiles/{}-config.nix", dotfiles_path, source_profile);
    if !Path::new(&source_path).exists() {
        return Err(AppError::NotImplemented(format!(
            "Source profile not found: {}",
            source_profile
        )));
    }

    // Check target doesn't exist
    let target_path = format!("{}/profiles/{}-config.nix", dotfiles_path, new_name);
    if Path::new(&target_path).exists() {
        return Err(AppError::Validation(format!(
            "Profile already exists: {}",
            new_name
        )));
    }

    // Read source content
    let content = std::fs::read_to_string(&source_path)
        .map_err(|e| AppError::Internal(format!("Failed to read source profile: {}", e)))?;

    // Get source hostname and envProfile for replacement
    let source_hostname = extract_value(&content, "hostname")
        .unwrap_or_else(|| source_profile.to_lowercase());
    let source_env_profile = extract_value(&content, "envProfile")
        .unwrap_or_else(|| source_profile.to_string());

    // Replace values
    let new_content = content
        .replace(
            &format!("hostname = \"{}\";", source_hostname),
            &format!("hostname = \"{}\";", new_hostname),
        )
        .replace(
            &format!("envProfile = \"{}\";", source_env_profile),
            &format!("envProfile = \"{}\";", new_name),
        );

    // Write new profile
    std::fs::write(&target_path, &new_content)
        .map_err(|e| AppError::Internal(format!("Failed to write new profile: {}", e)))?;

    // Try to create flake file if source has one
    let flake_result = duplicate_flake(source_profile, new_name, dotfiles_path);

    tracing::info!(
        "Duplicated profile {} -> {} (hostname: {})",
        source_profile,
        new_name,
        new_hostname
    );

    Ok(DuplicationResult {
        profile_name: new_name.to_string(),
        profile_path: target_path,
        flake_created: flake_result.is_ok(),
        flake_path: flake_result.ok(),
    })
}

/// Duplicate the flake file for a profile
fn duplicate_flake(
    source_profile: &str,
    new_name: &str,
    dotfiles_path: &str,
) -> Result<String, AppError> {
    let source_flake = format!("{}/flake.{}.nix", dotfiles_path, source_profile);
    let target_flake = format!("{}/flake.{}.nix", dotfiles_path, new_name);

    if !Path::new(&source_flake).exists() {
        return Err(AppError::NotImplemented(
            "Source flake not found".to_string(),
        ));
    }

    if Path::new(&target_flake).exists() {
        return Err(AppError::Validation("Flake already exists".to_string()));
    }

    let content = std::fs::read_to_string(&source_flake)
        .map_err(|e| AppError::Internal(format!("Failed to read source flake: {}", e)))?;

    // Replace profile references
    let new_content = content
        .replace(
            &format!("{}-config.nix", source_profile),
            &format!("{}-config.nix", new_name),
        )
        .replace(
            &format!("\"{}\"", source_profile),
            &format!("\"{}\"", new_name),
        );

    std::fs::write(&target_flake, &new_content)
        .map_err(|e| AppError::Internal(format!("Failed to write new flake: {}", e)))?;

    Ok(target_flake)
}

/// Extract a string value from Nix content
fn extract_value(content: &str, key: &str) -> Option<String> {
    let pattern = format!("{} = \"", key);
    if let Some(start) = content.find(&pattern) {
        let value_start = start + pattern.len();
        if let Some(end) = content[value_start..].find('"') {
            return Some(content[value_start..value_start + end].to_string());
        }
    }
    None
}

/// Result of profile duplication
#[derive(Debug, Clone)]
pub struct DuplicationResult {
    pub profile_name: String,
    pub profile_path: String,
    pub flake_created: bool,
    pub flake_path: Option<String>,
}

/// List profiles that can be used as templates
#[allow(dead_code)]
pub fn list_template_profiles(dotfiles_path: &str) -> Result<Vec<TemplateProfile>, AppError> {
    let profiles_dir = format!("{}/profiles", dotfiles_path);

    let entries = std::fs::read_dir(&profiles_dir)
        .map_err(|e| AppError::Internal(format!("Failed to read profiles dir: {}", e)))?;

    let mut templates = Vec::new();

    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();

        if name_str.ends_with("-config.nix") && !name_str.contains("-base") {
            let profile_name = name_str
                .trim_end_matches("-config.nix")
                .to_string();

            let profile_path = entry.path();
            let content = std::fs::read_to_string(&profile_path).unwrap_or_default();

            let profile_type = extract_value(&content, "profile")
                .or_else(|| {
                    // Infer from name
                    if profile_name.starts_with("LXC") {
                        Some("lxc".to_string())
                    } else if profile_name.starts_with("LAPTOP") {
                        Some("laptop".to_string())
                    } else if profile_name.starts_with("MACBOOK") {
                        Some("darwin".to_string())
                    } else {
                        Some("desktop".to_string())
                    }
                })
                .unwrap_or_else(|| "unknown".to_string());

            templates.push(TemplateProfile {
                name: profile_name,
                profile_type,
                has_flake: Path::new(&format!(
                    "{}/flake.{}.nix",
                    dotfiles_path,
                    name_str.trim_end_matches("-config.nix")
                ))
                .exists(),
            });
        }
    }

    templates.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(templates)
}

/// Template profile info
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct TemplateProfile {
    pub name: String,
    pub profile_type: String,
    pub has_flake: bool,
}
