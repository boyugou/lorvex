use lorvex_domain::naming::{DeferReason, EDGE_TASK_TAG, OP_UPSERT};
use lorvex_runtime::bump_local_change_seq;
use lorvex_workflow::task_enrichment;

use crate::error::{AppError, AppResult};

use super::constants::TASK_COLS;
use super::models::{Task, TaskChecklistItem};
use rusqlite::params;

// ── Enrichment delegation to shared module ──────────────────────────

fn task_planned(task: &Task) -> Option<chrono::NaiveDate> {
    task.planned_date
        .as_deref()
        .and_then(|raw| lorvex_domain::time::parse_iso_date(raw).ok())
}

fn task_due(task: &Task) -> Option<chrono::NaiveDate> {
    task.due_date
        .as_deref()
        .and_then(|raw| lorvex_domain::time::parse_iso_date(raw).ok())
}

fn enrich_tasks_all(conn: &rusqlite::Connection, tasks: &mut [Task]) -> AppResult<()> {
    if tasks.is_empty() {
        return Ok(());
    }
    let today = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let dates: Vec<(&str, Option<chrono::NaiveDate>, Option<chrono::NaiveDate>)> = tasks
        .iter()
        .map(|t| (t.id.as_str(), task_planned(t), task_due(t)))
        .collect();
    let mut map =
        task_enrichment::compute_enrichments(conn, &dates, &today).map_err(AppError::from)?;
    for task in tasks.iter_mut() {
        let enrichment = map.remove(&task.id).unwrap_or_default();
        task.tags = enrichment.tags;
        task.depends_on = enrichment.depends_on;
        task.checklist_items = enrichment.checklist_items.map(|v| {
            v.into_iter()
                .map(|item| TaskChecklistItem {
                    id: item.id,
                    task_id: item.task_id,
                    position: item.position,
                    text: item.text,
                    completed_at: item.completed_at,
                    version: item.version,
                    created_at: item.created_at,
                    updated_at: item.updated_at,
                })
                .collect()
        });
        task.lateness_state = enrichment.lateness;
    }
    Ok(())
}

// ── Row helpers ─────────────────────────────────────────────────────

pub(crate) fn task_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Task> {
    Ok(Task {
        id: row.get(0)?,
        title: row.get(1)?,
        body: row.get(2)?,
        raw_input: row.get(3)?,
        ai_notes: row.get(4)?,
        status: row.get(5)?,
        list_id: row.get(6)?,
        tags: None, // derived from task_tags join table, not a SQL column
        checklist_items: None,
        priority: row.get(7)?,
        due_date: row.get(8)?,
        due_time: row.get(9)?,
        estimated_minutes: row.get(10)?,
        recurrence: row.get(11)?,
        recurrence_exceptions: row.get(12)?,
        depends_on: None, // derived from task_dependencies edge table, not a SQL column
        spawned_from: row.get(13)?,
        recurrence_group_id: row.get(14)?,
        canonical_occurrence_date: row.get(15)?,
        version: row.get(16)?,
        created_at: row.get(17)?,
        updated_at: row.get(18)?,
        completed_at: row.get(19)?,
        last_deferred_at: row.get(20)?,
        last_defer_reason: row
            .get::<_, Option<String>>(21)?
            .as_deref()
            .and_then(DeferReason::parse),
        lateness_state: None,
        planned_date: row.get(22)?,
        defer_count: row.get(23)?,
        // Column order matches TASK_COLS — must stay in sync when adding
        // new fields. `recurrence_instance_key` is last because it was
        // appended to the SELECT list in the convergence era.
        recurrence_instance_key: row.get(24)?,
        // trailing Trash column. See TASK_COLS.
        archived_at: row.get(25)?,
    })
}

