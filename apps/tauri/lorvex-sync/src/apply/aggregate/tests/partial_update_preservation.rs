use super::super::apply_task_upsert;
use super::support::*;
use serde_json::{json, Value as JsonValue};

/// Every nullable column on `tasks` covered by the audit fix, with
/// a sentinel non-NULL seed value that the absent-key follow-up
/// must NOT erase.
fn full_seed_payload(list_id: &str) -> serde_json::Map<String, JsonValue> {
    let mut m = serde_json::Map::new();
    m.insert("title".into(), json!("Original title"));
    m.insert("body".into(), json!("seed body"));
    m.insert("raw_input".into(), json!("seed raw input"));
    m.insert("ai_notes".into(), json!("seed ai notes"));
    m.insert("status".into(), json!("open"));
    m.insert("list_id".into(), json!(list_id));
    m.insert("priority".into(), json!(2));
    m.insert("due_date".into(), json!("2026-05-01"));
    m.insert("due_time".into(), json!("09:30"));
    m.insert("estimated_minutes".into(), json!(45));
    m.insert("recurrence".into(), json!("FREQ=DAILY"));
    m.insert("recurrence_exceptions".into(), json!(r#"["2026-05-02"]"#));
    m.insert("spawned_from".into(), json!("parent-task-uuid-aaaa"));
    m.insert("recurrence_group_id".into(), json!("rec-group-uuid-bbbb"));
    m.insert("canonical_occurrence_date".into(), json!("2026-05-01"));
    m.insert("created_at".into(), json!("2026-05-01T08:00:00.000Z"));
    m.insert("updated_at".into(), json!("2026-05-01T08:00:00.000Z"));
    m.insert("completed_at".into(), json!("2026-05-01T11:00:00.000Z"));
    m.insert("last_deferred_at".into(), json!("2026-04-30T18:00:00.000Z"));
    m.insert("last_defer_reason".into(), json!("not_today"));
    m.insert("planned_date".into(), json!("2026-05-02"));
    m.insert("defer_count".into(), json!(7));
    m.insert(
        "recurrence_instance_key".into(),
        json!("rec-inst-uuid-cccc-2026-05-01"),
    );
    m.insert("archived_at".into(), json!("2026-05-03T12:00:00.000Z"));
    m
}

/// Apply a seed envelope, then apply a follow-up envelope that
/// drops `omit_keys`. Returns the SQLite `tasks` row as a JSON
/// `Map` with every column populated (NULLs stored as
/// `JsonValue::Null`).
fn run_partial_update(omit_keys: &[&str]) -> serde_json::Map<String, JsonValue> {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let mut full = full_seed_payload(list_id);
    let payload_v1 = JsonValue::Object(full.clone()).to_string();
    apply_task_upsert(
        &conn,
        "task-2993-partial",
        &payload_v1,
        &next_version(),
        false.into(),
        "2026-05-01T08:00:00.000Z",
    )
    .unwrap();

    for k in omit_keys {
        full.remove(*k);
    }
    // Force a strictly newer HLC for the follow-up envelope.
    let payload_v2 = JsonValue::Object(full).to_string();
    apply_task_upsert(
        &conn,
        "task-2993-partial",
        &payload_v2,
        &next_version(),
        false.into(),
        "2026-05-01T09:00:00.000Z",
    )
    .unwrap();

    let mut row = serde_json::Map::new();
    const COLS: &[&str] = &[
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        "recurrence_exceptions",
        "spawned_from",
        "recurrence_group_id",
        "canonical_occurrence_date",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        "recurrence_instance_key",
        "archived_at",
    ];
    // EXDATE list moved to `task_recurrence_exceptions` (#4585).
    // Substitute the bare column reference with the wire-form JSON
    // rebuilt from the child table so the partial-update assertions
    // continue to compare against the legacy JSON-array shape.
    let projected: Vec<String> = COLS
        .iter()
        .map(|c| {
            if *c == "recurrence_exceptions" {
                "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                  FROM task_recurrence_exceptions WHERE task_id = tasks.id)"
                    .to_string()
            } else {
                (*c).to_string()
            }
        })
        .collect();
    let select_sql = format!(
        "SELECT {} FROM tasks WHERE id = 'task-2993-partial'",
        projected.join(", ")
    );
    conn.query_row(&select_sql, [], |r| {
        for (i, col) in COLS.iter().enumerate() {
            let v: rusqlite::types::Value = r.get(i)?;
            let json_v: JsonValue = match v {
                rusqlite::types::Value::Null => JsonValue::Null,
                rusqlite::types::Value::Integer(n) => json!(n),
                rusqlite::types::Value::Real(f) => json!(f),
                rusqlite::types::Value::Text(s) => json!(s),
                rusqlite::types::Value::Blob(b) => json!(b),
            };
            row.insert((*col).to_string(), json_v);
        }
        Ok(())
    })
    .unwrap();
    row
}

/// Drop one column at a time and assert it round-trips intact.
/// Driving the assertion through a single helper means the fix
/// either covers every nullable column or every per-column case
/// fails at once.
fn assert_preserved(column: &str, expected: &JsonValue) {
    let row = run_partial_update(&[column]);
    let actual = row.get(column).cloned().unwrap_or(JsonValue::Null);
    assert_eq!(
        &actual, expected,
        "column `{column}` was NULLed by an absent-key \
             envelope; partial-update preservation regressed",
    );
}

#[test]
fn absent_body_preserves_existing_value() {
    assert_preserved("body", &json!("seed body"));
}

#[test]
fn absent_raw_input_preserves_existing_value() {
    assert_preserved("raw_input", &json!("seed raw input"));
}

#[test]
fn absent_ai_notes_preserves_existing_value() {
    assert_preserved("ai_notes", &json!("seed ai notes"));
}

#[test]
fn absent_priority_preserves_existing_value() {
    assert_preserved("priority", &json!(2));
}

#[test]
fn absent_due_date_preserves_existing_value() {
    assert_preserved("due_date", &json!("2026-05-01"));
}

#[test]
fn absent_due_time_preserves_existing_value() {
    assert_preserved("due_time", &json!("09:30"));
}

#[test]
fn absent_estimated_minutes_preserves_existing_value() {
    assert_preserved("estimated_minutes", &json!(45));
}

#[test]
fn absent_recurrence_preserves_existing_value() {
    assert_preserved("recurrence", &json!("FREQ=DAILY"));
}

#[test]
fn absent_recurrence_exceptions_preserves_existing_value() {
    assert_preserved("recurrence_exceptions", &json!(r#"["2026-05-02"]"#));
}

#[test]
fn absent_spawned_from_preserves_existing_value() {
    assert_preserved("spawned_from", &json!("parent-task-uuid-aaaa"));
}

#[test]
fn absent_recurrence_group_id_preserves_existing_value() {
    assert_preserved("recurrence_group_id", &json!("rec-group-uuid-bbbb"));
}

#[test]
fn absent_canonical_occurrence_date_preserves_existing_value() {
    assert_preserved("canonical_occurrence_date", &json!("2026-05-01"));
}

#[test]
fn absent_completed_at_preserves_existing_value() {
    assert_preserved("completed_at", &json!("2026-05-01T11:00:00.000Z"));
}

#[test]
fn absent_last_deferred_at_preserves_existing_value() {
    assert_preserved("last_deferred_at", &json!("2026-04-30T18:00:00.000Z"));
}

#[test]
fn absent_last_defer_reason_preserves_existing_value() {
    assert_preserved("last_defer_reason", &json!("not_today"));
}

#[test]
fn absent_planned_date_preserves_existing_value() {
    assert_preserved("planned_date", &json!("2026-05-02"));
}

#[test]
fn absent_defer_count_preserves_existing_value() {
    assert_preserved("defer_count", &json!(7));
}

#[test]
fn absent_recurrence_instance_key_preserves_existing_value() {
    assert_preserved(
        "recurrence_instance_key",
        &json!("rec-inst-uuid-cccc-2026-05-01"),
    );
}

#[test]
fn absent_archived_at_preserves_existing_value() {
    assert_preserved("archived_at", &json!("2026-05-03T12:00:00.000Z"));
}

#[test]
fn explicit_null_clears_value_through_partial_update_path() {
    // The companion contract: when the field IS present but
    // explicitly null, the column MUST clear to SQL NULL — the
    // partial-update gate cannot accidentally swallow real
    // clears. Pin it for `archived_at` (the field most recently
    // added to the schema and therefore the highest-risk site
    // for the bug class).
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let mut full = full_seed_payload(list_id);
    let payload_v1 = JsonValue::Object(full.clone()).to_string();
    apply_task_upsert(
        &conn,
        "task-2993-clear",
        &payload_v1,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();

    full.insert("archived_at".into(), JsonValue::Null);
    let payload_v2 = JsonValue::Object(full).to_string();
    apply_task_upsert(
        &conn,
        "task-2993-clear",
        &payload_v2,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();

    let stored: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = 'task-2993-clear'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(
        stored.is_none(),
        "explicit JSON null on archived_at must clear to SQL NULL, got {stored:?}",
    );
}
