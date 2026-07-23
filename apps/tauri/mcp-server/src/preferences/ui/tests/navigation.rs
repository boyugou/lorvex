use super::*;
use crate::contract::AssistantUiView;

/// The closed `AssistantUiView` enum on `ControlAppUiArgs.view` rejects
/// unknown variants at the serde-deserialize layer; the runtime
/// `control_app_ui` body never receives the unknown value, so the
/// rejection surface is now the JSON deserialize boundary.
#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_args_reject_unknown_view_at_deserialize() {
    let err = serde_json::from_value::<ControlAppUiArgs>(serde_json::json!({
        "action": "switch_view",
        "view": "definitely-not-a-view",
        "note": "test",
    }))
    .expect_err("invalid view should be rejected at the deserialize boundary");
    let message = err.to_string();
    assert!(
        message.contains("definitely-not-a-view") || message.contains("unknown variant"),
        "deserialize error should narrate the rejected variant, got: {message}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_accepts_valid_switch_view_values() {
    let conn = open_temp_db();
    seed_list(&conn, "list-1");

    let list_response = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(AssistantUiView::List),
            list_id: Some("list-1".to_string()),
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .unwrap_or_else(|error| panic!("list view should be accepted, got: {error}"));

    let list_payload: Value = serde_json::from_str(&list_response).expect("parse list response");
    assert_eq!(
        list_payload.get("action").and_then(Value::as_str),
        Some("switch_view")
    );
    assert_eq!(
        list_payload
            .get("command")
            .and_then(|command| command.get("value"))
            .and_then(|value| value.get("view"))
            .and_then(Value::as_str),
        Some("list"),
    );
    assert_eq!(
        list_payload
            .get("command")
            .and_then(|command| command.get("value"))
            .and_then(|value| value.get("list_id"))
            .and_then(Value::as_str),
        Some("list-1"),
    );

    let today_response = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(AssistantUiView::Today),
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .unwrap_or_else(|error| panic!("today view should be accepted, got: {error}"));

    let today_payload: Value = serde_json::from_str(&today_response).expect("parse today response");
    assert_eq!(
        today_payload.get("action").and_then(Value::as_str),
        Some("switch_view")
    );
    assert_eq!(
        today_payload
            .get("command")
            .and_then(|command| command.get("value"))
            .and_then(|value| value.get("view"))
            .and_then(Value::as_str),
        Some("today"),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_guard_surfaces_pending_command_metadata() {
    let conn = open_temp_db();

    let first_response = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(AssistantUiView::Today),
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .expect("first pending command should succeed");
    let first_payload: Value = serde_json::from_str(&first_response).expect("parse first response");
    let first_command_id = first_payload
        .get("command_id")
        .and_then(Value::as_str)
        .expect("first command_id")
        .to_string();

    let error = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(AssistantUiView::AiChangelog),
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: Some(false),
            note: Some("test".to_string()),
        },
    )
    .expect_err("pending-command guard should reject replacement");

    let inner_payload: Value = match error {
        crate::error::McpError::Validation(message) => {
            serde_json::from_str(&message).expect("parse raw validation payload")
        }
        other => panic!("expected validation error, got {other}"),
    };
    assert_eq!(
        inner_payload.get("error").and_then(Value::as_str),
        Some("Pending assistant_ui_command exists and allow_replace_pending=false"),
    );
    assert_eq!(
        inner_payload
            .get("pending_command")
            .and_then(|command| command.get("command_id"))
            .and_then(Value::as_str),
        Some(first_command_id.as_str()),
    );
    assert_eq!(
        inner_payload
            .get("pending_command")
            .and_then(|command| command.get("action"))
            .and_then(Value::as_str),
        Some("switch_view"),
    );
}
