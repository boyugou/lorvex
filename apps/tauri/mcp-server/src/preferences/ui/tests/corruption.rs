use super::*;
use crate::preferences::ui::{ASSISTANT_UI_COMMAND_KEY, ASSISTANT_UI_HANDLED_ID_KEY};

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_rejects_malformed_pending_command_state() {
    let conn = open_temp_db();
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        params![ASSISTANT_UI_COMMAND_KEY, "{not-valid-json"],
    )
    .expect("seed malformed pending command");

    let error = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(crate::contract::AssistantUiView::Today),
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .expect_err("malformed pending command should fail")
    .to_string();

    assert!(
        error.contains(ASSISTANT_UI_COMMAND_KEY),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_rejects_malformed_handled_command_state() {
    let conn = open_temp_db();
    let pending = serde_json::json!({
        "command_id": "cmd-1",
        "action": "switch_view",
    });
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        params![ASSISTANT_UI_COMMAND_KEY, pending.to_string()],
    )
    .expect("seed pending command");
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        params![ASSISTANT_UI_HANDLED_ID_KEY, "{\"oops\":true}"],
    )
    .expect("seed malformed handled command");

    let error = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::SwitchView,
            task_id: None,
            view: Some(crate::contract::AssistantUiView::Today),
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .expect_err("malformed handled command should fail")
    .to_string();

    assert!(
        error.contains(ASSISTANT_UI_HANDLED_ID_KEY),
        "unexpected error: {error}"
    );
}
