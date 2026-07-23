use super::*;

#[test]
#[serial_test::serial(hlc)]
fn create_task_drops_raw_input_when_record_raw_input_is_false() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
                (
                    lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT,
                    "false",
                    "0000000000000_0000_0000000000000000",
                    "2026-03-29T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed preference");

    let response = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Privacy Test".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: Some("sensitive transcript".to_string()),
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create task should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse create task response");
    let task = payload
        .get("task")
        .expect("response should have task field");
    assert_eq!(task.get("raw_input"), Some(&Value::Null));
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_rejects_malformed_record_raw_input_preference() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
                (
                    lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT,
                    "\"not-a-bool\"",
                    "0000000000000_0000_0000000000000000",
                    "2026-03-29T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed malformed preference");

    let error = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Privacy Test".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: Some("sensitive transcript".to_string()),
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect_err("malformed record_raw_input preference should fail");

    assert!(
        error.contains("record_raw_input"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_surfaces_record_raw_input_preference_read_failures() {
    use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    server
        .with_conn(|conn| {
            conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
                AuthAction::Read {
                    table_name: "preferences",
                    ..
                } => Authorization::Deny,
                _ => Authorization::Allow,
            }))
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("install authorizer");

    let error = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Privacy Test".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: Some("sensitive transcript".to_string()),
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect_err("preference read failure should fail task creation");

    assert!(
        error.contains("record_raw_input")
            || error.contains("preferences")
            || error.contains("not authorized"),
        "unexpected error: {error}"
    );
}
