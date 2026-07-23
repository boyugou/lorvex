use super::checklist::materialize_task_checklist_items;
use crate::open_db_in_memory;
use lorvex_domain::TaskId;
use rusqlite::Connection;

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

fn seed_task(conn: &Connection, id: &str, version: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-1', 'Inbox', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z',
                 '1700000000000_0001_aaaaaaaaaaaaaaaa')
         ON CONFLICT(id) DO NOTHING",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
         VALUES (?1, 'Test', 'open', 'list-1', ?2,
                 '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [id, version],
    )
    .unwrap();
}

fn checklist_version(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT version FROM task_checklist_items WHERE id = ?1",
        [id],
        |row| row.get(0),
    )
    .ok()
}

fn checklist_text(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT text FROM task_checklist_items WHERE id = ?1",
        [id],
        |row| row.get(0),
    )
    .ok()
}

/// a stale aggregate-task envelope must
/// not clobber a newer per-item envelope that already landed
/// locally. Pre-fix, `materialize_task_checklist_items` did
/// `DELETE … WHERE task_id = ?` then re-inserted from the
/// embedded array, silently losing the newer local edit.
#[test]
fn materialize_preserves_newer_local_checklist_item() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1", "1700000000000_0001_aaaaaaaaaaaaaaaa");

    // Newer per-item envelope already landed locally.
    let newer_local = "1800000000000_0001_aaaaaaaaaaaaaaaa";
    conn.execute(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (
            'task-1:checklist:0', 'task-1', 0, 'NEW LOCAL TEXT', NULL, ?1,
            '2026-04-15T00:00:00Z', '2026-04-15T00:00:00Z'
         )",
        [newer_local],
    )
    .unwrap();

    // Now an older aggregate-task envelope arrives carrying the
    // pre-edit text. The materializer must NOT overwrite the row.
    let older_task_version = "1700000000000_0002_aaaaaaaaaaaaaaaa";
    let payload = serde_json::json!({
        "id": "task-1",
        "checklist_items": [{
            "id": "task-1:checklist:0",
            "position": 0,
            "text": "OLD TEXT",
            "completed_at": null,
            "version": "1700000000000_0002_aaaaaaaaaaaaaaaa",
            "created_at": "2026-04-01T00:00:00Z",
            "updated_at": "2026-04-01T00:00:00Z",
        }]
    });
    materialize_task_checklist_items(
        &conn,
        &tid("task-1"),
        &payload,
        None,
        older_task_version,
        "2026-04-01T00:00:00Z",
        "2026-04-01T00:00:00Z",
    )
    .unwrap();

    assert_eq!(
        checklist_text(&conn, "task-1:checklist:0").as_deref(),
        Some("NEW LOCAL TEXT"),
        "newer per-item version must survive a stale aggregate envelope"
    );
    assert_eq!(
        checklist_version(&conn, "task-1:checklist:0").as_deref(),
        Some(newer_local)
    );
}

/// a newer aggregate-task envelope
/// containing a per-item update must apply normally — the LWW
/// gate is per-row, not per-aggregate, so when the embedded item's
/// version exceeds the local version the materializer must replace.
#[test]
fn materialize_applies_newer_embedded_checklist_item() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-2", "1700000000000_0001_aaaaaaaaaaaaaaaa");

    let older_local = "1700000000000_0001_aaaaaaaaaaaaaaaa";
    conn.execute(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (
            'task-2:checklist:0', 'task-2', 0, 'OLD LOCAL', NULL, ?1,
            '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
         )",
        [older_local],
    )
    .unwrap();

    let newer_task_version = "1900000000000_0001_aaaaaaaaaaaaaaaa";
    let payload = serde_json::json!({
        "id": "task-2",
        "checklist_items": [{
            "id": "task-2:checklist:0",
            "position": 0,
            "text": "REMOTE-EDITED",
            "completed_at": null,
            "version": "1900000000000_0001_aaaaaaaaaaaaaaaa",
            "created_at": "2026-04-01T00:00:00Z",
            "updated_at": "2026-05-01T00:00:00Z",
        }]
    });
    materialize_task_checklist_items(
        &conn,
        &tid("task-2"),
        &payload,
        None,
        newer_task_version,
        "2026-04-01T00:00:00Z",
        "2026-05-01T00:00:00Z",
    )
    .unwrap();

    assert_eq!(
        checklist_text(&conn, "task-2:checklist:0").as_deref(),
        Some("REMOTE-EDITED"),
    );
}

/// rows the embedded payload no longer
/// references are deleted only when their local version is `<=` the
/// parent task's version envelope. A locally-authored per-item
/// envelope newer than the parent envelope must survive.
#[test]
fn materialize_does_not_delete_newer_unreferenced_local_item() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-3", "1700000000000_0001_aaaaaaaaaaaaaaaa");

    // Older row that the embedded payload also drops.
    let older_local = "1700000000000_0001_aaaaaaaaaaaaaaaa";
    conn.execute(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (
            'task-3:checklist:0', 'task-3', 0, 'OLDER', NULL, ?1,
            '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'
         )",
        [older_local],
    )
    .unwrap();

    // Locally-newer per-item envelope (version > parent task version)
    // that the aggregate envelope hasn't observed yet.
    let newer_local = "1900000000000_0001_aaaaaaaaaaaaaaaa";
    conn.execute(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (
            'task-3:checklist:1', 'task-3', 1, 'LOCAL ONLY', NULL, ?1,
            '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z'
         )",
        [newer_local],
    )
    .unwrap();

    // Embedded payload references neither — drop both, allegedly.
    let task_version = "1800000000000_0001_aaaaaaaaaaaaaaaa";
    let payload = serde_json::json!({
        "id": "task-3",
        "checklist_items": []
    });
    materialize_task_checklist_items(
        &conn,
        &tid("task-3"),
        &payload,
        None,
        task_version,
        "2026-04-01T00:00:00Z",
        "2026-04-01T00:00:00Z",
    )
    .unwrap();

    // Older row deleted (its version <= task envelope).
    assert!(
        checklist_version(&conn, "task-3:checklist:0").is_none(),
        "older unreferenced row should be deleted"
    );
    // Newer-than-parent row preserved.
    assert_eq!(
        checklist_version(&conn, "task-3:checklist:1").as_deref(),
        Some(newer_local),
        "newer-than-parent unreferenced row must survive"
    );
}
