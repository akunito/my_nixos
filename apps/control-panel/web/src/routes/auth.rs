//! HTTP Basic Auth middleware

use axum::{
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::Response,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use std::sync::Arc;

use crate::AppState;

/// Basic auth middleware
pub async fn basic_auth_middleware(
    State(state): State<Arc<AppState>>,
    request: Request<Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    // Check for Authorization header
    let auth_header = request
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok());

    if let Some(auth_value) = auth_header {
        if auth_value.starts_with("Basic ") {
            let encoded = &auth_value[6..];
            if let Ok(decoded) = STANDARD.decode(encoded) {
                if let Ok(credentials) = String::from_utf8(decoded) {
                    if let Some((username, password)) = credentials.split_once(':') {
                        if username == state.config.auth.username
                            && password == state.config.auth.password
                        {
                            return Ok(next.run(request).await);
                        }
                    }
                }
            }
        }
    }

    // Return 401 with WWW-Authenticate header
    Err(StatusCode::UNAUTHORIZED)
}