/// Convert a shared-repo `TaskRow` to the Tauri IPC `Task` model.
///
/// Derived fields (`tags`, `depends_on`, `lateness_state`, `checklist_items`)
/// are set to `None` — call `enrich_tasks_all` afterward.
fn task_from_task_row(row: lorvex_store::repositories::task::read::TaskRow) -> Task {
    let (core, scheduling, recurrence, lifecycle) = row.into_parts();
    let core = core.into_fields();
    let scheduling = scheduling.into_fields();
    let recurrence = recurrence.into_fields();
    let lifecycle = lifecycle.into_fields();
    Task {
        id: core.id,
        title: core.title,
        body: core.body,
        raw_input: core.raw_input,
        ai_notes: core.ai_notes,
        status: core.status,
        list_id: core.list_id,
        tags: None,
        checklist_items: None,
        priority: core.priority,
        // Re-render the typed `Date` / `TimeOfDay` columns into the
        // `Option<String>` shape the IPC `Task` model exposes; the
        // typed wrapper guarantees the canonical YYYY-MM-DD / HH:MM
        // form so this is a one-line shape conversion, not a
        // re-validation.
        due_date: scheduling.due.date().map(|d| d.to_string()),
        due_time: scheduling.due.time().map(|t| t.to_string()),
        estimated_minutes: scheduling.estimated_minutes,
        recurrence: recurrence.recurrence,
        recurrence_exceptions: recurrence.recurrence_exceptions,
        depends_on: None,
        spawned_from: recurrence.spawned_from,
        recurrence_group_id: recurrence.recurrence_group_id,
        canonical_occurrence_date: recurrence.canonical_occurrence_date.map(|d| d.to_string()),
        // Carry `recurrence_instance_key` through so `enqueue_task_upsert`
        // emits it in the sync envelope — the cross-device dedup merge in
        // `lorvex_sync::apply::aggregate::merge_duplicate_recurrence_instances`
        // depends on it.
        recurrence_instance_key: recurrence.recurrence_instance_key,
        version: core.version,
        created_at: core.created_at,
        updated_at: core.updated_at,
        completed_at: lifecycle.completed_at,
        last_deferred_at: scheduling.last_deferred_at,
        last_defer_reason: scheduling
            .last_defer_reason
            .as_deref()
            .and_then(DeferReason::parse),
        lateness_state: None,
        planned_date: scheduling.planned_date.map(|d| d.to_string()),
        defer_count: scheduling.defer_count,
        archived_at: lifecycle.archived_at,
    }
}

/// Convert a vec of shared-repo `TaskRow` into enriched Tauri `Task` models.
///
/// Maps each `TaskRow` to `Task`, then batch-enriches with tags and depends_on.
pub(crate) fn tasks_from_task_rows(
    conn: &rusqlite::Connection,
    rows: Vec<lorvex_store::repositories::task::read::TaskRow>,
) -> AppResult<Vec<Task>> {
    let mut tasks: Vec<Task> = rows.into_iter().map(task_from_task_row).collect();
    enrich_tasks_all(conn, &mut tasks)?;
    Ok(tasks)
}

pub(crate) fn rows_from_query<T, F>(
    conn: &rusqlite::Connection,
    sql: &str,
    p: impl rusqlite::Params,
    mapper: F,
) -> AppResult<Vec<T>>
where
    F: FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<T>,
{
    // route through `prepare_cached` so every caller (task list,
    // calendar timeline, search, etc.) reuses the planned statement
    // across IPC requests instead of reparsing the same SQL on each
    // call. Each distinct SQL string is cached once on the
    // connection and reused on subsequent invocations.
    let mut stmt = conn.prepare_cached(sql).map_err(AppError::from)?;
    let rows = stmt
        .query_map(p, mapper)
        .map_err(AppError::from)?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(AppError::from)?;
    Ok(rows)
}

pub(crate) fn tasks_from_query(
    conn: &rusqlite::Connection,
    sql: &str,
    p: impl rusqlite::Params,
) -> AppResult<Vec<Task>> {
    let mut tasks = rows_from_query(conn, sql, p, task_from_row)?;
    enrich_tasks_all(conn, &mut tasks)?;
    Ok(tasks)
}

pub(crate) fn fetch_tasks_by_ids(
    conn: &rusqlite::Connection,
    task_ids: &[String],
) -> AppResult<std::collections::HashMap<String, Task>> {
    if task_ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }

    let placeholders = lorvex_domain::sql_in_placeholders(task_ids.len(), 0);
    let sql = format!("SELECT {TASK_COLS} FROM tasks WHERE id IN ({placeholders})");
    let params: Vec<&dyn rusqlite::types::ToSql> = task_ids
        .iter()
        .map(|id| id as &dyn rusqlite::types::ToSql)
        .collect();

    let tasks = tasks_from_query(conn, &sql, params.as_slice())?;
    let mut tasks_by_id = std::collections::HashMap::with_capacity(tasks.len());
    for task in tasks {
        tasks_by_id.insert(task.id.clone(), task);
    }
    Ok(tasks_by_id)
}

