use super::*;
use crate::test_db;

/// HLC versions used across tests. Lexicographic ordering matches temporal ordering.
const V_OLD: &str = "1711234567000_0000_dec0000100000001";
const V_MID: &str = "1711234568000_0000_dec0000100000001";
const V_NEW: &str = "1711234569000_0000_dec0000100000001";

const ZERO_VERSION: &str = "0000000000000_0000_0000000000000000";
/// Insert a minimal task row so FK constraints on task_reminders are satisfied.
fn insert_task(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
             VALUES (?1, 'T', 'open', ?2, '', '')",
        params![id, ZERO_VERSION],
    )
    .unwrap();
}

fn task_reminder_payload(task_id: &str, reminder_at: &str) -> String {
    serde_json::json!({
        "task_id": task_id,
        "reminder_at": reminder_at,
        "dismissed_at": null,
        "cancelled_at": null,
        "created_at": "2026-01-01T00:00:00Z",
    })
    .to_string()
}

fn count_task_reminders(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM task_reminders", [], |r| r.get(0))
        .unwrap()
}

fn get_reminder_at(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT reminder_at FROM task_reminders WHERE id = ?1",
        [id],
        |r| r.get(0),
    )
    .ok()
}

fn get_reminder_version(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT version FROM task_reminders WHERE id = ?1",
        [id],
        |r| r.get(0),
    )
    .ok()
}

// -----------------------------------------------------------------------
// apply_task_reminder_upsert: insert
// -----------------------------------------------------------------------

#[test]
fn task_reminder_upsert_inserts_new_reminder() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    let payload = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &payload, V_MID, false.into(), "").unwrap();

    assert_eq!(count_task_reminders(&conn), 1);
    assert_eq!(
        get_reminder_at(&conn, "rem-001").unwrap(),
        "2026-03-15T09:00:00.000Z"
    );
}

#[test]
fn task_reminder_upsert_with_offset_persists_canonical_utc_timestamp() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    let payload = task_reminder_payload("task-1", "2026-12-01T09:00:00-05:00");
    apply_task_reminder_upsert(&conn, "rem-001", &payload, V_MID, false.into(), "").unwrap();

    assert_eq!(
        get_reminder_at(&conn, "rem-001").unwrap(),
        "2026-12-01T14:00:00.000Z"
    );
    let due = lorvex_store::repositories::task::reminders::get_due_task_reminders(
        &conn,
        "2026-12-02T00:00:00.000Z",
        10,
    )
    .expect("canonical reminder should be readable by due-reminder query");
    assert_eq!(due.rows.len(), 1);
    assert_eq!(
        due.rows[0].reminder_at.as_string(),
        "2026-12-01T14:00:00.000Z"
    );
}

// -----------------------------------------------------------------------
// apply_task_reminder_upsert: LWW — newer version updates
// -----------------------------------------------------------------------

#[test]
fn task_reminder_upsert_updates_when_version_is_newer() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    let p1 = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p1, V_OLD, false.into(), "").unwrap();

    let p2 = task_reminder_payload("task-1", "2026-03-16T10:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p2, V_NEW, false.into(), "").unwrap();

    assert_eq!(count_task_reminders(&conn), 1);
    assert_eq!(
        get_reminder_at(&conn, "rem-001").unwrap(),
        "2026-03-16T10:00:00.000Z"
    );
    assert_eq!(get_reminder_version(&conn, "rem-001").unwrap(), V_NEW);
}

// -----------------------------------------------------------------------
// apply_task_reminder_upsert: delivery_state reset on reminder_at edit
// -----------------------------------------------------------------------

fn count_delivery_state(conn: &Connection, reminder_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = ?1",
        [reminder_id],
        |r| r.get(0),
    )
    .unwrap()
}

fn insert_delivered_state(conn: &Connection, reminder_id: &str) {
    conn.execute(
            "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, last_fired_at, last_notified_at, updated_at) \
             VALUES (?1, 'delivered', '2026-03-15T09:01:00Z', '2026-03-15T09:01:00Z', '2026-03-15T09:01:00Z')",
            params![reminder_id],
        )
        .unwrap();
}

