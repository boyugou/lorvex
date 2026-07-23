// `ENTITY_CURRENT_FOCUS` is referenced only by the colocated
// `#[cfg(test)]` outbox-payload assertion. Gate the import with the
// same cfg so the release build stays clean. `OP_UPSERT` is no longer
// referenced from this file — removed.
#[cfg(test)]
use lorvex_domain::naming::ENTITY_CURRENT_FOCUS;

use super::*;
use crate::error::AppError;

use super::shared::{normalize_requested_task_ids, validate_same_open_task_ids};
use crate::commands::sync_timestamp_now;

fn reorder_current_focus_open_tasks_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
    open_task_ids: Vec<String>,
    now: &str,
) -> Result<CurrentFocusWithTasks, AppError> {
    // only `date`, `briefing`, `timezone` are needed for
    // the reorder response shape — the canonical aggregate builder
    // re-reads everything else when building the sync envelope, so
    // the previous `created_at` projection became dead.
    let plan_row: Option<(String, Option<String>, Option<String>)> = conn
        .query_row(
            "SELECT date, briefing, timezone FROM current_focus WHERE date = ?1",
            params![today],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, Option<String>>(2)?,
                ))
            },
        )
        .optional()
        .map_err(AppError::from)?;

    let Some((date, briefing, timezone)) = plan_row else {
        return Err(AppError::NotFound(
            "No current focus exists for today".to_string(),
        ));
    };
    let effective_timezone =
        timezone.unwrap_or(lorvex_workflow::timezone::anchored_timezone_name(conn)?);

    let existing_task_ids: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT task_id FROM current_focus_items WHERE date = ?1 ORDER BY position ASC",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![&date], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?
    };
    if existing_task_ids.is_empty() {
        return Err(AppError::Validation(
            "Daily plan has no task ids to reorder".to_string(),
        ));
    }

    let normalized_requested = normalize_requested_task_ids(open_task_ids);

    let existing_open_ids: Vec<String> = {
        let placeholders = lorvex_domain::sql_in_placeholders(existing_task_ids.len(), 0);
        let sql = format!(
            "SELECT id FROM tasks WHERE id IN ({placeholders}) AND status = 'open' AND archived_at IS NULL"
        );
        let mut stmt = conn.prepare(&sql).map_err(AppError::from)?;
        let param_values: Vec<Box<dyn rusqlite::types::ToSql>> = existing_task_ids
            .iter()
            .map(|id| Box::new(id.clone()) as Box<dyn rusqlite::types::ToSql>)
            .collect();
        let param_refs: Vec<&dyn rusqlite::types::ToSql> = param_values
            .iter()
            .map(std::convert::AsRef::as_ref)
            .collect();
        let open_set: HashSet<String> = stmt
            .query_map(param_refs.as_slice(), |row| row.get::<_, String>(0))
            .map_err(AppError::from)?
            .collect::<Result<HashSet<_>, _>>()
            .map_err(AppError::from)?;
        existing_task_ids
            .iter()
            .filter(|id| open_set.contains(*id))
            .cloned()
            .collect()
    };

    if existing_open_ids.is_empty() {
        return Err(AppError::Validation(
            "Daily plan has no open tasks to reorder".to_string(),
        ));
    }

    validate_same_open_task_ids(
        &existing_open_ids,
        &normalized_requested,
        "open_task_ids must contain the same open task ids currently in today's current focus",
    )?;

    let existing_open_set: HashSet<String> = existing_open_ids.iter().cloned().collect();
    let mut reordered_task_ids: Vec<String> = Vec::with_capacity(existing_task_ids.len());
    let mut next_open_idx = 0usize;
    for id in &existing_task_ids {
        if existing_open_set.contains(id) {
            reordered_task_ids.push(normalized_requested[next_open_idx].clone());
            next_open_idx += 1;
        } else {
            reordered_task_ids.push(id.clone());
        }
    }

    if reordered_task_ids != existing_task_ids {
        // rebuild children + bump parent header in one
        // call so the row's `version` column moves forward in lockstep
        // with the new task_ids order. The fresh HLC is also embedded
        // in the outbox envelope below; `version_stamp` re-stamps at
        // the same string and treats it as a benign no-op.
        let version = crate::hlc::generate_version_result()?;
        lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
            conn,
            &date,
            &reordered_task_ids,
            &version,
            now,
        )
        .map_err(AppError::from)?;

        // route through the canonical aggregate builder so
        // peers see the new task_ids order rebuilt from the live row,
        // not from a hand-rolled snapshot that could drift from what
        // `materialize_focus_items` actually persisted above.
        enqueue_current_focus_upsert_for_date(conn, &date)?;
    }

    let tasks =
        fetch_ordered_active_tasks_by_ids(conn, &reordered_task_ids, "Current focus reorder")?;

    Ok(CurrentFocusWithTasks {
        date,
        task_ids: reordered_task_ids,
        briefing,
        timezone: Some(effective_timezone),
        tasks,
    })
}

