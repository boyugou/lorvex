//! Task-row enrichment + multi-row fetch helpers.
//!
//! Split out of `query_support/mod.rs`. This module owns:
//! * the MCP-specific reminder enrichment step,
//! * the wrapper that fans the shared
//!   (`lorvex_workflow::task_enrichment`) lateness / tags /
//!   checklist / depends-on enrichment plus reminders into a single
//!   call, and the `⟦user⟧`-fenced read-path variant,
//! * the single-task fetch helpers (`fetch_task_json`, `reload_task_json`),
//! * the multi-task fetch family (`fetch_tasks_json_batch`,
//!   `fetch_existing_tasks_json`, `fetch_existing_active_tasks_json`)
//!   plus the shared `query_enriched_tasks_by_ids` /
//!   `reorder_tasks_to_request_order` helpers they all route through.

use super::suggestions::{format_suggestions, task_not_found_with_suggestions, task_suggestions};
use super::task_id::required_task_id;
use crate::error::McpError;
use lorvex_workflow::task_enrichment;
use lorvex_workflow::timezone::today_ymd_for_conn;

// ── Shared enrichment delegation ────────────────────────────────────
//
// Tags, depends_on, checklist items, and lateness enrichment are now
// handled by `lorvex_workflow::task_enrichment::compute_enrichments`,
// which returns a per-task `Enrichment` map this module folds back into
// the JSON value tree.

fn task_id_or_empty(task: &serde_json::Value) -> &str {
    task.get("id").and_then(|v| v.as_str()).unwrap_or("")
}

fn task_planned(task: &serde_json::Value) -> Option<chrono::NaiveDate> {
    task.get("planned_date")
        .and_then(|v| v.as_str())
        .and_then(|raw| lorvex_domain::time::parse_iso_date(raw).ok())
}

fn task_due(task: &serde_json::Value) -> Option<chrono::NaiveDate> {
    task.get("due_date")
        .and_then(|v| v.as_str())
        .and_then(|raw| lorvex_domain::time::parse_iso_date(raw).ok())
}

fn apply_enrichment(task: &mut serde_json::Value, enrichment: task_enrichment::Enrichment) {
    task["tags"] = match enrichment.tags {
        Some(names) => {
            serde_json::Value::Array(names.into_iter().map(serde_json::Value::String).collect())
        }
        None => serde_json::Value::Array(Vec::new()),
    };
    task["depends_on"] = match enrichment.depends_on {
        Some(ids) => {
            serde_json::Value::Array(ids.into_iter().map(serde_json::Value::String).collect())
        }
        None => serde_json::Value::Array(Vec::new()),
    };
    task["checklist_items"] = match enrichment.checklist_items {
        Some(items) => serde_json::Value::Array(
            items
                .into_iter()
                .map(|item| {
                    serde_json::json!({
                        "id": item.id,
                        "task_id": item.task_id,
                        "position": item.position,
                        "text": item.text,
                        "completed_at": item.completed_at,
                        "version": item.version,
                        "created_at": item.created_at,
                        "updated_at": item.updated_at,
                    })
                })
                .collect(),
        ),
        None => serde_json::Value::Array(Vec::new()),
    };
    // Round-trip through `serde_json::to_value` so the wire form
    // (`"past_planned"` / `"overdue_unhandled"` / `"overdue_acknowledged"`)
    // is owned by the snake_case `Serialize` impl on `TaskLateness`.
    // `None` collapses to JSON `null` to keep the previous shape.
    task["lateness_state"] = enrichment
        .lateness
        .map_or(serde_json::Value::Null, |state| {
            serde_json::to_value(state).unwrap_or(serde_json::Value::Null)
        });
}

fn apply_task_recurrence_exceptions(
    conn: &rusqlite::Connection,
    task: &mut serde_json::Value,
) -> Result<(), McpError> {
    let id = task_id_or_empty(task);
    if id.is_empty() {
        return Ok(());
    }
    let dates = lorvex_store::recurrence_exceptions::load_task_exception_dates(conn, id)?;
    task["recurrence_exceptions"] = serde_json::Value::String(serde_json::to_string(&dates)?);
    Ok(())
}

