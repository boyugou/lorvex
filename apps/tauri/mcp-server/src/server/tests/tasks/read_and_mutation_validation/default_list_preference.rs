use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn create_task_uses_plain_string_default_list_id_preference_and_rejects_double_encoded_values() {
    let server = make_server();
    seed_list_named(&server, "list-default", "Default");

    server
        .set_preference(Parameters(SetPreferenceArgs {
            key: lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID.to_string(),
            value: json!("list-default"),
            idempotency_key: None,
        }))
        .expect("plain-string default_list_id should succeed");

    let created = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Captured via default list".to_string(),
            list_id: None,
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("default_list_id-backed task creation should succeed");
    let payload: Value = serde_json::from_str(&created).expect("parse create_task payload");
    assert_eq!(payload["task"]["list_id"], json!("list-default"));

    let error = server
        .set_preference(Parameters(SetPreferenceArgs {
            key: lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID.to_string(),
            value: json!(r#""list-default""#),
            idempotency_key: None,
        }))
        .expect_err("double-encoded string literal should fail");
    assert!(
        error.contains("plain strings") || error.contains("JSON-encoded string literals"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_uses_plain_string_default_list_id_set_via_mcp_preference() {
    let server = make_server();
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
                (
                    "default-list",
                    "Inbox",
                    "0000000000000_0000_0000000000000000",
                    "2026-04-03T00:00:00Z",
                    "2026-04-03T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed default list");

    server
        .set_preference(Parameters(SetPreferenceArgs {
            key: lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID.to_string(),
            value: json!("default-list"),
            idempotency_key: None,
        }))
        .expect("set default_list_id preference");

    let response = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Preference-backed capture".to_string(),
            list_id: None,
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,
            planned_date: None,
            depends_on: None,
            completed: None,
            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect("create_task should resolve default_list_id");

    let payload: Value = serde_json::from_str(&response).expect("parse create task response");
    assert_eq!(payload["task"]["list_id"], json!("default-list"));
}