#[tauri::command]
pub fn reorder_current_focus_open_tasks(
    open_task_ids: Vec<String>,
) -> Result<CurrentFocusWithTasks, String> {
    let conn = get_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let now = sync_timestamp_now();
    let open_task_ids_for_tx = open_task_ids;

    with_immediate_transaction(&conn, |conn| {
        reorder_current_focus_open_tasks_with_conn(conn, &today, open_task_ids_for_tx.clone(), &now)
    })
    .inspect(|_| {
        event_bus::emit_data_changed(event_bus::Entity::Planning);
    })
    .map_err(String::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;

    fn setup() -> rusqlite::Connection {
        test_conn()
    }

    #[test]
    fn reorder_current_focus_open_tasks_with_conn_enqueues_reordered_snapshot() {
        let conn = setup();
        let today = "2026-03-29";
        // lift to canonical TaskBuilder.
        use lorvex_store::test_support::fixtures::TaskBuilder;
        TaskBuilder::new("task-a")
            .title("Task A")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .insert(&conn);
        TaskBuilder::new("task-b")
            .title("Task B")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .insert(&conn);
        conn.execute(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
             VALUES (?1, 'briefing', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            params![today],
        )
        .expect("seed current focus header");
        conn.execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES
             (?1, 0, 'task-a'),
             (?1, 1, 'task-b')",
            params![today],
        )
        .expect("seed current focus items");

        let reordered = reorder_current_focus_open_tasks_with_conn(
            &conn,
            today,
            vec!["task-b".to_string(), "task-a".to_string()],
            "2026-03-29T09:00:00Z",
        )
        .expect("reorder current focus");

        assert_eq!(reordered.task_ids, vec!["task-b", "task-a"]);

        let payload: String = conn
            .query_row(
                "SELECT payload
                 FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2
                 ORDER BY id DESC
                 LIMIT 1",
                params![ENTITY_CURRENT_FOCUS, today],
                |row| row.get::<_, String>(0),
            )
            .expect("load current focus outbox payload");
        let payload: serde_json::Value =
            serde_json::from_str(&payload).expect("current focus payload should be valid json");

        assert_eq!(payload["date"], today);
        assert_eq!(payload["task_ids"], serde_json::json!(["task-b", "task-a"]));
    }

    #[test]
    fn reorder_current_focus_open_tasks_with_conn_ignores_archived_task_cards() {
        let conn = setup();
        let today = "2026-03-29";
        use lorvex_store::test_support::fixtures::TaskBuilder;
        TaskBuilder::new("task-active")
            .title("Active task")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .insert(&conn);
        TaskBuilder::new("task-archived")
            .title("Archived task")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .archived_at(Some("2026-03-29T09:00:00Z"))
            .insert(&conn);
        conn.execute(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
             VALUES (?1, 'briefing', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            params![today],
        )
        .expect("seed current focus header");
        conn.execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES
             (?1, 0, 'task-active'),
             (?1, 1, 'task-archived')",
            params![today],
        )
        .expect("seed current focus items");

        let reordered = reorder_current_focus_open_tasks_with_conn(
            &conn,
            today,
            vec!["task-active".to_string()],
            "2026-03-29T09:30:00Z",
        )
        .expect("reordering active focus tasks should ignore archived pins");

        assert_eq!(reordered.task_ids, vec!["task-active", "task-archived"]);
        let task_ids: Vec<&str> = reordered
            .tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect();
        assert_eq!(task_ids, vec!["task-active"]);
    }
}
