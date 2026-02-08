//! HTTP Basic Authentication middleware

use axum::{
    body::Body,
    extract::State,
    http::{header, Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use base64::{engine::general_purpose::STANDARD, Engine};
use std::sync::Arc;

use crate::AppState;

/// Authentication middleware that validates HTTP Basic Auth credentials
pub async fn auth_middleware(
    State(state): State<Arc<AppState>>,
    request: Request<Body>,
    next: Next,
) -> Response {
    // Skip auth for health check endpoint
    if request.uri().path() == "/health" {
        return next.run(request).await;
    }

    // Get Authorization header
    let auth_header = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok());

    match auth_header {
        Some(auth) if validate_basic_auth(auth, &state.config.auth.username, &state.config.auth.password) => {
            next.run(request).await
        }
        _ => {
            // Return 401 with WWW-Authenticate header
            (
                StatusCode::UNAUTHORIZED,
                [(header::WWW_AUTHENTICATE, "Basic realm=\"Control Panel\"")],
                "Unauthorized",
            )
                .into_response()
        }
    }
}

/// Validate HTTP Basic Auth credentials
fn validate_basic_auth(auth_header: &str, expected_user: &str, expected_pass: &str) -> bool {
    // Parse "Basic <base64>" format
    if !auth_header.starts_with("Basic ") {
        return false;
    }

    let encoded = &auth_header[6..];

    // Decode base64
    let decoded = match STANDARD.decode(encoded) {
        Ok(d) => d,
        Err(_) => return false,
    };

    // Parse "user:password" format
    let credentials = match String::from_utf8(decoded) {
        Ok(c) => c,
        Err(_) => return false,
    };

    let parts: Vec<&str> = credentials.splitn(2, ':').collect();
    if parts.len() != 2 {
        return false;
    }

    // Constant-time comparison to prevent timing attacks
    let user_matches = constant_time_compare(parts[0], expected_user);
    let pass_matches = constant_time_compare(parts[1], expected_pass);

    user_matches && pass_matches
}

/// Constant-time string comparison to prevent timing attacks
fn constant_time_compare(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }

    let mut result = 0u8;
    for (x, y) in a.bytes().zip(b.bytes()) {
        result |= x ^ y;
    }
    result == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_basic_auth() {
        // "admin:password" in base64
        let auth = "Basic YWRtaW46cGFzc3dvcmQ=";
        assert!(validate_basic_auth(auth, "admin", "password"));
        assert!(!validate_basic_auth(auth, "admin", "wrong"));
        assert!(!validate_basic_auth(auth, "wrong", "password"));
    }

    #[test]
    fn test_invalid_auth_format() {
        assert!(!validate_basic_auth("Bearer token", "admin", "password"));
        assert!(!validate_basic_auth("Basic !!invalid!!", "admin", "password"));
    }
}
