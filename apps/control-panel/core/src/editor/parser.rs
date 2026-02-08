//! Nix profile parsing
//!
//! Uses simple pattern matching for parsing Nix expressions and extracting configuration values.
//! For complex cases, falls back to JSON export via `nix eval`.

use crate::editor::{ConfigEntry, ConfigValue, EntryType, ProfileConfig};
use crate::error::AppError;
use std::path::Path;

/// Parse a profile configuration file
pub fn parse_profile(profile_name: &str, dotfiles_path: &str) -> Result<ProfileConfig, AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);

    if !Path::new(&profile_path).exists() {
        return Err(AppError::NotImplemented(format!(
            "Profile not found: {}",
            profile_name
        )));
    }

    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Simple regex-based parsing for common patterns
    // In a full implementation, we'd use rnix for proper AST parsing
    let system_settings = extract_settings(&content, "systemSettings");
    let user_settings = extract_settings(&content, "userSettings");
    let system_packages = extract_packages(&content, "systemPackages");
    let home_packages = extract_packages(&content, "homePackages");

    Ok(ProfileConfig {
        name: profile_name.to_string(),
        path: profile_path,
        system_settings,
        user_settings,
        system_packages,
        home_packages,
    })
}

/// Extract settings from a section
fn extract_settings(content: &str, section: &str) -> Vec<ConfigEntry> {
    let mut entries = Vec::new();

    // Find the section
    let section_marker = format!("{} = {{", section);
    let section_start = match content.find(&section_marker) {
        Some(pos) => pos,
        None => return entries,
    };

    // Extract lines from the section
    let section_content = &content[section_start..];

    // Parse boolean flags (most common pattern)
    for (line_no, line) in section_content.lines().enumerate() {
        let trimmed = line.trim();

        // Skip comments and empty lines
        if trimmed.starts_with('#') || trimmed.is_empty() || trimmed.starts_with("/*") {
            continue;
        }

        // Match pattern: key = value;
        if let Some((key, value)) = parse_assignment(trimmed) {
            let entry_type = infer_type(&value);
            let config_value = parse_value(&value, &entry_type);

            entries.push(ConfigEntry {
                key: key.to_string(),
                value: config_value,
                entry_type,
                description: extract_comment(section_content, line_no),
                line_number: Some(line_no),
            });
        }

        // Stop at closing brace (end of section)
        if trimmed == "};" || trimmed == "}" {
            break;
        }
    }

    entries
}

/// Extract packages from a list
fn extract_packages(content: &str, section: &str) -> Vec<String> {
    let mut packages = Vec::new();

    // Find pattern: section = pkgs: pkgs-unstable: [ ... ]
    // or simpler: section = [ ... ]
    let patterns = [
        format!("{} = pkgs: pkgs-unstable: [", section),
        format!("{} = [", section),
    ];

    for pattern in &patterns {
        if let Some(start) = content.find(pattern) {
            let after_bracket = &content[start + pattern.len()..];
            if let Some(end) = after_bracket.find(']') {
                let list_content = &after_bracket[..end];

                // Parse package names
                for line in list_content.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() || trimmed.starts_with('#') {
                        continue;
                    }

                    // Handle various package reference patterns
                    // pkgs.packageName, pkgs-unstable.packageName, packageName
                    let clean = trimmed
                        .trim_end_matches(',')
                        .trim_end_matches(';')
                        .trim();

                    if !clean.is_empty() && !clean.starts_with("/*") {
                        packages.push(clean.to_string());
                    }
                }

                break;
            }
        }
    }

    packages
}

/// Parse a key = value; assignment
fn parse_assignment(line: &str) -> Option<(&str, String)> {
    let parts: Vec<&str> = line.splitn(2, '=').collect();
    if parts.len() != 2 {
        return None;
    }

    let key = parts[0].trim();
    let value = parts[1].trim().trim_end_matches(';').trim();

    // Skip complex expressions (functions, imports, etc.)
    if value.contains("import ")
        || value.contains("pkgs.")
        || value.contains("${")
        || value.starts_with("with ")
        || value.starts_with("let ")
    {
        return None;
    }

    Some((key, value.to_string()))
}

