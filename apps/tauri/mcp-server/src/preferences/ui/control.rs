use crate::contract::{ControlAppUiArgs, UiAction, UiCommandMetadata};
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::preferences::parse_preference_row_value;
use crate::runtime::change_tracking::{log_change, resolve_ai_actor_name, LogChangeParams};
use crate::system::handler_support::{new_uuid, utc_now_iso};
use lorvex_domain::naming::STATUS_OPEN;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{
    parse_ui_command_metadata, ui_action_to_str, ASSISTANT_UI_COMMAND_KEY,
    ASSISTANT_UI_HANDLED_ID_KEY,
};
use lorvex_domain::parse_json_string_field;

pub(crate) fn control_app_ui(
    conn: &Connection,
    args: ControlAppUiArgs,
) -> Result<String, McpError> {
    let action = ui_action_to_str(args.action);

    // dispatch through an exhaustive `match` on the
    // typed `UiAction` enum so a future variant can never silently
    // bypass the per-action allowlist gate.
    // chain of `if matches!(...)` blocks: a new variant added to
    // `UiAction` would compile, dispatch through `ui_action_to_str`,
    // and persist into `device_state` as a queued command without ever
    // tripping a Validation arm. The exhaustive match makes that
    // omission a compile error.
    match args.action {
        UiAction::EnterFocusMode | UiAction::FocusTask => {
            // Both require a task_id and the task must be open.
            // `FocusTask` always requires a task_id; `EnterFocusMode`
            // accepts a missing task_id (resume current focus) but
            // when one is supplied, the row must exist + be open.
            if matches!(args.action, UiAction::FocusTask) && args.task_id.is_none() {
                return Err(McpError::Validation(
                    "task_id is required for focus_task".to_string(),
                ));
            }
            if let Some(task_id) = args.task_id.as_ref() {
                let task_status: Option<String> = conn
                    .query_row(
                        "SELECT status FROM tasks WHERE id = ? AND archived_at IS NULL",
                        [task_id],
                        |row| row.get(0),
                    )
                    .optional()?;
                let Some(task_status) = task_status else {
                    return Err(McpError::NotFound(format!("Task '{task_id}' not found")));
                };
                if task_status != STATUS_OPEN {
                    return Err(McpError::Validation(format!(
                        "{action} requires task '{task_id}' to be open"
                    )));
                }
            }
        }
        UiAction::OpenTask => {
            let Some(task_id) = args.task_id.as_ref() else {
                return Err(McpError::Validation(
                    "task_id is required for open_task".to_string(),
                ));
            };
            let task_status: Option<String> = conn
                .query_row(
                    "SELECT status FROM tasks WHERE id = ? AND archived_at IS NULL",
                    [task_id],
                    |row| row.get(0),
                )
                .optional()?;
            if task_status.is_none() {
                return Err(McpError::NotFound(format!("Task '{task_id}' not found")));
            }
        }
        UiAction::SwitchView => {
            // The closed `AssistantUiView` enum on `ControlAppUiArgs.view`
            // already rejects unknown variants at the JSON Schema /
            // serde-deserialize layer, so this body only enforces the
            // per-action *required* check + the contextual `list_id`
            // shape gate that the type system can't express.
            let Some(view) = args.view else {
                return Err(McpError::Validation(
                    "view is required for switch_view".to_string(),
                ));
            };
            if matches!(view, crate::contract::AssistantUiView::List) {
                let Some(list_id) = args.list_id.as_ref() else {
                    return Err(McpError::Validation(
                        "list_id is required when view is list".to_string(),
                    ));
                };
                let list_exists: Option<i64> = conn
                    .query_row("SELECT 1 FROM lists WHERE id = ?", [list_id], |row| {
                        row.get(0)
                    })
                    .optional()?;
                if list_exists.is_none() {
                    return Err(McpError::NotFound(format!("List '{list_id}' not found")));
                }
            }
        }
        UiAction::SetTheme => {
            // Closed `ThemeMode` enum gates the value at deserialize.
            if args.theme.is_none() {
                return Err(McpError::Validation(
                    "theme is required for set_theme".to_string(),
                ));
            }
        }
        UiAction::SetAppearanceProfile => {
            // Closed `AppearanceProfile` enum gates the value at deserialize.
            if args.appearance_profile.is_none() {
                return Err(McpError::Validation(
                    "appearance_profile is required for set_appearance_profile".to_string(),
                ));
            }
        }
        UiAction::SetLanguage => {
            // Closed `AssistantUiLanguage` enum gates the value at deserialize.
            if args.language.is_none() {
                return Err(McpError::Validation(
                    "language is required for set_language".to_string(),
                ));
            }
        }
        UiAction::ExitFocusMode => {
            // No additional payload required; the device-state insert
            // below carries the bare command.
        }
    }

    let now = utc_now_iso();
    let command_id = new_uuid();
    // Render the typed `Option<…>` variants back to the canonical wire
    // strings before they land on the device-state command record. The
    // device_state row carries the snake_case wire token so the Tauri
    // poll site (and any peer that mirrors device_state) can dispatch
    // without re-importing the typed enum vocabulary.
    let command = UiCommandMetadata {
        command_id: command_id.clone(),
        action: action.to_string(),
        task_id: args.task_id.clone(),
        view: args.view.map(|v| v.as_wire_str().to_string()),
        list_id: args.list_id.clone(),
        theme: args.theme.map(|v| v.as_wire_str().to_string()),
        appearance_profile: args.appearance_profile.map(|v| v.as_wire_str().to_string()),
        language: args.language.map(|v| v.as_wire_str().to_string()),
        note: args.note.clone(),
        requested_at: Some(now),
        requested_by: Some(resolve_ai_actor_name()),
    };

    let allow_replace_pending = args.allow_replace_pending != Some(false);
    let before = query_one_as_json(
        conn,
        "SELECT key, value FROM device_state WHERE key = ?",
        [ASSISTANT_UI_COMMAND_KEY.to_string()],
    )?;
    let handled = query_one_as_json(
        conn,
        "SELECT key, value FROM device_state WHERE key = ?",
        [ASSISTANT_UI_HANDLED_ID_KEY.to_string()],
    )?;
    let pending_candidate = parse_ui_command_metadata(
        before
            .as_ref()
            .and_then(|value| value.get("value"))
            .and_then(Value::as_str),
        ASSISTANT_UI_COMMAND_KEY,
    )?;
    let handled_command_id = parse_json_string_field(
        handled
            .as_ref()
            .and_then(|value| value.get("value"))
            .and_then(Value::as_str),
        ASSISTANT_UI_HANDLED_ID_KEY,
    )?;
    let has_pending_command = pending_candidate.as_ref().is_some_and(|candidate| {
        handled_command_id.as_deref() != Some(candidate.command_id.as_str())
    });

    if has_pending_command && !allow_replace_pending {
        let payload = json!({
            "error": "Pending assistant_ui_command exists and allow_replace_pending=false",
            "pending_command": pending_candidate,
        });
        return Err(McpError::Validation(serde_json::to_string(&payload)?));
    }

    let command_value = serde_json::to_string(&command)?;
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (ASSISTANT_UI_COMMAND_KEY, &command_value),
    )?;

    let after_row = query_one_as_json(
        conn,
        "SELECT key, value FROM device_state WHERE key = ?",
        [ASSISTANT_UI_COMMAND_KEY.to_string()],
    )?
    .ok_or_else(|| {
        McpError::Internal(format!(
            "Failed to read back device_state key '{ASSISTANT_UI_COMMAND_KEY}'"
        ))
    })?;
    let response_pref = parse_preference_row_value(after_row.clone())?;

    let summary = if has_pending_command {
        format!(
            "Queued app UI command \"{action}\" (replaced pending \"{}\")",
            pending_candidate
                .as_ref()
                .map_or("unknown", |candidate| candidate.action.as_str()),
        )
    } else {
        format!("Queued app UI command \"{action}\"")
    };
    let replaced_pending_command = if has_pending_command {
        pending_candidate
    } else {
        None
    };
    let operation = if before.is_some() { "update" } else { "create" };
    // thread the captured pre/post device_state row
    // through the changelog so the diff renderer sees what changed.
    // The earlier shape passed `None` for both slots even though both
    // snapshots were already in scope (`before` from line 138,
    // `after_row` from line 183), erasing the audit trail for every
    // assistant UI command.
    log_change(
        conn,
        LogChangeParams::new(
            operation,
            lorvex_domain::naming::ENTITY_DEVICE_STATE,
            "control_app_ui",
            summary,
        )
        .with_entity_id(ASSISTANT_UI_COMMAND_KEY.to_string())
        .with_before_opt(before)
        .with_after(after_row),
        None,
    )?;

    let payload = json!({
        "command_id": command_id,
        "action": action,
        "note": args.note,
        "command": response_pref,
        "replaced_pending_command": replaced_pending_command,
        "pending_replaced": has_pending_command,
    });
    Ok(serde_json::to_string(&payload)?)
}
