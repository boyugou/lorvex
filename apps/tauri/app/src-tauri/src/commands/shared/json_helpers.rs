//! JSON parsing helpers used by IPC handlers.

use crate::error::{AppError, AppResult};

pub(crate) fn parse_canonical_json_value(raw: &str, context: &str) -> AppResult<serde_json::Value> {
    serde_json::from_str::<serde_json::Value>(raw).map_err(|error| {
        AppError::Serialization(format!("{context} must be canonical JSON: {error}"))
    })
}

pub(crate) fn to_json_value<T: serde::Serialize>(value: &T) -> AppResult<serde_json::Value> {
    serde_json::to_value(value).map_err(AppError::from)
}
