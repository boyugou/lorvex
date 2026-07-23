use crate::error::McpError;
use crate::tasks::validation::validate_string_length;
use lorvex_domain::memory::{is_human_owned_memory_key, normalize_memory_key};
use lorvex_domain::validation::KV_KEY_MAX_CHARS;

pub(super) fn normalize_mcp_memory_key(raw_key: &str) -> Result<String, McpError> {
    let key = normalize_memory_key(raw_key);
    if key.is_empty() {
        return Err(McpError::Validation("key must not be empty".to_string()));
    }
    validate_string_length(&key, "key", KV_KEY_MAX_CHARS)?;
    Ok(key)
}

pub(super) fn reject_human_owned_ai_memory_key(key: &str) -> Result<(), McpError> {
    if is_human_owned_memory_key(key) {
        return Err(McpError::Validation(format!(
            "key '{key}' is human-owned and cannot be changed through MCP. Ask the user to edit notes_for_ai in the app UI."
        )));
    }
    Ok(())
}