#[test]
fn task_reminder_upsert_clears_delivery_state_when_time_changes() {
    // Simulate a remote device editing a reminder's reminder_at. The
    // local device already delivered the original firing. After the
    // UPSERT, the delivery_state row must be cleared so the new
    // reminder_at can re-fire.
    let conn = test_db();
    insert_task(&conn, "task-1");

    let p1 = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p1, V_OLD, false.into(), "").unwrap();
    insert_delivered_state(&conn, "rem-001");
    assert_eq!(count_delivery_state(&conn, "rem-001"), 1);

    // Remote edits the time to a later value.
    let p2 = task_reminder_payload("task-1", "2026-04-01T10:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p2, V_NEW, false.into(), "").unwrap();

    assert_eq!(
        get_reminder_at(&conn, "rem-001").unwrap(),
        "2026-04-01T10:00:00.000Z"
    );
    assert_eq!(
        count_delivery_state(&conn, "rem-001"),
        0,
        "delivery_state row must be cleared when reminder_at is edited"
    );
}

#[test]
fn task_reminder_upsert_preserves_delivery_state_when_time_unchanged() {
    // If an upsert arrives with the same reminder_at, the delivery_state
    // must NOT be cleared — that would mean a fresh envelope re-firing a
    // reminder the user already dismissed.
    let conn = test_db();
    insert_task(&conn, "task-1");

    let p1 = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p1, V_OLD, false.into(), "").unwrap();
    insert_delivered_state(&conn, "rem-001");

    // Same reminder_at, newer version (e.g. metadata refresh).
    let p2 = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p2, V_NEW, false.into(), "").unwrap();

    assert_eq!(
        count_delivery_state(&conn, "rem-001"),
        1,
        "delivery_state must be preserved when reminder_at is unchanged"
    );
}

#[test]
fn task_reminder_upsert_preserves_delivery_state_on_format_only_canonicalization() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('rem-legacy-format', 'task-1', '2026-03-15T09:00:00Z', ?1, '2026-01-01T00:00:00Z')",
        params![V_OLD],
    )
    .unwrap();
    insert_delivered_state(&conn, "rem-legacy-format");

    let payload = task_reminder_payload("task-1", "2026-03-15T09:00:00.000Z");
    apply_task_reminder_upsert(
        &conn,
        "rem-legacy-format",
        &payload,
        V_NEW,
        false.into(),
        "",
    )
    .unwrap();

    assert_eq!(
        get_reminder_at(&conn, "rem-legacy-format").unwrap(),
        "2026-03-15T09:00:00.000Z"
    );
    assert_eq!(
        count_delivery_state(&conn, "rem-legacy-format"),
        1,
        "format-only canonicalization must not re-fire a delivered reminder"
    );
}

#[test]
fn task_reminder_upsert_fresh_insert_leaves_delivery_state_absent() {
    // Fresh insert: no delivery_state row to clear.
    let conn = test_db();
    insert_task(&conn, "task-1");

    let p = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &p, V_MID, false.into(), "").unwrap();

    assert_eq!(count_delivery_state(&conn, "rem-001"), 0);
}

// -----------------------------------------------------------------------
// apply_task_reminder_delete
// -----------------------------------------------------------------------

#[test]
fn task_reminder_delete_removes_reminder() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    let payload = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    apply_task_reminder_upsert(&conn, "rem-001", &payload, V_MID, false.into(), "").unwrap();
    assert_eq!(count_task_reminders(&conn), 1);

    // child deletes now carry the envelope's
    // version so the in-row LWW gate can refuse stale-replays.
    // Pass V_NEW (strictly greater than the V_MID seed) so the
    // gate accepts the delete.
    apply_task_reminder_delete(&conn, "rem-001", V_NEW, "").unwrap();
    assert_eq!(count_task_reminders(&conn), 0);
}

/// a stale-HLC delete envelope must
/// be refused by the in-row LWW guard. The defense-in-depth
/// gate makes the handler safe under shadow-promotion replay
/// and any future replay path that hasn't already gated upstream.
#[test]
fn task_reminder_stale_delete_is_refused_by_in_row_lww_guard() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    let payload = task_reminder_payload("task-1", "2026-03-15T09:00:00Z");
    // Seed at the highest HLC.
    apply_task_reminder_upsert(&conn, "rem-stay", &payload, V_NEW, false.into(), "").unwrap();
    assert_eq!(count_task_reminders(&conn), 1);

    // Stale delete at V_OLD must NOT remove the row. Pre-fix,
    // the bare `DELETE FROM task_reminders WHERE id = ?1`
    // happily removed it.
    apply_task_reminder_delete(&conn, "rem-stay", V_OLD, "").unwrap();
    assert_eq!(
        count_task_reminders(&conn),
        1,
        "stale delete (V_OLD) MUST NOT remove a child row at V_NEW; \
             M1 in-row LWW guard regressed",
    );
}

// -----------------------------------------------------------------------
