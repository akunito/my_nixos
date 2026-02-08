//! Error types for the control panel

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};
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
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::SshConnection(msg) => (StatusCode::SERVICE_UNAVAILABLE, msg.clone()),
            AppError::SshCommand(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::Docker(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::NodeNotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::ContainerNotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::Config(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            AppError::NotImplemented(msg) => (StatusCode::NOT_IMPLEMENTED, msg.clone()),
            AppError::Validation(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
        };

        tracing::error!("Application error: {}", self);

        // For htmx requests, return an error fragment
        let body = format!(
            r#"<div class="error-message bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded">
                <strong>Error:</strong> {}
            </div>"#,
            message
        );

        (status, axum::response::Html(body)).into_response()
    }
}

impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}
