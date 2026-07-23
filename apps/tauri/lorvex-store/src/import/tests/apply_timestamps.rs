use super::*;

#[test]
fn import_normalizes_entity_sync_timestamps_before_persisting() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");

    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-ts",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "list-ts",
                    "name": "Inbox",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00.123456Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-ts",
                "version": "1711234567890_0002_deadbeefdeadbeef",
                "payload": {
                    "id": "task-ts",
                    "title": "Timestamp task",
                    "status": "open",
                    "list_id": "list-ts",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00.123456Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_CALENDAR_EVENT,
                "entity_id": "evt-ts",
                "version": "1711234567890_0003_deadbeefdeadbeef",
                "payload": {
                    "id": "evt-ts",
                    "title": "Event",
                    "start_date": "2026-03-29",
                    "all_day": false,
                    "event_type": "event",
                    "created_at": "2026-03-29T01:02:03Z",
                    "updated_at": "2026-03-29T01:02:03.987654Z"
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let (task_created_at, task_updated_at): (String, String) = conn
        .query_row(
            "SELECT created_at, updated_at FROM tasks WHERE id = 'task-ts'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(task_created_at, "2026-03-29T00:00:00.000Z");
    assert_eq!(task_updated_at, "2026-03-29T00:00:00.123Z");

    let (event_created_at, event_updated_at): (String, String) = conn
        .query_row(
            "SELECT created_at, updated_at FROM calendar_events WHERE id = 'evt-ts'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(event_created_at, "2026-03-29T01:02:03.000Z");
    assert_eq!(event_updated_at, "2026-03-29T01:02:03.987Z");
}

#[test]
fn import_provider_link_lww_compares_normalized_timestamps() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");

    write_import_zip_with_provider_links(
        &zip_path,
        &[serde_json::json!({
            "entity_type": EDGE_TASK_PROVIDER_EVENT_LINK,
            "payload": {
                "task_id": "task-provider-ts",
                "provider_kind": "google_calendar",
                "provider_scope": "primary",
                "provider_event_key": "evt-provider-ts",
                "created_at": "2026-03-20T15:30:00.001000Z",
                "updated_at": "2026-03-20T15:30:00.001Z"
            }
        })],
    );

    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-provider-ts', 'Provider List', '2026-03-20T15:00:00Z',
                 '2026-03-20T15:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
         VALUES ('task-provider-ts', 'Provider task', 'open', 'list-provider-ts',
                 '2026-03-20T15:00:00Z', '2026-03-20T15:00:00Z',
                 '1711234567890_0002_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_provider_event_links
            (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
         VALUES ('task-provider-ts', 'google_calendar', 'primary', 'evt-provider-ts',
                 '2026-03-20T15:00:00Z', '2026-03-20T15:30:00Z')",
        [],
    )
    .unwrap();

    import_from_zip(&conn, &zip_path).unwrap();

    let (created_at, updated_at): (String, String) = conn
        .query_row(
            "SELECT created_at, updated_at
             FROM task_provider_event_links
             WHERE task_id = 'task-provider-ts'
               AND provider_kind = 'google_calendar'
               AND provider_scope = 'primary'
               AND provider_event_key = 'evt-provider-ts'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(created_at, "2026-03-20T15:30:00.001Z");
    assert_eq!(updated_at, "2026-03-20T15:30:00.001Z");
}
