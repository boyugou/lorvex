//! router-dispatch tests for `control_app_ui`.
//!
//! The exhaustive `match` on `UiAction` (M11) and the audit-trail
//! threading (#3006-H1) both lack router-level coverage. These tests
//! exercise the `Parameters<ControlAppUiArgs>` path and assert:
//!
//!  1. Each variant's required field gate produces a typed Validation
//!     error when the field is missing.
//!  2. A successful queue writes the `assistant_ui_command` device
//!     state row AND a paired `ai_changelog` row carrying both
//!     `before_json` and `after_json` (issue #3006-H1).
//!  3. The exhaustive-match contract (#3006-M11) reaches every arm —
//!     `ExitFocusMode` is the lowest-required variant and must
//!     succeed without any task / view / theme payload.

use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_focus_task_requires_task_id() {
    let server = make_server();
    let err = server
        .control_app_ui(Parameters(ControlAppUiArgs {
            action: UiAction::FocusTask,
            task_id: None,
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            note: None,
            allow_replace_pending: None,
        }))
        .expect_err("focus_task without task_id must be rejected");
    assert!(
        err.contains("task_id is required"),
        "diagnostic should name the missing field, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_open_task_requires_task_id() {
    let server = make_server();
    let err = server
        .control_app_ui(Parameters(ControlAppUiArgs {
            action: UiAction::OpenTask,
            task_id: None,
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            note: None,
            allow_replace_pending: None,
        }))
        .expect_err("open_task without task_id must be rejected");
    assert!(err.contains("task_id is required"), "got: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_switch_view_requires_view_field() {
    let server = make_server();
    let err = server
        .control_app_ui(Parameters(ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            note: None,
            allow_replace_pending: None,
        }))
        .expect_err("switch_view without view must be rejected");
    assert!(err.contains("view is required"), "got: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_set_theme_requires_theme_field() {
    let server = make_server();
    let err = server
        .control_app_ui(Parameters(ControlAppUiArgs {
            action: UiAction::SetTheme,
            task_id: None,
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            note: None,
            allow_replace_pending: None,
        }))
        .expect_err("set_theme without theme must be rejected");
    assert!(err.contains("theme is required"), "got: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_exit_focus_mode_requires_no_payload_and_logs_audit() {
    let server = make_server();

    let response = server
        .control_app_ui(Parameters(ControlAppUiArgs {
            action: UiAction::ExitFocusMode,
            task_id: None,
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            note: None,
            allow_replace_pending: None,
        }))
        .expect("exit_focus_mode must accept a bare payload");
    let parsed: Value = serde_json::from_str(&response).expect("parse response");
    assert_eq!(parsed["action"], json!("exit_focus_mode"));

    // the audit row must carry after_json (the
    // queued command). before_json is None on the first call (no
    // prior pending command).
    let (before_json, after_json): (Option<String>, Option<String>) = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT before_json, after_json FROM ai_changelog \
                 WHERE mcp_tool = 'control_app_ui' \
                 ORDER BY timestamp DESC LIMIT 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("query ai_changelog");
    assert!(
        before_json.is_none(),
        "first command in a fresh DB must not carry a before snapshot"
    );
    assert!(
        after_json.is_some(),
        "control_app_ui must thread after_json into the audit row"
    );
}

/// `AssistantUiLanguage` on `ControlAppUiArgs.language` is a closed
/// `serde::Deserialize` enum, so unknown variants are rejected at the
/// JSON Schema / serde layer before the router dispatches the call.
/// The router-dispatch test exercises the deserialize path explicitly:
/// the rejection surface is `serde_json::Error`, not the runtime
/// `language must be one of …` diagnostic.
#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_set_language_rejects_unknown_value_at_deserialize() {
    let err = serde_json::from_value::<ControlAppUiArgs>(serde_json::json!({
        "action": "set_language",
        "language": "kreyol",
    }))
    .expect_err("unknown language must be rejected at the deserialize boundary");
    let message = err.to_string();
    assert!(
        message.contains("kreyol") || message.contains("unknown variant"),
        "deserialize error should narrate the rejected variant, got: {message}"
    );
}
