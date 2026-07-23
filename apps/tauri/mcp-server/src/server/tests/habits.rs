//! router-dispatch tests for the habit surface.
//!
//! Pre-fix the habit module had per-function unit tests (see
//! `server_habits/writes.rs::tests`) but the rmcp `tool_router` glue
//! that wraps `Parameters<...>` and threads through `with_conn_typed`
//! was uncovered. This test module exercises the full
//! `router → handler → DB` path so a regression in the wrapper layer
//! (e.g. a missing arg field, a typo in the tool name, an
//! `Option<...>` accidentally treated as required by serde) fails
//! loudly.

use super::*;

#[test]
#[serial_test::serial(hlc)]
fn create_habit_via_router_persists_row_and_returns_full_shape() {
    let server = make_server();

    let response = server
        .create_habit(Parameters(CreateHabitArgs {
            name: "Read 30 minutes".to_string(),
            icon: Some("📚".to_string()),
            color: Some("#4CAF50".to_string()),
            cue: Some("After coffee".to_string()),
            frequency_type: Some(FrequencyType::Daily),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: Some(1),
            idempotency_key: None,
        }))
        .expect("create_habit should succeed");

    let parsed: Value = serde_json::from_str(&response).expect("parse create_habit response");
    let id = parsed
        .get("id")
        .and_then(Value::as_str)
        .expect("response carries id");
    assert!(!id.is_empty(), "id must not be empty");
    assert_eq!(parsed.get("name"), Some(&Value::from("Read 30 minutes")));
    assert_eq!(parsed.get("cue"), Some(&Value::from("After coffee")));
    assert_eq!(parsed.get("color"), Some(&Value::from("#4CAF50")));

    // Audit log row must exist for the create.
    let log_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'create_habit'",
                [],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("query ai_changelog");
    assert_eq!(log_count, 1, "create_habit must log to ai_changelog");
}

#[test]
#[serial_test::serial(hlc)]
fn create_habit_via_router_rejects_invalid_color() {
    let server = make_server();

    let err = server
        .create_habit(Parameters(CreateHabitArgs {
            name: "Hydrate".to_string(),
            icon: None,
            // Not a valid hex shape — the validator at the trust
            // boundary must reject before INSERT.
            color: Some("not-a-color".to_string()),
            cue: None,
            frequency_type: Some(FrequencyType::Daily),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            idempotency_key: None,
        }))
        .expect_err("invalid hex color must be rejected");
    assert!(!err.is_empty(), "router must surface a typed error string");
}

#[test]
#[serial_test::serial(hlc)]
fn complete_and_uncomplete_habit_via_router_round_trip() {
    let server = make_server();

    let create = server
        .create_habit(Parameters(CreateHabitArgs {
            name: "Stretch".to_string(),
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some(FrequencyType::Daily),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            idempotency_key: None,
        }))
        .expect("create_habit should succeed");
    let id = serde_json::from_str::<Value>(&create).expect("parse create_habit")["id"]
        .as_str()
        .expect("id present")
        .to_string();

    server
        .complete_habit(Parameters(CompleteHabitArgs {
            id: id.clone(),
            date: Some("2026-04-28".to_string()),
            note: None,
            idempotency_key: None,
        }))
        .expect("complete_habit");

    server
        .uncomplete_habit(Parameters(UncompleteHabitArgs {
            id: id.clone(),
            date: Some("2026-04-28".to_string()),
            idempotency_key: None,
        }))
        .expect("uncomplete_habit");

    // Verify no completion row remains for that date.
    let remaining: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
                rusqlite::params![id, "2026-04-28"],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("count habit_completions");
    assert_eq!(remaining, 0, "uncomplete must remove all rows for the date");
}

/// the dispatch glue must roll back the entire batch
/// when any per-id call fails. Pre-fix the response said "5 of 7
/// succeeded" but the underlying rusqlite txn rolled back wholesale,
/// so the changelog and the response disagreed. The router-level
/// invocation must surface a typed error and leave zero rows behind.
#[test]
#[serial_test::serial(hlc)]
fn batch_complete_habit_via_router_atomic_on_partial_failure() {
    let server = make_server();
    let create = server
        .create_habit(Parameters(CreateHabitArgs {
            name: "Walk".to_string(),
            icon: None,
            color: None,
            cue: None,
            frequency_type: Some(FrequencyType::Daily),
            weekdays: None,
            per_period_target: None,
            day_of_month: None,
            target_count: None,
            idempotency_key: None,
        }))
        .expect("create habit");
    let real_id = serde_json::from_str::<Value>(&create).unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let err = server
        .batch_complete_habit(Parameters(BatchCompleteHabitArgs {
            habit_ids: vec![real_id.clone(), "phantom-habit".to_string()],
            date: Some("2026-04-28".to_string()),
            idempotency_key: None,
        }))
        .expect_err("batch with phantom id must reject wholesale");
    assert!(!err.is_empty());

    // Atomicity: no completion row was written for the real id.
    let remaining: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ?1",
                rusqlite::params![real_id],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("count habit_completions");
    assert_eq!(
        remaining, 0,
        "rejected batch must not leave the real habit with a completion"
    );
}