/// Apply all shared enrichments (lateness, tags, checklist items, deps)
/// plus MCP-specific enrichments (reminders) to a batch of task JSON values.
///
/// This function does NOT apply the `⟦user⟧` untrusted fence (#2422);
/// fencing is applied in the read-path tools (`get_task`, `list_tasks`,
/// `get_overview`, …) via [`enrich_and_fence_tasks_for_response`] so
/// write-path helpers that post-process the enriched task (intake-advice
/// duplicate-title detection, checklist ordering assertions) still see
/// the raw strings.
pub(crate) fn enrich_tasks_for_response(
    conn: &rusqlite::Connection,
    tasks: &mut [serde_json::Value],
) -> Result<(), McpError> {
    if !tasks.is_empty() {
        let today = today_ymd_for_conn(conn)?;
        let dates: Vec<(&str, Option<chrono::NaiveDate>, Option<chrono::NaiveDate>)> = tasks
            .iter()
            .map(|t| (task_id_or_empty(t), task_planned(t), task_due(t)))
            .collect();
        let mut map = task_enrichment::compute_enrichments(conn, &dates, &today)?;
        for task in tasks.iter_mut() {
            let id = task_id_or_empty(task).to_string();
            let enrichment = map.remove(&id).unwrap_or_default();
            apply_enrichment(task, enrichment);
            apply_task_recurrence_exceptions(conn, task)?;
        }
    }
    enrich_tasks_with_reminders(conn, tasks)?;
    Ok(())
}

/// Enrich a batch of tasks AND fence their user-origin string fields
/// with the `⟦user⟧` untrusted sentinel (#2422). Use this from
/// read-path tools (`get_task`, `list_tasks`, `get_todays_tasks`,
/// `get_upcoming_tasks`, `get_overview`, `search_tasks`, …) so the
/// assistant sees a structural security boundary around user content.
pub(crate) fn enrich_and_fence_tasks_for_response(
    conn: &rusqlite::Connection,
    tasks: &mut [serde_json::Value],
) -> Result<(), McpError> {
    enrich_tasks_for_response(conn, tasks)?;
    crate::system::text_hygiene::fence_tasks_user_fields(tasks);
    Ok(())
}

// ── MCP-specific reminder enrichment ────────────────────────────────
//
// Reminders are only surfaced in MCP responses (not in the Tauri app's
// task model), so this remains MCP-specific.

/// Attach `"reminders"` arrays to a batch of task JSON objects.
/// Uses a single batch query instead of N per-task queries.
///
/// Demoted to `pub(super) fn` so it can't be reached around
/// `enrich_tasks_for_response` — the wrapper above adds the
/// lateness / tags / checklist enrichment steps that every MCP
/// task-read consumer expects to see in the response, and routing
/// through `enrich_tasks_with_reminders` directly would skip them.
pub(super) fn enrich_tasks_with_reminders(
    conn: &rusqlite::Connection,
    tasks: &mut [serde_json::Value],
) -> Result<(), McpError> {
    if tasks.is_empty() {
        return Ok(());
    }

    // Collect all task IDs
    let task_ids: Vec<String> = tasks
        .iter()
        .map(|task| required_task_id(task, "batched task reminder enrichment").map(str::to_string))
        .collect::<Result<_, _>>()?;

    // Batch query all reminders for all tasks at once
    let placeholders = lorvex_domain::sql_in_placeholders(task_ids.len(), 0);
    let sql = format!(
        "SELECT * FROM task_reminders WHERE task_id IN ({placeholders}) ORDER BY task_id, reminder_at ASC"
    );
    let all_reminders =
        crate::json_row::query_all_as_json(conn, &sql, rusqlite::params_from_iter(&task_ids))?;

    // Group reminders by task_id
    let mut reminder_map: std::collections::HashMap<String, Vec<serde_json::Value>> =
        std::collections::HashMap::new();
    for reminder in all_reminders {
        if let Some(tid) = reminder.get("task_id").and_then(|v| v.as_str()) {
            reminder_map
                .entry(tid.to_string())
                .or_default()
                .push(reminder);
        }
    }

    // Attach to each task
    for task in tasks.iter_mut() {
        let tid = required_task_id(task, "batched task reminder enrichment")?;
        let reminders = reminder_map.remove(tid).unwrap_or_default();
        task["reminders"] = serde_json::Value::Array(reminders);
    }

    Ok(())
}

// ── Single-task fetch helpers ───────────────────────────────────────

