use std::collections::HashSet;

use super::*;
use crate::commands::sync_timestamp_now;
use crate::error::{AppError, AppResult};

pub(crate) fn get_current_focus_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
) -> AppResult<Option<CurrentFocusWithTasks>> {
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
        return Ok(None);
    };

    let task_ids: Vec<String> = {
        let mut stmt = conn
            .prepare_cached(
                "SELECT task_id FROM current_focus_items WHERE date = ?1 ORDER BY position ASC",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![&date], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?
    };

    let tasks = fetch_ordered_active_tasks_by_ids(conn, &task_ids, "Current focus")?;

    Ok(Some(CurrentFocusWithTasks {
        date,
        task_ids,
        briefing,
        timezone,
        tasks,
    }))
}

#[tauri::command]
pub fn get_current_focus() -> Result<Option<CurrentFocusWithTasks>, String> {
    let conn = get_read_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    get_current_focus_with_conn(&conn, &today).map_err(String::from)
}

/// Maximum number of tasks in current focus (defensive bound).
const CURRENT_FOCUS_TASK_IDS_MAX: usize = 50;

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Add task IDs to today's current focus, creating the focus header if it does
/// not yet exist. Duplicates are silently skipped.
fn add_to_current_focus_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
    task_ids: Vec<String>,
    now: &str,
) -> AppResult<CurrentFocusWithTasks> {
    if task_ids.is_empty() {
        return Err(AppError::Validation(
            "task_ids must contain at least one item".to_string(),
        ));
    }

    // Cap the incoming batch at the IPC boundary BEFORE the O(n·m)
    // `contains` walk against the existing focus list. A peer that
    // POSTs `task_ids: [<id>; 100_000]` would otherwise spin in a
    // quadratic merge for several seconds before any post-merge size
    // check fires; the cap below stops that pathological case at
    // constant work.
    if task_ids.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(AppError::Validation(format!(
            "task_ids contains {} items, which exceeds the {}-item current-focus cap",
            task_ids.len(),
            CURRENT_FOCUS_TASK_IDS_MAX
        )));
    }
    validate_task_ids_active(conn, &task_ids, "task_ids")?;

    let timezone = lorvex_workflow::timezone::anchored_timezone_name(conn)?;

    // Read existing focus task_ids (empty vec if no focus exists yet)
    let existing_ids: Vec<String> =
        lorvex_store::current_focus_items::query_focus_task_ids(conn, today)
            .map_err(AppError::from)?;
    let before_count = existing_ids.len();

    // dedup via HashSet membership rather than the
    // prior `Vec::contains` which was O(n) per insertion. With both
    // sides bounded at CURRENT_FOCUS_TASK_IDS_MAX the absolute work is
    // small, but the earlier shape was the kind of accidental quadratic
    // a future cap-bump (or a peer write that bypassed this gate)
    // would silently amplify.
    let mut merged_ids = existing_ids;
    let mut seen: HashSet<String> = merged_ids.iter().cloned().collect();
    for id in &task_ids {
        if seen.insert(id.clone()) {
            merged_ids.push(id.clone());
        }
    }

    if merged_ids.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(AppError::Validation(format!(
            "Current focus would exceed {} tasks after adding {} new items (current: {})",
            CURRENT_FOCUS_TASK_IDS_MAX,
            task_ids.len(),
            before_count
        )));
    }

    // Mint `version` as a canonical HLC via the process-wide HlcState
    // so the row's `version` column is comparable with peer envelopes.
    // An ISO `now` timestamp would lex-sort ABOVE every legitimate HLC
    // (`'2'` > `'0'`), breaking both the local LWW gate
    // (`?1 > version`) and the sync-apply LWW gate
    // (`excluded.version > current_focus.version`).
    let version = crate::hlc::generate_version_result()?;

    // Upsert header (creates if needed, preserves timezone on update)
    lorvex_store::current_focus_items::upsert_current_focus_header(
        conn, today, None, &timezone, &version, now,
    )
    .map_err(AppError::from)?;

    // bake the parent `(version, updated_at)` bump into
    // the materialize call so a future caller can't forget the touch
    // and ship an envelope whose children disagree with the parent
    // row. The `upsert_current_focus_header` above already advanced
    // the row to `version`; passing the same string here is a benign
    // re-stamp that keeps every local-write path uniform.
    lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
        conn,
        today,
        &merged_ids,
        &version,
        now,
    )
    .map_err(AppError::from)?;

    // enqueue via the canonical aggregate builder so the
    // envelope shape matches the apply pipeline expectation
    // (`current_focus_items` rebuilt from `task_ids`).
    enqueue_current_focus_upsert_for_date(conn, today)?;

    let tasks = fetch_ordered_active_tasks_by_ids(conn, &merged_ids, "Current focus add")?;

    Ok(CurrentFocusWithTasks {
        date: today.to_string(),
        task_ids: merged_ids,
        briefing: None,
        timezone: Some(timezone),
        tasks,
    })
}

