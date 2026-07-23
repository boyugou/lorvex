use lorvex_domain::naming::{EDGE_TASK_CALENDAR_EVENT_LINK, OP_UPSERT};
use lorvex_domain::{EventId, TaskId};
use lorvex_store::repositories::task::calendar_links;
use rusqlite::params;

use crate::commands::enqueue_to_outbox_typed;
use crate::commands::{sync_timestamp_now, with_immediate_transaction};
use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;

pub use calendar_links::TaskCalendarEventLink;

fn ensure_task_exists(conn: &rusqlite::Connection, task_id: &TaskId) -> AppResult<()> {
    let task_exists: bool = conn
        .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1")
        .and_then(|mut stmt| stmt.exists(params![task_id.as_str()]))
        .map_err(AppError::from)?;
    if !task_exists {
        return Err(AppError::NotFound(format!("Task not found: {task_id}")));
    }
    Ok(())
}

fn ensure_live_task_exists(conn: &rusqlite::Connection, task_id: &TaskId) -> AppResult<()> {
    if !lorvex_store::task_exists_active(conn, task_id).map_err(AppError::from)? {
        return Err(AppError::NotFound(format!("Task not found: {task_id}")));
    }
    Ok(())
}

fn ensure_calendar_event_exists(conn: &rusqlite::Connection, event_id: &EventId) -> AppResult<()> {
    let event_exists: bool = conn
        .prepare_cached("SELECT 1 FROM calendar_events WHERE id = ?1")
        .and_then(|mut stmt| stmt.exists(params![event_id.as_str()]))
        .map_err(AppError::from)?;
    if !event_exists {
        return Err(AppError::NotFound(format!(
            "Calendar event not found: {event_id}"
        )));
    }
    Ok(())
}

