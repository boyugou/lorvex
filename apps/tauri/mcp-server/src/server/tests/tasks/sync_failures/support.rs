pub(super) use super::super::*;
pub(super) use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS,
    ENTITY_FOCUS_SCHEDULE, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
pub(super) use serde_json::Value;

/// #2182: tool-boundary errors are now structured JSON payloads. These
/// rollback tests only care that *some* error surfaced (the detail
/// varies across rusqlite versions and CI environments), so we assert
/// the JSON envelope shape without pinning the message.
pub(super) fn assert_is_tool_error(raw: &str) {
    let _: Value = serde_json::from_str(raw)
        .unwrap_or_else(|e| panic!("expected JSON error payload, got {raw:?}: {e}"));
}

/// `permanent_delete_task` now requires `archived_at IS
/// NOT NULL` so the MCP tool cannot bypass Trash. Tests that want to
/// exercise the hard-delete cleanup path must archive first.
pub(super) fn archive_task_for_test(server: &LorvexMcpServer, id: &str) {
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET archived_at = '2026-04-02T00:00:00Z' WHERE id = ?",
                [id],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("archive task for test");
}

pub(super) fn install_sync_outbox_entity_failure_trigger(
    server: &LorvexMcpServer,
    trigger_name: &str,
    entity_type: &str,
) {
    server
        .with_conn(|conn| {
            let escaped_entity_type = entity_type.replace('\'', "''");
            conn.execute(
                &format!(
                    "CREATE TEMP TRIGGER {trigger_name}
                     BEFORE INSERT ON sync_outbox
                     WHEN NEW.entity_type = '{escaped_entity_type}'
                     BEGIN
                       SELECT RAISE(FAIL, 'forced relation sync failure');
                     END"
                ),
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("install sync_outbox entity failure trigger");
}

pub(super) fn install_spawned_successor_delete_trigger(
    server: &LorvexMcpServer,
    trigger_name: &str,
) {
    server
        .with_conn(|conn| {
            conn.execute(
                &format!(
                    "CREATE TEMP TRIGGER {trigger_name}
                     AFTER INSERT ON tasks
                     WHEN NEW.spawned_from IS NOT NULL
                     BEGIN
                       DELETE FROM tasks WHERE id = NEW.id;
                     END"
                ),
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("install spawned successor delete trigger");
}

pub(super) fn install_delete_failure_trigger(
    server: &LorvexMcpServer,
    trigger_name: &str,
    table: &str,
) {
    server
        .with_conn(|conn| {
            conn.execute(
                &format!(
                    "CREATE TEMP TRIGGER {trigger_name}
                     BEFORE DELETE ON {table}
                     BEGIN
                       SELECT RAISE(FAIL, 'forced cleanup failure');
                     END"
                ),
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("install delete failure trigger");
}

pub(super) fn insert_task_reminder(
    server: &LorvexMcpServer,
    reminder_id: &str,
    task_id: &str,
    reminder_at: &str,
) {
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) VALUES (?1, ?2, ?3, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
                (reminder_id, task_id, reminder_at),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("insert task reminder");
}

pub(super) fn insert_task_dependency(
    server: &LorvexMcpServer,
    task_id: &str,
    depends_on_task_id: &str,
) {
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
                (task_id, depends_on_task_id),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("insert dependency edge");
}

pub(super) fn task_status(server: &LorvexMcpServer, task_id: &str) -> String {
    server
        .with_conn(|conn| {
            conn.query_row("SELECT status FROM tasks WHERE id = ?1", [task_id], |row| {
                row.get::<_, String>(0)
            })
            .map_err(to_error_message)
        })
        .expect("load task status")
}

pub(super) fn reminder_cancelled_at(server: &LorvexMcpServer, reminder_id: &str) -> Option<String> {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
                [reminder_id],
                |row| row.get::<_, Option<String>>(0),
            )
            .map_err(to_error_message)
        })
        .expect("load reminder cancelled_at")
}

pub(super) fn task_count(server: &LorvexMcpServer) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get::<_, i64>(0))
                .map_err(to_error_message)
        })
        .expect("count tasks")
}

pub(super) fn task_exists(server: &LorvexMcpServer, task_id: &str) -> bool {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM tasks WHERE id = ?1)",
                [task_id],
                |row| row.get::<_, i64>(0),
            )
            .map(|exists| exists != 0)
            .map_err(to_error_message)
        })
        .expect("check task existence")
}

pub(super) fn reminder_count(server: &LorvexMcpServer) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM task_reminders", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(to_error_message)
        })
        .expect("count reminders")
}

pub(super) fn dependency_count_for_task(server: &LorvexMcpServer, task_id: &str) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?1",
                [task_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count dependencies for task")
}

pub(super) fn seed_current_focus_item(server: &LorvexMcpServer, date: &str, task_id: &str) {
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?1, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
                [date],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, ?2)",
                (date, task_id),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed current focus item");
}

pub(super) fn current_focus_item_count(server: &LorvexMcpServer, task_id: &str) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?1",
                [task_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count current focus items")
}

pub(super) fn seed_focus_schedule_block(server: &LorvexMcpServer, date: &str, task_id: &str) {
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO focus_schedule (date, version, created_at, updated_at) VALUES (?1, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
                [date],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id)
                 VALUES (?1, 0, 'task', 540, 600, ?2)",
                (date, task_id),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed focus schedule block");
}

pub(super) fn focus_schedule_block_count(server: &LorvexMcpServer, task_id: &str) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?1",
                [task_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count focus schedule blocks")
}

pub(super) fn count_outbox_entries(
    server: &LorvexMcpServer,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                (entity_type, entity_id, operation),
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count sync_outbox entries")
}

pub(super) fn count_tombstones(
    server: &LorvexMcpServer,
    entity_type: &str,
    entity_id: &str,
) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_tombstones
                 WHERE entity_type = ?1 AND entity_id = ?2",
                (entity_type, entity_id),
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count tombstones")
}

pub(super) fn complete_recurring_parent_and_get_successor(
    server: &LorvexMcpServer,
    parent_id: &str,
) -> String {
    let response = server
        .complete_task(Parameters(CompleteTaskArgs {
            id: parent_id.to_string(),
            idempotency_key: None,
        }))
        .expect("complete recurring parent");
    let payload: Value = serde_json::from_str(&response).expect("parse completion response");
    payload["next_occurrence"]["id"]
        .as_str()
        .expect("spawned successor id")
        .to_string()
}