pub(crate) fn fetch_ordered_tasks_by_ids(
    conn: &rusqlite::Connection,
    task_ids: &[String],
    context: &str,
) -> AppResult<Vec<Task>> {
    let mut tasks_by_id = fetch_tasks_by_ids(conn, task_ids)?;
    let mut ordered = Vec::with_capacity(task_ids.len());
    let mut missing = Vec::new();

    for task_id in task_ids {
        match tasks_by_id.remove(task_id) {
            Some(task) => ordered.push(task),
            None => missing.push(task_id.clone()),
        }
    }

    if !missing.is_empty() {
        return Err(AppError::Internal(format!(
            "{context} references missing tasks: {}",
            missing.join(", ")
        )));
    }

    Ok(ordered)
}

/// Fetch tasks in caller order, but omit archived rows while still
/// treating missing ids as an internal consistency error.
///
/// Current focus keeps the raw `task_ids` link table intact so a task
/// archived after being pinned can reappear if restored. The rendered
/// task cards, however, must match active-task read surfaces and skip
/// `archived_at IS NOT NULL` rows.
pub(crate) fn fetch_ordered_active_tasks_by_ids(
    conn: &rusqlite::Connection,
    task_ids: &[String],
    context: &str,
) -> AppResult<Vec<Task>> {
    let tasks_by_id = fetch_tasks_by_ids(conn, task_ids)?;
    let mut ordered = Vec::with_capacity(task_ids.len());
    let mut missing = Vec::new();

    for task_id in task_ids {
        match tasks_by_id.get(task_id) {
            Some(task) if task.archived_at.is_none() => ordered.push(task.clone()),
            Some(_) => {}
            None => missing.push(task_id.clone()),
        }
    }

    if !missing.is_empty() {
        return Err(AppError::Internal(format!(
            "{context} references missing tasks: {}",
            missing.join(", ")
        )));
    }

    Ok(ordered)
}

/// Validate that every id resolves to an active task row.
///
/// This is the Tauri-side equivalent of MCP's `tasks_active` contract
/// validator. IPC boundary code still owns UUID shape validation; this
/// helper checks the database state before writer paths materialize
/// forward-looking task references.
pub(crate) fn validate_task_ids_active(
    conn: &rusqlite::Connection,
    task_ids: &[String],
    field_name: &'static str,
) -> AppResult<()> {
    let tasks_by_id = fetch_tasks_by_ids(conn, task_ids)?;

    for task_id in task_ids {
        match tasks_by_id.get(task_id) {
            Some(task) if task.archived_at.is_some() => {
                return Err(AppError::Validation(format!(
                    "{field_name} references archived task: {task_id}"
                )));
            }
            Some(_) => {}
            None => {
                return Err(AppError::Validation(format!(
                    "{field_name} references non-existent task: {task_id}"
                )));
            }
        }
    }

    Ok(())
}

/// Read a single `tasks`-row WITHOUT loading the derived child
/// collections (tags, depends_on, checklist_items, lateness_state).
///
/// Use this in the inside-loop of batch ops that pipe the row straight
/// into `enqueue_task_upsert` — that path runs the result through
/// `lorvex_sync::task_payload::strip_derived_task_fields` which
/// discards every derived field, so the per-row 3-query enrichment
/// (`fetch_task_by_id`) is wasted work. The post-loop
/// `fetch_ordered_tasks_by_ids` does the single enriched batch read
/// for the user-visible response.
pub(crate) fn fetch_task_row_unenriched(conn: &rusqlite::Connection, id: &str) -> AppResult<Task> {
    let sql = format!("SELECT {TASK_COLS} FROM tasks WHERE id = ?1");
    conn.query_row(&sql, params![id], task_from_row)
        .optional()
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("Task not found: {id}")))
}

