use crate::contract::{UiAction, UiCommandMetadata};
use crate::error::McpError;
use serde_json::Value;

pub(crate) const fn ui_action_to_str(action: UiAction) -> &'static str {
    match action {
        UiAction::EnterFocusMode => "enter_focus_mode",
        UiAction::ExitFocusMode => "exit_focus_mode",
        UiAction::FocusTask => "focus_task",
        UiAction::OpenTask => "open_task",
        UiAction::SwitchView => "switch_view",
        UiAction::SetTheme => "set_theme",
        UiAction::SetAppearanceProfile => "set_appearance_profile",
        UiAction::SetLanguage => "set_language",
    }
}

pub(crate) fn parse_ui_command_metadata(
    raw: Option<&str>,
    field_name: &str,
) -> Result<Option<UiCommandMetadata>, McpError> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let parsed = serde_json::from_str::<Value>(raw).map_err(|error| {
        McpError::Validation(format!(
            "{field_name} must contain valid JSON object: {error}"
        ))
    })?;
    let command_id = parsed
        .get("command_id")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            McpError::Validation(format!("{field_name} must contain non-empty command_id"))
        })?
        .to_string();
    let action = parsed
        .get("action")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| McpError::Validation(format!("{field_name} must contain non-empty action")))?
        .to_string();
    Ok(Some(UiCommandMetadata {
        command_id,
        action,
        requested_at: parsed
            .get("requested_at")
            .and_then(Value::as_str)
            .map(str::to_string),
        requested_by: parsed
            .get("requested_by")
            .and_then(Value::as_str)
            .map(str::to_string),
        task_id: parsed
            .get("task_id")
            .and_then(Value::as_str)
            .map(str::to_string),
        view: parsed
            .get("view")
            .and_then(Value::as_str)
            .map(str::to_string),
        list_id: parsed
            .get("list_id")
            .and_then(Value::as_str)
            .map(str::to_string),
        theme: parsed
            .get("theme")
            .and_then(Value::as_str)
            .map(str::to_string),
        appearance_profile: parsed
            .get("appearance_profile")
            .and_then(Value::as_str)
            .map(str::to_string),
        language: parsed
            .get("language")
            .and_then(Value::as_str)
            .map(str::to_string),
        note: parsed
            .get("note")
            .and_then(Value::as_str)
            .map(str::to_string),
    }))
}

// `parse_json_string_value` was promoted to the
// canonical `lorvex_domain::parse_json_string_field` so every router
// shares one strict JSON-string field parser. The MCP error
// `From<JsonStringFieldError>` impl preserves the previous wire
// wording.