/// Shape-check every task UUID at the IPC boundary before opening
/// the writer transaction. Without this gate the merge loop and
/// FK-bound writer would accept a malformed id (e.g. a frontend bug
/// shipping `"  task-1  "` post-trim with the wrong shape) and the
/// failure would surface only as an opaque sync-apply mismatch on a
/// peer device. Matches the validation pattern used by sibling
/// task-id IPC handlers.
pub(crate) fn validate_current_focus_task_ids(task_ids: &[String]) -> Result<Vec<String>, String> {
    task_ids
        .iter()
        .map(|raw| crate::commands::shared::validate_uuid_id(raw, "task_id"))
        .collect()
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_to_current_focus(task_ids: Vec<String>) -> Result<CurrentFocusWithTasks, String> {
    let task_ids = validate_current_focus_task_ids(&task_ids)?;
    let conn = get_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let now = sync_timestamp_now();

    with_immediate_transaction(&conn, |conn| {
        add_to_current_focus_with_conn(conn, &today, task_ids.clone(), &now)
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
    fn get_current_focus_with_conn_rejects_missing_task_reference() {
        let conn = setup();
        let today = "2026-03-29";
        conn.execute(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
             VALUES (?1, 'briefing', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            params![today],
        )
        .expect("seed current focus header");
        conn.execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES (?1, 0, 'missing-task')",
            params![today],
        )
        .expect("seed dangling current focus item");

        let error = get_current_focus_with_conn(&conn, today)
            .expect_err("dangling current focus task should be rejected");

        match error {
            AppError::Internal(message) => assert!(message.contains("missing-task")),
            other => panic!("expected internal consistency error, got {other:?}"),
        }
    }

    #[test]
    fn get_current_focus_with_conn_omits_archived_tasks_but_preserves_task_ids() {
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

        let focus = get_current_focus_with_conn(&conn, today)
            .expect("current focus read should succeed")
            .expect("current focus exists");

        assert_eq!(focus.task_ids, vec!["task-active", "task-archived"]);
        let task_ids: Vec<&str> = focus.tasks.iter().map(|task| task.id.as_str()).collect();
        assert_eq!(
            task_ids,
            vec!["task-active"],
            "archived tasks must be omitted from the rendered task cards"
        );
    }

    #[test]
    fn add_to_current_focus_with_conn_rejects_archived_task_id() {
        let conn = setup();
        let today = "2026-03-29";
        use lorvex_store::test_support::fixtures::TaskBuilder;
        TaskBuilder::new("task-archived")
            .title("Archived task")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .archived_at(Some("2026-03-29T09:00:00Z"))
            .insert(&conn);

        let error = add_to_current_focus_with_conn(
            &conn,
            today,
            vec!["task-archived".to_string()],
            "2026-03-29T09:30:00Z",
        )
        .expect_err("archived tasks must be rejected on add");

        match error {
            AppError::Validation(message) => {
                assert!(message.contains("archived"), "unexpected error: {message}");
                assert!(
                    message.contains("task-archived"),
                    "expected archived id in error: {message}"
                );
            }
            other => panic!("expected validation error, got {other:?}"),
        }
        let focus_items_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
                params![today],
                |row| row.get(0),
            )
            .expect("count focus items");
        assert_eq!(
            focus_items_count, 0,
            "rejected add must not write focus items"
        );
    }

    /// Regression: `add_to_current_focus_with_conn` must stamp
    /// `current_focus.version` with a canonical HLC, not an ISO `now`
    /// timestamp. ISO strings lex-sort ABOVE every legitimate HLC
    /// (`'2'` > `'0'`), so a stamped ISO would break both the local
    /// LWW gate (`?1 > version`) and the sync-apply LWW gate against
    /// peer envelopes carrying a real HLC.
    #[test]
    fn add_to_current_focus_with_conn_stamps_hlc_version_not_iso_timestamp() {
        let conn = setup();
        let today = "2026-04-26";
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new("task-a")
            .title("Task A")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-04-26T08:00:00Z")
            .insert(&conn);

        let now = "2026-04-26T09:00:00.000000Z";
        add_to_current_focus_with_conn(&conn, today, vec!["task-a".to_string()], now)
            .expect("add to current focus succeeds");

        let stamped_version: String = conn
            .query_row(
                "SELECT version FROM current_focus WHERE date = ?1",
                params![today],
                |row| row.get::<_, String>(0),
            )
            .expect("read current_focus.version");

        assert!(
            lorvex_domain::hlc::Hlc::parse(&stamped_version).is_ok(),
            "current_focus.version should be a canonical HLC string, got {stamped_version:?}"
        );
        assert_ne!(
            stamped_version, now,
            "current_focus.version must not be the ISO `now` timestamp (#2961)"
        );
        assert!(
            !stamped_version.contains('T'),
            "current_focus.version should not contain ISO date separators, got {stamped_version:?}"
        );
    }

    /// Regression: `add_to_current_focus` must reject malformed UUIDs
    /// at the IPC boundary before any DB work runs. Forwarding a
    /// caller-supplied string straight into the writer transaction
    /// would surface a frontend bug (e.g. `"  task-1  "`) or a
    /// malformed IPC call only as an opaque sync-apply mismatch on a
    /// peer device.
    #[test]
    fn validate_current_focus_task_ids_rejects_non_uuid_input() {
        let error = validate_current_focus_task_ids(&["not-a-uuid".to_string()])
            .expect_err("malformed UUID must be rejected");
        assert!(error.contains("task_id"), "unexpected error: {error}");
    }

    #[test]
    fn validate_current_focus_task_ids_rejects_empty_string() {
        let error = validate_current_focus_task_ids(&["   ".to_string()])
            .expect_err("empty/whitespace UUID must be rejected");
        assert!(error.contains("task_id"), "unexpected error: {error}");
    }

    #[test]
    fn validate_current_focus_task_ids_accepts_canonical_uuids() {
        let id_a = lorvex_domain::new_entity_id_string();
        let id_b = lorvex_domain::new_entity_id_string();
        let validated = validate_current_focus_task_ids(&[format!("  {id_a}  "), id_b.clone()])
            .expect("canonical UUIDs must validate");
        assert_eq!(validated, vec![id_a, id_b]);
    }
}