pub(crate) fn fetch_task_by_id(conn: &rusqlite::Connection, id: &str) -> AppResult<Task> {
    let mut task = fetch_task_row_unenriched(conn, id)?;
    enrich_tasks_all(conn, std::slice::from_mut(&mut task))?;
    Ok(task)
}

/// Tauri-side writer wrapper: opens `BEGIN IMMEDIATE`, runs the closure,
/// bumps `local_change_seq`, and commits or rolls back based on the
/// Result.
///
/// Panic-safety, busy-retry, and disk-full breaker plumbing are
/// delegated to [`lorvex_store::with_immediate_transaction`] so both
/// wrappers share one implementation. The Tauri-specific addition is
/// the post-closure `bump_local_change_seq` call, which runs inside
/// the same transaction so the seq bump is atomic with the writes
/// that triggered it: a panic in `bump_local_change_seq` rolls back
/// the writes via the inner wrapper's rollback contract. Running the
/// bump between the closure return and COMMIT would require a
/// separate panic-catcher and a duplicate rollback path.
pub(crate) fn with_immediate_transaction<T, F>(conn: &rusqlite::Connection, op: F) -> AppResult<T>
where
    F: FnOnce(&rusqlite::Connection) -> Result<T, AppError>,
{
    lorvex_store::with_immediate_transaction(conn, |conn| {
        let value = op(conn)?;
        // `bump_local_change_seq` runs inside the same transaction so
        // the seq bump is atomic with the writes. A panic here unwinds
        // through the inner wrapper's `catch_unwind` and the inner
        // wrapper rolls back the BEGIN IMMEDIATE before resuming the
        // panic — same panic-safety contract the previous hand-rolled
        // version encoded.
        bump_local_change_seq(conn).map_err(AppError::from)?;
        Ok(value)
    })
}

pub(crate) trait OptionalExt<T> {
    fn optional(self) -> rusqlite::Result<Option<T>>;
}

impl<T> OptionalExt<T> for rusqlite::Result<T> {
    fn optional(self) -> rusqlite::Result<Option<T>> {
        match self {
            Ok(v) => Ok(Some(v)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }
}

/// Resolve a tag display name to its UUID id, creating the tag row if it does not exist.
/// Returns `(tag_id, was_created)`.
fn resolve_or_create_tag_entry(
    conn: &rusqlite::Connection,
    name: &str,
    now: &str,
) -> AppResult<(String, bool)> {
    use lorvex_store::repositories::tag_repo;

    // The store-layer signature requires an explicit `version` and
    // `now` so callers stage a deterministic timestamp upstream and
    // the tag row's `created_at`/`updated_at` stay pinned to the
    // surrounding logical write (a `sync_timestamp_now()` override
    // inside `tag_repo` would drift them away from any test-pinned
    // clock). The version stamper overwrites this provisional HLC
    // during outbox enqueue, so generating one inline keeps the
    // contract simple.
    let version = crate::hlc::generate_version_result()?;
    tag_repo::resolve_or_create_tag(conn, name, &version, now).map_err(AppError::from)
}

/// Resolve/create a tag and attach it to a task, emitting canonical sync snapshots.
pub(crate) fn link_tag_to_task(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    tag_name: &str,
    now: &str,
) -> AppResult<String> {
    let (tag_id, created) = resolve_or_create_tag_entry(conn, tag_name, now)?;
    if created {
        crate::commands::enqueue_tag_upsert(conn, &tag_id)?;
    }

    let edge_version = crate::hlc::generate_version_result()?;
    let inserted = conn.execute(
        "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) VALUES (?1, ?2, ?3, ?4)",
        params![task_id.as_str(), tag_id, edge_version, now],
    )
    .map_err(AppError::from)?;

    if inserted > 0 {
        let entity_id = lorvex_domain::TaskTagEdgeId::new(
            task_id,
            &lorvex_domain::TagId::from_trusted_str(&tag_id),
        );
        let payload = serde_json::json!({
            "task_id": task_id,
            "tag_id": tag_id,
            "version": edge_version,
            "created_at": now,
            "updated_at": now,
        });
        crate::commands::enqueue_to_outbox_typed(
            conn,
            EDGE_TASK_TAG,
            entity_id.as_str(),
            OP_UPSERT,
            &payload,
        )?;
    }

    Ok(tag_id)
}

#[cfg(test)]
mod tests;