/// Shared SELECT + enrich path for the single-task fetchers below. The
/// `Option` arm distinguishes "row absent" so each public wrapper can
/// pick its own not-found error variant.
fn select_one_task_enriched(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> Result<Option<serde_json::Value>, McpError> {
    let mut task = crate::json_row::query_one_as_json(
        conn,
        "SELECT * FROM tasks WHERE id = ?",
        [task_id.to_string()],
    )?;
    if let Some(t) = &mut task {
        enrich_tasks_for_response(conn, std::slice::from_mut(t))?;
    }
    Ok(task)
}

pub(crate) fn fetch_task_json(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> Result<serde_json::Value, McpError> {
    select_one_task_enriched(conn, task_id)?
        .ok_or_else(|| task_not_found_with_suggestions(conn, task_id))
}

/// Re-fetch a task after a write, using `load_failed_error` for the context.
pub(crate) fn reload_task_json(
    conn: &rusqlite::Connection,
    task_id: &str,
    context: &str,
) -> Result<serde_json::Value, McpError> {
    select_one_task_enriched(conn, task_id)?
        .ok_or_else(|| McpError::UserMessage(super::super::load_failed_error(context, task_id)))
}

/// Fetch multiple tasks by ID, returning an error if any ID is missing.
///
/// On partial-miss the error message enumerates every missing id and
/// attaches up to three nearest-neighbour suggestions per id drawn from
/// the local task set (#2371). The error uses `McpError::NotFound` so
/// the structured MCP boundary emits `kind: "not_found"` and the
/// assistant can distinguish a typo from a real data-integrity issue.
pub(crate) fn fetch_tasks_json_batch(
    conn: &rusqlite::Connection,
    ids: &[String],
    context: &str,
) -> Result<Vec<serde_json::Value>, McpError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let tasks = query_enriched_tasks_by_ids(conn, ids, /* only_active = */ false)?;

    // Build the request-order lookup map in a single pass: build the
    // `id → task` map once, derive `missing` from
    // `task_map.contains_key` lookups against the input ids, then
    // drain the map in request order. Avoids walking `tasks` twice
    // (once for a `HashSet<&str>` missing-id check, again to build
    // the key→value map for reordering).
    let mut task_map: std::collections::HashMap<String, serde_json::Value> =
        std::collections::HashMap::with_capacity(tasks.len());
    for task in tasks {
        let id = required_task_id(&task, "fetch_tasks_json_batch")?.to_string();
        task_map.insert(id, task);
    }

    // Verify all requested IDs landed in the map; if not, collect
    // every missing id + its suggestion block into one enriched
    // error so the assistant can recover from a typo in a single
    // round-trip.
    let missing: Vec<&String> = ids
        .iter()
        .filter(|id| !task_map.contains_key(id.as_str()))
        .collect();
    if !missing.is_empty() {
        let mut parts: Vec<String> = Vec::with_capacity(missing.len());
        for id in &missing {
            let suggestions = task_suggestions(conn, id);
            if suggestions.is_empty() {
                parts.push(format!("'{id}'"));
            } else {
                parts.push(format!(
                    "'{id}' (did you mean: {})",
                    format_suggestions(&suggestions),
                ));
            }
        }
        let message = format!(
            "Error: {context} failed — {} task{} not found: {}",
            missing.len(),
            super::plural_s(missing.len()),
            parts.join("; "),
        );
        return Err(McpError::NotFound(message));
    }

    // Return in request order. `task_map.remove(id)` instead of
    // `.get(id).cloned()` moves the `serde_json::Value` (which can
    // carry a deeply-nested tree of `String` / `Value::Array`
    // allocations) out of the map by ownership, eliminating an
    // entire pass of recursive value cloning. Duplicate ids in the
    // input resolve to `None` on the second lookup, matching the
    // previous "skip on miss" behavior for repeated ids.
    Ok(ids.iter().filter_map(|id| task_map.remove(id)).collect())
}

/// Fetch multiple tasks by ID, silently skipping any that no longer exist.
///
/// Does NOT filter `archived_at` — daily-review reads (and other
/// surfaces that intentionally preserve historical pins to
/// since-archived tasks per issue #2971-H2) need the unfiltered
/// version. For forward-looking surfaces (current focus, schedule
/// blocks rendered as task cards) use
/// [`fetch_existing_active_tasks_json`] so a task archived after it
/// was pinned does not render as a ghost row.
pub(crate) fn fetch_existing_tasks_json(
    conn: &rusqlite::Connection,
    ids: &[String],
) -> Result<Vec<serde_json::Value>, McpError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let tasks = query_enriched_tasks_by_ids(conn, ids, /* only_active = */ false)?;
    reorder_tasks_to_request_order(tasks, ids, "fetch_existing_tasks_json")
}