/// Infer the type of a value
fn infer_type(value: &str) -> EntryType {
    if value == "true" || value == "false" {
        EntryType::Boolean
    } else if value.starts_with('"') && value.ends_with('"') {
        EntryType::String
    } else if value.parse::<i64>().is_ok() {
        EntryType::Number
    } else if value.starts_with('[') {
        EntryType::List
    } else {
        EntryType::Unknown
    }
}

/// Parse a value string into a ConfigValue
fn parse_value(value: &str, entry_type: &EntryType) -> ConfigValue {
    match entry_type {
        EntryType::Boolean => ConfigValue::Bool(value == "true"),
        EntryType::String => ConfigValue::String(value.trim_matches('"').to_string()),
        EntryType::Number => ConfigValue::Number(value.parse().unwrap_or(0)),
        EntryType::List => {
            // Simple list parsing
            let items: Vec<String> = value
                .trim_start_matches('[')
                .trim_end_matches(']')
                .split_whitespace()
                .map(|s| s.trim_matches('"').to_string())
                .filter(|s| !s.is_empty())
                .collect();
            ConfigValue::List(items)
        }
        EntryType::Unknown => ConfigValue::String(value.to_string()),
    }
}

/// Extract inline comment for a line
fn extract_comment(content: &str, target_line: usize) -> Option<String> {
    let lines: Vec<&str> = content.lines().collect();

    if target_line >= lines.len() {
        return None;
    }

    let line = lines[target_line];

    // Check for inline comment
    if let Some(comment_pos) = line.find('#') {
        let comment = line[comment_pos + 1..].trim();
        if !comment.is_empty() {
            return Some(comment.to_string());
        }
    }

    // Check for comment on previous line
    if target_line > 0 {
        let prev_line = lines[target_line - 1].trim();
        if prev_line.starts_with('#') {
            return Some(prev_line[1..].trim().to_string());
        }
    }

    None
}

/// Toggle a boolean flag in a profile
pub fn toggle_flag(
    profile_name: &str,
    dotfiles_path: &str,
    flag: &str,
) -> Result<bool, AppError> {
    let profile_path = format!("{}/profiles/{}-config.nix", dotfiles_path, profile_name);

    let content = std::fs::read_to_string(&profile_path)
        .map_err(|e| AppError::Internal(format!("Failed to read profile: {}", e)))?;

    // Find the flag and toggle it
    let pattern_true = format!("{} = true;", flag);
    let pattern_false = format!("{} = false;", flag);

    let (new_content, new_value) = if content.contains(&pattern_true) {
        (content.replace(&pattern_true, &pattern_false), false)
    } else if content.contains(&pattern_false) {
        (content.replace(&pattern_false, &pattern_true), true)
    } else {
        return Err(AppError::NotImplemented(format!(
            "Flag not found: {}",
            flag
        )));
    };

    std::fs::write(&profile_path, new_content)
        .map_err(|e| AppError::Internal(format!("Failed to write profile: {}", e)))?;

    tracing::info!("Toggled {} to {} in {}", flag, new_value, profile_name);

    Ok(new_value)
}

/// List all available profiles
pub fn list_profiles(dotfiles_path: &str) -> Result<Vec<String>, AppError> {
    let profiles_dir = format!("{}/profiles", dotfiles_path);

    let entries = std::fs::read_dir(&profiles_dir)
        .map_err(|e| AppError::Internal(format!("Failed to read profiles dir: {}", e)))?;

    let profiles: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            name_str.ends_with("-config.nix")
        })
        .map(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            name_str
                .trim_end_matches("-config.nix")
                .to_string()
        })
        .collect();

    Ok(profiles)
}
