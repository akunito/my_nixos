//! Profile configuration editor module (Phase 3)
//!
//! - View profile configuration
//! - Edit feature flags and settings
//! - Manage packages
//! - Duplicate profiles

pub mod parser;
pub mod routes;

use serde::{Deserialize, Serialize};

/// Parsed profile configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileConfig {
    pub name: String,
    pub path: String,
    pub system_settings: Vec<ConfigEntry>,
    pub user_settings: Vec<ConfigEntry>,
    pub system_packages: Vec<String>,
    pub home_packages: Vec<String>,
}

/// Configuration entry (key-value pair with metadata)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigEntry {
    pub key: String,
    pub value: ConfigValue,
    pub entry_type: EntryType,
    pub description: Option<String>,
    pub line_number: Option<usize>,
}

/// Configuration value types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ConfigValue {
    Bool(bool),
    String(String),
    Number(i64),
    List(Vec<String>),
    Null,
}

/// Entry type classification
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum EntryType {
    Boolean,
    String,
    Number,
    List,
    Unknown,
}

impl ConfigValue {
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            ConfigValue::Bool(b) => Some(*b),
            _ => None,
        }
    }

    #[allow(dead_code)]
    pub fn as_string(&self) -> Option<&str> {
        match self {
            ConfigValue::String(s) => Some(s),
            _ => None,
        }
    }

    pub fn display(&self) -> String {
        match self {
            ConfigValue::Bool(b) => b.to_string(),
            ConfigValue::String(s) => s.clone(),
            ConfigValue::Number(n) => n.to_string(),
            ConfigValue::List(l) => format!("[{}]", l.join(", ")),
            ConfigValue::Null => "null".to_string(),
        }
    }
}