fn link_task_to_event_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    event_id: &EventId,
    now: &str,
) -> AppResult<TaskCalendarEventLink> {
    ensure_live_task_exists(conn, task_id)?;
    ensure_calendar_event_exists(conn, event_id)?;

    let version = crate::hlc::generate_version_result()?;
    // `insert_link` now reports whether the LWW gate
    // accepted the upsert. Local writes always mint a fresh HLC, so the
    // gate accepts in the common path; the `_applied` slot is reserved
    // for a future caller that wants to short-circuit on no-op.
    let (link, _applied) = calendar_links::insert_link(conn, task_id, event_id, &version, now)
        .map_err(AppError::from)?;

    let entity_id = format!("{task_id}:{event_id}");
    let payload = serde_json::to_value(&link).map_err(AppError::from)?;
    enqueue_to_outbox_typed(
        conn,
        EDGE_TASK_CALENDAR_EVENT_LINK,
        &entity_id,
        OP_UPSERT,
        &payload,
    )?;

    Ok(link)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn link_task_to_event(
    task_id: String,
    event_id: String,
) -> Result<TaskCalendarEventLink, String> {
    // validate UUID shape at the trust boundary so a
    // malformed id never reaches `format!("{task_id}:{event_id}")`
    // and ends up as a malformed outbox entity_id. Mirrors the
    // sibling provider-link surface that already adopted the
    // shared validator (#2937-L6).
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let event_id_str = crate::commands::shared::validate_uuid_id(&event_id, "event_id")?;
    let task_id = TaskId::from_trusted(task_id_str);
    let event_id = EventId::from_trusted(event_id_str);
    let conn = get_conn()?;
    let now = sync_timestamp_now();
    let link = with_immediate_transaction(&conn, |conn| {
        link_task_to_event_inner(conn, &task_id, &event_id, &now)
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(link)
}

fn unlink_task_from_event_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    event_id: &EventId,
) -> AppResult<Vec<TaskCalendarEventLink>> {
    ensure_task_exists(conn, task_id)?;
    ensure_calendar_event_exists(conn, event_id)?;

    // capture the pre-delete snapshot BEFORE the
    // DELETE so the typed `DeleteEnvelope` ships
    // `(task_id, calendar_event_id, version, created_at, updated_at)`
    // for peer LWW. The previous shape carried only
    // `{task_id, calendar_event_id}` (no `version`, no `created_at`),
    // which forced peers into the degenerate no-version compare
    // branch on the link tombstone path.
    let snapshot = crate::commands::load_task_calendar_event_link_pre_delete_snapshot(
        conn, task_id, event_id,
    )?;

    let deleted = calendar_links::delete_link(conn, task_id, event_id)?;
    if deleted == 0 {
        return Err(AppError::NotFound(format!(
            "Task-calendar event link not found: {task_id}:{event_id}"
        )));
    }
    let entity_id = format!("{task_id}:{event_id}");
    crate::commands::enqueue_task_calendar_event_link_delete(
        conn,
        crate::commands::DeleteEnvelope::new(entity_id, snapshot),
    )?;

    // Return remaining links for this task
    let links = calendar_links::get_links_for_task(conn, task_id).map_err(AppError::from)?;
    Ok(links)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn unlink_task_from_event(
    task_id: String,
    event_id: String,
) -> Result<Vec<TaskCalendarEventLink>, String> {
    // same UUID-shape gate as the link path.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let event_id_str = crate::commands::shared::validate_uuid_id(&event_id, "event_id")?;
    let task_id = TaskId::from_trusted(task_id_str);
    let event_id = EventId::from_trusted(event_id_str);
    let conn = get_conn()?;
    let links = with_immediate_transaction(&conn, |conn| {
        unlink_task_from_event_inner(conn, &task_id, &event_id)
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(links)
}

fn get_linked_events_for_task_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
) -> AppResult<Vec<TaskCalendarEventLink>> {
    ensure_task_exists(conn, task_id)?;
    calendar_links::get_links_for_task(conn, task_id).map_err(AppError::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_linked_events_for_task(task_id: String) -> Result<Vec<TaskCalendarEventLink>, String> {
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let task_id = TaskId::from_trusted(task_id_str);
    let conn = get_read_conn()?;
    get_linked_events_for_task_inner(&conn, &task_id).map_err(String::from)
}

/// Test-only inverse of `get_linked_events_for_task`. The renderer
/// never queried "what tasks belong to event X", so the Tauri command
/// shipped in #2940-H1 was unused; this helper stays so the existing
/// "missing event" regression test can keep exercising the lookup.
#[cfg(test)]
fn get_linked_tasks_for_event_inner(
    conn: &rusqlite::Connection,
    event_id: &EventId,
) -> AppResult<Vec<TaskCalendarEventLink>> {
    ensure_calendar_event_exists(conn, event_id)?;
    calendar_links::get_links_for_event(conn, event_id).map_err(AppError::from)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::AppError;

    use crate::test_support::test_conn;

    fn seed_task_and_event(conn: &rusqlite::Connection) {
        // lift the task row to canonical TaskBuilder;
        // the calendar event row stays inline because there is no
        // CalendarEventBuilder yet.
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000001",
        )
        .title("Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(conn);
        conn.execute(
            "INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000028', 'Event', '2026-03-29', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            [],
        )
        .expect("seed calendar event");
    }

    #[test]
    fn unlink_task_from_event_inner_rejects_missing_link() {
        let conn = test_conn();
        seed_task_and_event(&conn);

        let error = unlink_task_from_event_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
            &EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000028".to_string()),
        )
        .expect_err("missing link should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains(
                "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000028"
            )),
            other => panic!("expected not found error, got {other:?}"),
        }
    }

    #[test]
    fn link_task_to_event_inner_rejects_missing_calendar_event() {
        let conn = test_conn();
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000001",
        )
        .title("Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(&conn);

        let error = link_task_to_event_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
            &EventId::from_trusted("missing-event".to_string()),
            "2026-03-29T09:00:00Z",
        )
        .expect_err("missing calendar event should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains("missing-event")),
            other => panic!("expected not found error, got {other:?}"),
        }
    }

    #[test]
    fn link_task_to_event_inner_rejects_archived_task_without_relation_or_outbox_rows() {
        let conn = test_conn();
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000010",
        )
        .title("Archived Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .archived_at(Some("2026-03-29T08:30:00.000000Z"))
        .insert(&conn);
        conn.execute(
            "INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000028', 'Event', '2026-03-29', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            [],
        )
        .expect("seed calendar event");

        let error = link_task_to_event_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000010".to_string()),
            &EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000028".to_string()),
            "2026-03-29T09:00:00Z",
        )
        .expect_err("archived task link should be rejected");

        match error {
            AppError::NotFound(message) => {
                assert!(message.contains("01966a3f-7c8b-7d4e-8f3a-000000000010"))
            }
            other => panic!("expected archived task to be treated as not found, got {other:?}"),
        }

        let relation_rows: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM task_calendar_event_links",
                [],
                |row| row.get(0),
            )
            .expect("count relation rows");
        assert_eq!(relation_rows, 0);

        let outbox_rows: i64 = conn
            .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
            .expect("count sync outbox rows");
        assert_eq!(outbox_rows, 0);
    }

    #[test]
    fn get_linked_events_for_task_inner_rejects_missing_task() {
        let conn = test_conn();

        let error = get_linked_events_for_task_inner(
            &conn,
            &TaskId::from_trusted("missing-task".to_string()),
        )
        .expect_err("missing task should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains("missing-task")),
            other => panic!("expected not found error, got {other:?}"),
        }
    }

    #[test]
    fn get_linked_tasks_for_event_inner_rejects_missing_event() {
        let conn = test_conn();

        let error = get_linked_tasks_for_event_inner(
            &conn,
            &EventId::from_trusted("missing-event".to_string()),
        )
        .expect_err("missing event should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains("missing-event")),
            other => panic!("expected not found error, got {other:?}"),
        }
    }
}
