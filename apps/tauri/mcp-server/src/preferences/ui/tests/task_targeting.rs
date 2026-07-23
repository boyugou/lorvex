use super::*;

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_rejects_focus_task_for_non_open_tasks() {
    let conn = open_temp_db();
    seed_task(&conn, "task-completed", "completed");

    let error = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::FocusTask,
            task_id: Some("task-completed".to_string()),
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .expect_err("focus_task should reject non-open tasks");

    // #2182: validation failures are structured JSON on the boundary.
    let raw = String::from(error);
    let payload: serde_json::Value =
        serde_json::from_str(&raw).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "validation");
    assert_eq!(
        payload["message"],
        "focus_task requires task 'task-completed' to be open"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_rejects_enter_focus_mode_for_non_open_target_tasks() {
    let conn = open_temp_db();
    seed_task(&conn, "task-completed", "completed");

    let error = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::EnterFocusMode,
            task_id: Some("task-completed".to_string()),
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .expect_err("enter_focus_mode should reject non-open target tasks");

    // #2182: validation failures are structured JSON on the boundary.
    let raw = String::from(error);
    let payload: serde_json::Value =
        serde_json::from_str(&raw).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "validation");
    assert_eq!(
        payload["message"],
        "enter_focus_mode requires task 'task-completed' to be open"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_accepts_enter_focus_mode_for_open_target_tasks() {
    let conn = open_temp_db();
    seed_task(&conn, "task-open", "open");

    let response = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::EnterFocusMode,
            task_id: Some("task-open".to_string()),
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .unwrap_or_else(|error| {
        panic!("enter_focus_mode should accept open target tasks, got: {error}")
    });

    let payload: Value = serde_json::from_str(&response).expect("parse response");
    assert_eq!(
        payload.get("action").and_then(Value::as_str),
        Some("enter_focus_mode")
    );
    assert_eq!(
        payload
            .get("command")
            .and_then(|command| command.get("value"))
            .and_then(|value| value.get("task_id"))
            .and_then(Value::as_str),
        Some("task-open"),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_allows_open_task_for_completed_tasks() {
    let conn = open_temp_db();
    seed_task(&conn, "task-completed", "completed");

    let response = control_app_ui(
        &conn,
        ControlAppUiArgs {
            action: UiAction::OpenTask,
            task_id: Some("task-completed".to_string()),
            view: None,
            list_id: None,
            theme: None,
            appearance_profile: None,
            language: None,
            allow_replace_pending: None,
            note: Some("test".to_string()),
        },
    )
    .unwrap_or_else(|error| {
        panic!("open_task should accept existing completed tasks, got: {error}")
    });

    let payload: Value = serde_json::from_str(&response).expect("parse response");
    assert_eq!(
        payload.get("action").and_then(Value::as_str),
        Some("open_task")
    );
    assert_eq!(
        payload
            .get("command")
            .and_then(|command| command.get("value"))
            .and_then(|value| value.get("task_id"))
            .and_then(Value::as_str),
        Some("task-completed"),
    );
}
