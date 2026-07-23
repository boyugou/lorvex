use super::*;

// Issue #3285: tests bypass the trust-boundary parser via
// `from_trusted` because the seeded FK rows use short labels
// (`t1`, `e1`, …) rather than UUIDs.
fn task(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}
fn event(id: &str) -> EventId {
    EventId::from_trusted(id.to_string())
}

/// Seeded test connection: opens via the canonical
/// `crate::test_support::test_conn` helper and
/// then inserts the FK-satisfying parent rows this module's tests
/// rely on. The seeding step is unique to these link-table tests,
/// so the wrapper stays local.
fn test_conn() -> Connection {
    let conn = crate::test_support::test_conn();

    // Seed a task and calendar events so FK constraints are satisfied.
    conn.execute_batch(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at)
         VALUES ('t1', 'Test task', 'open', '0000000000000_0000_0000000000000000', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');
         INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES ('e1', 'Test event', '2025-01-15', 1, '0000000000000_0000_0000000000000000', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');
         INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES ('e2', 'Another event', '2025-02-01', 1, '0000000000000_0000_0000000000000000', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');",
    )
    .expect("seed data");
    conn
}

#[test]
fn insert_and_read_link() {
    let conn = test_conn();
    let (link, applied) = insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();
    assert!(applied);
    assert_eq!(link.task_id, "t1");
    assert_eq!(link.calendar_event_id, "e1");
    assert_eq!(link.created_at.as_string(), "2025-01-10T00:00:00.000Z");

    let links = get_links_for_task(&conn, &task("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].calendar_event_id, "e1");
}

#[test]
fn get_links_for_event_returns_matching() {
    let conn = test_conn();
    insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();

    let links = get_links_for_event(&conn, &event("e1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].task_id, "t1");

    let empty = get_links_for_event(&conn, &event("e2")).unwrap();
    assert!(empty.is_empty());
}

#[test]
fn insert_upsert_updates_timestamp() {
    let conn = test_conn();
    let (link1, applied1) = insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();
    assert!(applied1);
    assert_eq!(link1.updated_at.as_string(), "2025-01-10T00:00:00.000Z");

    let (link2, applied2) = insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v2",
        "2025-01-11T00:00:00Z",
    )
    .unwrap();
    assert!(applied2);
    assert_eq!(link2.updated_at.as_string(), "2025-01-11T00:00:00.000Z");
    // created_at should remain the original
    assert_eq!(link2.created_at.as_string(), "2025-01-10T00:00:00.000Z");

    // Still only one link
    let links = get_links_for_task(&conn, &task("t1")).unwrap();
    assert_eq!(links.len(), 1);
}

#[test]
fn delete_link_returns_one_when_exists() {
    let conn = test_conn();
    insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();

    let deleted = delete_link(&conn, &task("t1"), &event("e1")).unwrap();
    assert_eq!(deleted, 1);

    let links = get_links_for_task(&conn, &task("t1")).unwrap();
    assert!(links.is_empty());
}

#[test]
fn delete_link_returns_zero_when_missing() {
    let conn = test_conn();
    let deleted = delete_link(&conn, &task("t1"), &event("e1")).unwrap();
    assert_eq!(deleted, 0);
}

#[test]
fn multiple_links_for_task() {
    let conn = test_conn();
    insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();
    insert_link(
        &conn,
        &task("t1"),
        &event("e2"),
        "v2",
        "2025-01-11T00:00:00Z",
    )
    .unwrap();

    let links = get_links_for_task(&conn, &task("t1")).unwrap();
    assert_eq!(links.len(), 2);
}

/// a stale local stamp racing an
/// in-flight peer write must lose the LWW race. Pre-fix the
/// upsert blindly overwrote the row's version even when
/// `excluded.version <= task_calendar_event_links.version`,
/// silently regressing the cluster's HLC.
#[test]
fn insert_link_lww_gate_rejects_stale_version() {
    let conn = test_conn();

    // First write wins: peer-equivalent baseline at v2.
    let (link1, applied1) = insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v2",
        "2025-01-10T00:00:00Z",
    )
    .unwrap();
    assert!(applied1, "initial insert must apply");
    assert_eq!(link1.updated_at.as_string(), "2025-01-10T00:00:00.000Z");

    // Stale write at v1 must NOT regress version or updated_at.
    let (link2, applied2) = insert_link(
        &conn,
        &task("t1"),
        &event("e1"),
        "v1",
        "2025-01-11T00:00:00Z",
    )
    .unwrap();
    assert!(!applied2, "stale stamp under LWW gate must be a no-op");
    // Re-loaded row reflects the still-canonical state.
    assert_eq!(link2.updated_at.as_string(), "2025-01-10T00:00:00.000Z");

    // Direct version probe: the column must be untouched.
    let version: String = conn
        .query_row(
            "SELECT version FROM task_calendar_event_links \
             WHERE task_id = 't1' AND calendar_event_id = 'e1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(version, "v2", "stale stamp must not regress version");
}
