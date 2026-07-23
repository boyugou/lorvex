use super::body_writes_effects::*;
use crate::commands::shared::test_support::tid;
use crate::error::CliError;
use lorvex_store::open_db_in_memory;
use rusqlite::Connection;

const T_APPEND_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000a01";
const T_APPEND_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000000a02";
const T_APPEND_3: &str = "01966a3f-7c8b-7d4e-8f3a-000000000a03";
const T_AINOTES_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000b01";
const T_AINOTES_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000000b02";
const T_3493_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000003493";
const T_REX_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000000c02";

fn seed_task(conn: &Connection, id: &str, title: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .created_at("2026-04-25T00:00:00Z")
        .insert(conn);
}

fn seed_recurring_task(conn: &Connection, id: &str) {
    // The schema enforces: recurrence IS NULL OR (due_date AND
    // recurrence_group_id AND canonical_occurrence_date are all
    // set). TaskBuilder doesn't expose `canonical_occurrence_date`,
    // so this seed must stay raw to satisfy the CHECK.
    let recurrence = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at, \
                            due_date, recurrence, recurrence_group_id, \
                            canonical_occurrence_date) \
         VALUES (?1, 'Standup', 'open', '0000000000000_0000_0000000000000000', \
                 '2026-04-20T00:00:00Z', '2026-04-20T00:00:00Z', '2026-04-20', ?2, \
                 'rg-1', '2026-04-20')",
        rusqlite::params![id, recurrence],
    )
    .expect("seed recurring task");
}

#[test]
fn append_to_task_body_creates_body_when_none() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_APPEND_1, "Write report");
    let row =
        append_to_task_body_with_conn(&mut conn, &tid(T_APPEND_1), "First note").expect("append");
    assert_eq!(row.core().body(), Some("First note"));
}

#[test]
fn append_to_task_body_appends_with_separator() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_APPEND_2, "Write report");
    append_to_task_body_with_conn(&mut conn, &tid(T_APPEND_2), "First note").unwrap();
    let row = append_to_task_body_with_conn(&mut conn, &tid(T_APPEND_2), "Second note")
        .expect("append second");
    assert_eq!(row.core().body(), Some("First note\n\nSecond note"));
}

#[test]
fn append_to_task_body_rejects_empty_text() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_APPEND_3, "Title");
    let err =
        append_to_task_body_with_conn(&mut conn, &tid(T_APPEND_3), "   ").expect_err("empty text");
    assert!(matches!(err, CliError::Validation(_)));
}

#[test]
fn add_ai_notes_creates_dated_block_when_none() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_AINOTES_1, "Title");
    let row =
        add_ai_notes_with_conn(&mut conn, &tid(T_AINOTES_1), "Plan first").expect("add notes");
    let notes = row.core().ai_notes().expect("notes set");
    assert!(notes.ends_with(": Plan first"), "got: {notes}");
}

#[test]
fn add_ai_notes_appends_with_dated_separator() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_AINOTES_2, "Title");
    add_ai_notes_with_conn(&mut conn, &tid(T_AINOTES_2), "First").unwrap();
    let row = add_ai_notes_with_conn(&mut conn, &tid(T_AINOTES_2), "Second").unwrap();
    let notes = row.core().ai_notes().expect("notes");
    assert!(
        notes.contains("\n\n---\n"),
        "expected dated separator: {notes}"
    );
    assert!(notes.contains(": Second"));
}

#[test]
fn add_recurrence_exception_round_trips() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000020";
    seed_recurring_task(&conn, task_id);
    let row = add_task_recurrence_exception_with_conn(&mut conn, &tid(task_id), "2026-04-22")
        .expect("add exception");
    assert!(
        row.recurrence()
            .recurrence_exceptions()
            .unwrap_or("")
            .contains("2026-04-22"),
        "exception not stored: {:?}",
        row.recurrence().recurrence_exceptions()
    );
    let row2 = remove_task_recurrence_exception_with_conn(&mut conn, &tid(task_id), "2026-04-22")
        .expect("remove exception");
    let after = row2
        .recurrence()
        .recurrence_exceptions()
        .unwrap_or_default();
    assert!(
        !after.contains("2026-04-22"),
        "exception still present after remove: {after}"
    );
}

/// #3493 regression: the returned `TaskRow` must be the in-tx
/// post-mutation snapshot deserialized from `output.extra[TASK_ROW]`,
/// not a fresh post-commit SELECT. The returned row is the pre-stamp
/// version pinned to `output.after` — semantically tied to the
/// mutation we just applied — so its `body` reflects the write and
/// it round-trips through `TaskRow`'s new `Deserialize` derive (which
/// exercises the flattened sub-structs and the `DueAt` `deserialize_with`
/// adapter).
///
/// Note: the post-commit DB row carries a STAMPED version (one HLC
/// tick newer than the returned row) because the surrounding
/// `enqueue_entity_upsert` runs `version_stamp::stamp_entity_version`
/// inside the same transaction. Returning the pre-stamp row is
/// intentional — it matches `output.after` and is what the audit log
/// records.
#[test]
fn append_to_task_body_returns_in_tx_row_via_extra() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, T_3493_1, "Write report");
    let returned =
        append_to_task_body_with_conn(&mut conn, &tid(T_3493_1), "Note A").expect("append");

    // The returned row reflects the write semantically.
    assert_eq!(returned.core().id(), T_3493_1);
    assert_eq!(returned.core().body(), Some("Note A"));

    // Round-trip the returned row through serde_json to prove the new
    // `Deserialize` derive on `TaskRow` (and the `DueAt`
    // `deserialize_with` adapter on `TaskScheduling`) parses the same
    // wire shape that `Serialize` emits, byte-identically.
    let serialized = serde_json::to_value(&returned).expect("serialize returned row");
    let round_trip: lorvex_store::repositories::task::read::TaskRow =
        serde_json::from_value(serialized.clone()).expect("TaskRow Deserialize round-trip");
    let reserialized = serde_json::to_value(&round_trip).expect("re-serialize");
    assert_eq!(
        serialized, reserialized,
        "TaskRow JSON must be byte-stable across Serialize/Deserialize"
    );

    // The DB row's content fields (everything except the post-stamp
    // `version`) must agree with the returned row — confirming the
    // returned row is the canonical post-mutation snapshot, not a
    // stale or peer-shadowed read.
    let from_db = lorvex_store::repositories::task::read::get_task(&conn, &tid(T_3493_1))
        .expect("re-load")
        .expect("task exists");
    assert_eq!(returned.core().body(), from_db.core().body());
    assert_eq!(returned.core().title(), from_db.core().title());
    assert_eq!(returned.core().updated_at(), from_db.core().updated_at());
}

#[test]
fn recurrence_exception_rejects_bad_date_shape() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open in-memory db");
    seed_recurring_task(&conn, T_REX_2);
    let err = add_task_recurrence_exception_with_conn(&mut conn, &tid(T_REX_2), "not-a-date")
        .expect_err("bad date");
    assert!(matches!(err, CliError::Validation(_)));
}