/// Fetch multiple tasks by ID, silently skipping any that are missing
/// OR archived (`archived_at IS NOT NULL`).
///
/// defense-in-depth for the focus read path. Even with
/// the #2888/#2971-H1 write-side gates in place, an active task that
/// was added to current focus can be archived AFTER the focus was
/// written, leaving a stale pin.
/// rendered the archived row as a ghost (every other read path filters
/// `archived_at IS NULL`, so the assistant got a row whose fields
/// disagreed with `get_task` for the same id). Filtering at the read
/// boundary keeps the focus surface internally consistent without
/// touching the link table — the pin remains intact for sync
/// reconciliation (the sync apply pipeline still sees the soft
/// reference) and re-emerges automatically if the task is restored.
///
/// Daily review and other surfaces that intentionally preserve pins to
/// since-archived tasks (per #2971-H2 policy) must keep using
/// [`fetch_existing_tasks_json`].
pub(crate) fn fetch_existing_active_tasks_json(
    conn: &rusqlite::Connection,
    ids: &[String],
) -> Result<Vec<serde_json::Value>, McpError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let tasks = query_enriched_tasks_by_ids(conn, ids, /* only_active = */ true)?;
    reorder_tasks_to_request_order(tasks, ids, "fetch_existing_active_tasks_json")
}

/// Shared SELECT + enrichment for the three `fetch_*_tasks_json` helpers.
///
/// Routes through [`crate::json_row::query_all_as_json`] (which already
/// uses `prepare_cached`) and binds `ids` via `params_from_iter` so the
/// per-id `Vec<&dyn ToSql>` allocation that lived in three byte-isomorphic
/// copies is gone. `only_active` injects the `archived_at IS NULL`
/// predicate the focus surface needs without forking the SQL string into
/// a separate copy.
fn query_enriched_tasks_by_ids(
    conn: &rusqlite::Connection,
    ids: &[String],
    only_active: bool,
) -> Result<Vec<serde_json::Value>, McpError> {
    let placeholders = lorvex_domain::sql_csv_placeholders(ids.len());
    let archived_filter = if only_active {
        "archived_at IS NULL AND "
    } else {
        ""
    };
    let sql = format!("SELECT * FROM tasks WHERE {archived_filter}id IN ({placeholders})");
    let mut tasks =
        crate::json_row::query_all_as_json(conn, &sql, rusqlite::params_from_iter(ids.iter()))?;
    enrich_tasks_for_response(conn, &mut tasks)?;
    Ok(tasks)
}

/// Drop the rows from `tasks` into a HashMap keyed on `id`, then yield
/// them back in `requested_ids` order, silently skipping ids the DB
/// did not return.
///
/// Callers that error on missing ids (`fetch_tasks_json_batch`) handle
/// the partial-miss check before invoking this — by the time we reach
/// it we know `tasks.len() == requested_ids.len()`.
///
/// `task_map.remove(id)` instead of `.get(id).cloned()`
/// moves the `serde_json::Value` (which can carry a deeply-nested
/// tree of `String` / `Value::Array` allocations) out of the map by
/// ownership, eliminating an entire pass of recursive value cloning.
/// Each task in `requested_ids` appears at most once (UUIDv7 ids are
/// unique by construction), so removing on hit is safe — a duplicate
/// id would resolve to `None` on the second look-up and silently drop
/// the second slot, which matches the previous "return in request
/// order, skip on miss" behavior for repeated ids.
fn reorder_tasks_to_request_order(
    tasks: Vec<serde_json::Value>,
    requested_ids: &[String],
    context: &'static str,
) -> Result<Vec<serde_json::Value>, McpError> {
    let mut task_map: std::collections::HashMap<String, serde_json::Value> =
        std::collections::HashMap::with_capacity(tasks.len());
    for task in tasks {
        let id = required_task_id(&task, context)?.to_string();
        task_map.insert(id, task);
    }
    Ok(requested_ids
        .iter()
        .filter_map(|id| task_map.remove(id))
        .collect())
}
