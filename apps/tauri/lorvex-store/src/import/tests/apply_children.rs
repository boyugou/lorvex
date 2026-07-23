use super::*;

#[test]
fn import_rejects_blank_child_version() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("blank-child-version.zip");

    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "reminder-1",
            "version": "",
            "payload": {
                "id": "reminder-1",
                "task_id": "task-1",
                "reminder_at": "2026-03-29T09:00:00Z",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z",
            }
        })],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("children.jsonl"));
            assert!(message.contains("non-empty version"));
        }
        other => panic!("expected InvalidPayload for blank child version, got {other:?}"),
    }
}

#[test]
fn import_rejects_child_with_non_hlc_version() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-child-version.zip");

    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "reminder-1",
            "version": "not-an-hlc",
            "payload": {
                "id": "reminder-1",
                "task_id": "task-1",
                "reminder_at": "2026-03-29T09:00:00Z",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z",
            }
        })],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("children.jsonl"));
            assert!(message.contains("valid HLC version"));
        }
        other => panic!("expected InvalidPayload for bad child version, got {other:?}"),
    }
}

#[test]
fn import_rejects_memory_revision_missing_actor() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_MEMORY_REVISION,
            "entity_id": "mem-rev-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "mem-rev-1",
                "memory_key": "behavioral_patterns",
                "content": "pattern",
                "operation": "upsert",
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("actor"),
        "expected actor error, got: {err}"
    );
}

#[test]
fn import_rejects_memory_revision_non_string_source_revision_id_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_MEMORY_REVISION,
            "entity_id": "mem-rev-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "mem-rev-1",
                "memory_key": "behavioral_patterns",
                "content": "pattern",
                "operation": "upsert",
                "source_revision_id": 7,
                "actor": "ai",
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("source_revision_id"),
        "expected source_revision_id error, got: {err}"
    );
}

#[test]
fn import_rejects_memory_revision_missing_operation() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_MEMORY_REVISION,
            "entity_id": "mem-rev-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "mem-rev-1",
                "memory_key": "notes_for_ai",
                "actor": "human",
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("operation"),
        "expected operation error, got: {err}"
    );
}

#[test]
fn import_rejects_task_reminder_missing_created_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Test List",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Task",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-03-29T09:00:00Z"
            }
        })],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_task_reminder_non_string_dismissed_at_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Test List",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Task",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-03-29T09:00:00Z",
                "dismissed_at": 123,
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("dismissed_at"),
        "expected dismissed_at error, got: {err}"
    );
}

#[test]
fn import_task_reminder_with_offset_persists_canonical_utc_timestamp() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Test List",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Task",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-12-01T09:00:00-05:00",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "2026-12-01T14:00:00.000Z");
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

#[test]
fn import_task_reminder_time_update_clears_delivery_state() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-1', 'Test List', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, defer_count, created_at, updated_at, version)
         VALUES ('task-1', 'Task', 'open', 'list-1', 0, '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('rem-1', 'task-1', '2026-12-01T14:00:00.000Z', '1711234567890_0000_deadbeefdeadbeef', '2026-03-29T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at)
         VALUES ('rem-1', 'delivered', '2026-12-01T14:01:00.000Z')",
        [],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-12-02T09:00:00-05:00",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "2026-12-02T14:00:00.000Z");
    let delivery_state_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(delivery_state_count, 0);

    let due = lorvex_store::repositories::task::reminders::get_due_task_reminders(
        &conn,
        "2026-12-03T00:00:00.000Z",
        10,
    )
    .expect("updated reminder should be readable by due-reminder query");
    assert_eq!(due.rows.len(), 1);
    assert_eq!(due.rows[0].id, "rem-1");
}

#[test]
fn import_task_reminder_format_only_update_preserves_delivery_state() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-1', 'Test List', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, defer_count, created_at, updated_at, version)
         VALUES ('task-1', 'Task', 'open', 'list-1', 0, '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('rem-1', 'task-1', '2026-12-01T14:00:00Z', '1711234567890_0000_deadbeefdeadbeef', '2026-03-29T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at)
         VALUES ('rem-1', 'delivered', '2026-12-01T14:01:00.000Z')",
        [],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-12-01T14:00:00.000Z",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "2026-12-01T14:00:00.000Z");
    let delivery_state_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(delivery_state_count, 1);
}

#[test]
fn import_task_reminder_skipped_stale_update_preserves_delivery_state() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-1', 'Test List', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, defer_count, created_at, updated_at, version)
         VALUES ('task-1', 'Task', 'open', 'list-1', 0, '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', '1711234567890_0000_deadbeefdeadbeef')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('rem-1', 'task-1', '2026-12-01T14:00:00.000Z', '1711234567890_0002_deadbeefdeadbeef', '2026-03-29T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at)
         VALUES ('rem-1', 'delivered', '2026-12-01T14:01:00.000Z')",
        [],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_REMINDER,
            "entity_id": "rem-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "rem-1",
                "task_id": "task-1",
                "reminder_at": "2026-12-02T14:00:00.000Z",
                "dismissed_at": null,
                "cancelled_at": null,
                "created_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();

    let (stored_at, stored_version): (String, String) = conn
        .query_row(
            "SELECT reminder_at, version FROM task_reminders WHERE id = 'rem-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(stored_at, "2026-12-01T14:00:00.000Z");
    assert_eq!(stored_version, "1711234567890_0002_deadbeefdeadbeef");
    let delivery_state_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = 'rem-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(delivery_state_count, 1);
}

#[test]
fn import_rejects_habit_reminder_policy_missing_reminder_time() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT,
            "entity_id": "habit-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-1",
                "name": "Walk",
                "frequency_type": "daily",
                "target_count": 1,
                "archived": false,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT_REMINDER_POLICY,
            "entity_id": "habit-pol-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-pol-1",
                "habit_id": "habit-1",
                "enabled": true,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("reminder_time"),
        "expected reminder_time error, got: {err}"
    );
}
