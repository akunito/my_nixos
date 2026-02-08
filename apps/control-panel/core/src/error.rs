//! Error types for the control panel
//!
//! Core error types used throughout the application.
//! Web-specific error handling (HTTP responses) is in the web crate.

use thiserror::Error;

/// Application error type
#[derive(Error, Debug)]
pub enum AppError {
    #[error("SSH connection failed: {0}")]
    SshConnection(String),

    #[error("SSH command failed: {0}")]
    SshCommand(String),

    #[error("Docker error: {0}")]
    Docker(String),

    #[error("Node not found: {0}")]
    NodeNotFound(String),

    #[error("Container not found: {0}")]
    ContainerNotFound(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Not implemented: {0}")]
    NotImplemented(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}
