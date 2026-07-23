use crate::contract::{SaveFocusScheduleArgs, ScheduleBlockType, MAX_BRIEFING_LENGTH};
use crate::error::McpError;
use crate::focus::current::enrich_current_focus_row;
use crate::focus::schedule::shared::{materialize_blocks, normalize_focus_schedule_row};
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{resolve_optional_date, utc_now_iso};
use crate::system::vec_limits::MAX_SCHEDULE_BLOCKS;
use crate::tasks::validation::validate_optional_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_PREFERENCE};
use lorvex_store::current_focus_items::{touch_current_focus_header, upsert_current_focus_header};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::timezone::anchored_timezone_name;
use rusqlite::{params_from_iter, Connection, OptionalExtension};
use serde_json::{json, Value};
use std::collections::HashSet;

fn mcp_error_to_store(error: McpError) -> StoreError {
    match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) => StoreError::Validation(message),
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    }
}

struct SaveFocusScheduleMutation {
    date: String,
    rationale: Option<String>,
    timezone: String,
    now: String,
    blocks_json: Vec<Value>,
    before: Option<Value>,
    task_blocks: usize,
}

impl Mutation for SaveFocusScheduleMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_FOCUS_SCHEDULE
    }

    fn operation(&self) -> &'static str {
        "focus_schedule"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        lorvex_store::focus_schedule_blocks::upsert_focus_schedule_header(
            conn,
            &self.date,
            self.rationale.as_deref(),
            &self.timezone,
            &version,
            &self.now,
        )?;
        materialize_blocks(conn, &self.date, &self.blocks_json).map_err(mcp_error_to_store)?;

        let saved = query_one_as_json(
            conn,
            "SELECT * FROM focus_schedule WHERE date = ?",
            [self.date.clone()],
        )
        .map_err(StoreError::from)?
        .ok_or_else(|| {
            StoreError::Invariant(format!("Failed to load focus schedule '{}'", self.date))
        })?;
        let normalized_saved =
            normalize_focus_schedule_row(conn, saved).map_err(mcp_error_to_store)?;

        Ok(MutationOutput::new(
            normalized_saved,
            format!(
                "Saved focus schedule for {} with {} task blocks",
                self.date, self.task_blocks
            ),
        ))
    }
}

struct ApplyScheduleToCurrentFocusMutation {
    date: String,
    applied: Vec<String>,
    timezone: String,
    now: String,
    before: Option<Value>,
    effective_briefing: Option<String>,
}

impl Mutation for ApplyScheduleToCurrentFocusMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CURRENT_FOCUS
    }

    fn operation(&self) -> &'static str {
        if self.before.is_some() {
            "update"
        } else {
            "create"
        }
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        if self.before.is_some() {
            touch_current_focus_header(conn, &self.date, Some(&version), &self.now)?;
        } else {
            upsert_current_focus_header(
                conn,
                &self.date,
                self.effective_briefing.as_deref(),
                &self.timezone,
                &version,
                &self.now,
            )?;
        }

        lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
            conn,
            &self.date,
            &self.applied,
            &version,
            &self.now,
        )?;

        let plan_after = query_one_as_json(
            conn,
            "SELECT * FROM current_focus WHERE date = ?",
            [self.date.clone()],
        )
        .map_err(StoreError::from)?
        .ok_or_else(|| StoreError::Invariant("current_focus disappeared after save".to_string()))?;
        let plan_after = enrich_current_focus_row(conn, plan_after).map_err(mcp_error_to_store)?;

        Ok(MutationOutput::new(
            plan_after,
            format!(
                "Applied focus schedule to current focus for {} with {} task(s)",
                self.date,
                self.applied.len()
            ),
        ))
    }
}

struct EnsureDashboardScheduleSectionMutation {
    before: Option<Value>,
    after: Value,
    raw: String,
    now: String,
}

impl Mutation for EnsureDashboardScheduleSectionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        lorvex_store::repositories::preference_repo::set_preference(
            conn,
            lorvex_domain::preference_keys::PREF_DASHBOARD_LAYOUT,
            &self.raw,
            &version,
            &self.now,
        )?;
        Ok(MutationOutput::new(
            self.after.clone(),
            "Inserted dashboard schedule section (auto, side effect of save_focus_schedule)",
        ))
    }
}

pub(crate) fn save_focus_schedule(
    conn: &Connection,
    args: SaveFocusScheduleArgs,
) -> Result<String, McpError> {
    // every MCP write tool runs under
    // `with_conn`, which already wraps the closure in
    // `BEGIN IMMEDIATE` + a `mcp_tool` SAVEPOINT (see `server.rs`
    // `with_conn`). The earlier inner `with_savepoint_mapped` here
    // nested a redundant savepoint inside that frame — it bought
    // nothing because the outer savepoint already covers atomic
    // rollback on any error returned from this function. Drop the
    // inner wrap so the call shape mirrors every other write tool
    // and we don't pay an extra savepoint per save.
    // #3029-M4: idempotency cache. Cf. `set_current_focus`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let SaveFocusScheduleArgs {
        date,
        blocks,
        rationale,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "save_focus_schedule",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    if blocks.is_empty() {
        return Err(McpError::Validation(
            "blocks must contain at least 1 item".to_string(),
        ));
    }
    if blocks.len() > MAX_SCHEDULE_BLOCKS {
        return Err(McpError::Validation(format!(
            "blocks exceeds maximum count ({} items, limit {MAX_SCHEDULE_BLOCKS})",
            blocks.len()
        )));
    }
    // scrub `rationale` BEFORE the length check so
    // a bidi-laden long string can't slip past the cap by truncating
    // itself off-boundary. Mirrors the daily-review free-text fields
    // (#2929-MM2).
    let rationale = rationale.map(|s| lorvex_domain::sanitize_user_text(&s));
    validate_optional_string_length(rationale.as_deref(), "rationale", MAX_BRIEFING_LENGTH)?;

    let date = resolve_optional_date(conn, date)?;
    let now = utc_now_iso();
    let timezone = anchored_timezone_name(conn)?;

    // capture the pre-save snapshot so the changelog can
    // diff. The aggregate root carries header columns + materialized
    // blocks; reuse the same normalize helper as the post-save path so
    // before/after share an identical shape.
    let before_json = query_one_as_json(
        conn,
        "SELECT * FROM focus_schedule WHERE date = ?",
        [date.clone()],
    )?
    .map(|row| normalize_focus_schedule_row(conn, row))
    .transpose()?;

    let blocks_json: Vec<serde_json::Value> = blocks
        .iter()
        .map(|b| {
            json!({
                "block_type": match b.block_type {
                    ScheduleBlockType::Task => "task",
                    ScheduleBlockType::Buffer => "buffer",
                },
                "task_id": b.task_id,
                "start_time": b.start_time,
                "end_time": b.end_time,
            })
        })
        .collect();
    let task_ids = task_block_ids_from_inputs(&blocks);
    lorvex_store::validate_task_ids_live(conn, &task_ids, "blocks[].task_id")?;

    let task_blocks = blocks
        .iter()
        .filter(|block| block.block_type == ScheduleBlockType::Task)
        .count();
    let mutation = SaveFocusScheduleMutation {
        date: date.clone(),
        rationale,
        timezone: timezone.clone(),
        now: now.clone(),
        blocks_json,
        before: before_json,
        task_blocks,
    };
    let output = execute_mcp_mutation(conn, &mutation, "save_focus_schedule", date.clone())?;

    // Apply task blocks to current_focus_items
    let task_ids_applied =
        apply_schedule_to_current_focus(conn, &date, &mutation.blocks_json, &timezone, &now)?;

    // Auto-activate the schedule section in the dashboard layout if absent
    ensure_dashboard_schedule_section(conn)?;

    // Build response including applied task info
    let mut response = output.after;
    if let Value::Object(ref mut obj) = response {
        obj.insert("task_ids_applied".to_string(), json!(task_ids_applied));
    }

    let response_str = serde_json::to_string(&response)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "save_focus_schedule",
        &request_repr,
        &response_str,
    )?;

    Ok(response_str)
}

/// Apply the schedule's task blocks to current_focus_items for the given date.
/// Returns the list of task IDs that were applied (existing tasks only).
fn apply_schedule_to_current_focus(
    conn: &Connection,
    date: &str,
    blocks: &[Value],
    timezone: &str,
    now: &str,
) -> Result<Vec<String>, McpError> {
    // Extract unique task IDs from task blocks
    let mut seen: HashSet<String> = HashSet::new();
    let mut task_ids: Vec<String> = Vec::new();
    for block in blocks {
        let block_type = block
            .get("block_type")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| {
                McpError::Validation("focus schedule block missing block_type".to_string())
            })?;
        if block_type != "task" {
            continue;
        }
        let task_id = block
            .get("task_id")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| {
                McpError::Validation("focus schedule task block missing task_id".to_string())
            })?
            .to_string();
        if seen.insert(task_id.clone()) {
            task_ids.push(task_id);
        }
    }

    // validate every task_id at the trust
    // boundary BEFORE writing.
    // phantom IDs via `WHERE id IN (...)`, so a hallucinated UUID rode
    // through `save_focus_schedule` without surfacing — the assistant
    // got a success response that quietly dropped the bogus block.
    //
    // route through `validate_task_ids_active`. The focus schedule is
    // a forward-looking plan, so an archived (trashed) task pinned
    // into a time
    // block is semantically equivalent to a phantom one — every task
    // read path filters `archived_at IS NULL`, so the block would
    // render as a ghost row the assistant cannot recover. Mirrors the
    // gate already in place at `set_current_focus` /
    // `add_to_current_focus` (#2888).
    lorvex_store::validate_task_ids_live(conn, &task_ids, "blocks[].task_id")?;

    // Re-check existence with the same single-IN-query shape so the
    // applied list preserves block order and dedupe semantics. After
    // the validation above this is guaranteed to match `task_ids`
    // verbatim, but we keep the lookup for clarity and to keep the
    // returned list anchored to rows that actually live in the DB.
    let applied: Vec<String> = if task_ids.is_empty() {
        Vec::new()
    } else {
        let placeholders = lorvex_domain::sql_csv_placeholders(task_ids.len());
        let sql = format!("SELECT id FROM tasks WHERE id IN ({placeholders})");
        let mut stmt = conn.prepare(&sql)?;
        let found: HashSet<String> = stmt
            .query_map(params_from_iter(task_ids.iter()), |row| {
                row.get::<_, String>(0)
            })?
            .collect::<Result<_, _>>()?;
        // Preserve the original block order; dedupe via HashSet above.
        task_ids
            .iter()
            .filter(|tid| found.contains(*tid))
            .cloned()
            .collect()
    };

    // Empty applied is valid (buffer-only schedule) — don't skip materialization.

    // Read before state for changelog
    let before_plan = query_one_as_json(
        conn,
        "SELECT * FROM current_focus WHERE date = ?",
        [date.to_string()],
    )?;
    let before_plan = match before_plan {
        Some(row) => Some(enrich_current_focus_row(conn, row)?),
        None => None,
    };

    // Preserve existing briefing when upserting the current focus
    let effective_briefing: Option<String> = before_plan
        .as_ref()
        .and_then(|plan| plan.get("briefing").and_then(Value::as_str))
        .map(str::to_string);

    let mutation = ApplyScheduleToCurrentFocusMutation {
        date: date.to_string(),
        applied: applied.clone(),
        timezone: timezone.to_string(),
        now: now.to_string(),
        before: before_plan,
        effective_briefing,
    };
    execute_mcp_mutation(conn, &mutation, "save_focus_schedule", date.to_string())?;

    Ok(applied)
}

fn task_block_ids_from_inputs(blocks: &[crate::contract::FocusScheduleBlockInput]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut task_ids = Vec::new();
    for block in blocks {
        if block.block_type == ScheduleBlockType::Task {
            if let Some(task_id) = block.task_id.as_ref() {
                if seen.insert(task_id.clone()) {
                    task_ids.push(task_id.clone());
                }
            }
        }
    }
    task_ids
}

fn default_dashboard_layout() -> serde_json::Value {
    serde_json::json!({
        "sections": [
            { "type": "ai_briefing" },
            { "type": "focus" },
            { "type": "habits" },
            { "type": "overdue_alert", "limit": 4 },
            { "type": "priority" },
            { "type": "recently_completed" }
        ],
        "updated_by": "ai"
    })
}

fn ensure_dashboard_schedule_section(conn: &Connection) -> Result<(), McpError> {
    // this helper writes `PREF_DASHBOARD_LAYOUT` as a
    // side effect of `save_focus_schedule`.
    // `enqueue_relation_sync` directly without `log_change`
    // — violating the CLAUDE.md "every MCP write logs to ai_changelog,
    // no exceptions" rule. The user could not see in the changelog
    // that their dashboard layout had been mutated by a side effect.
    // We now route the write through the canonical funnel below
    // (after the sync check confirms a write is needed) so the audit
    // trail is consistent with every other MCP write.
    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            rusqlite::params![lorvex_domain::preference_keys::PREF_DASHBOARD_LAYOUT],
            |row| row.get(0),
        )
        .optional()?;

    let mut layout = match raw.as_deref() {
        Some(raw) => {
            let parsed = serde_json::from_str::<serde_json::Value>(raw).map_err(|_| {
                McpError::Validation("dashboard_layout must be valid JSON".to_string())
            })?;
            if parsed.get("sections").and_then(|v| v.as_array()).is_some() {
                parsed
            } else {
                return Err(McpError::Validation(
                    "dashboard_layout sections missing".to_string(),
                ));
            }
        }
        None => default_dashboard_layout(),
    };
    let sections = layout
        .get_mut("sections")
        .and_then(|v| v.as_array_mut())
        .ok_or_else(|| McpError::Validation("dashboard_layout sections missing".to_string()))?;

    // Check if schedule section already exists
    let has_schedule = sections
        .iter()
        .any(|s| s.get("type").and_then(|v| v.as_str()) == Some("schedule"));
    if has_schedule {
        return Ok(());
    }

    // Insert schedule section after focus (or at index 1)
    let insert_at = sections
        .iter()
        .position(|s| s.get("type").and_then(|v| v.as_str()) == Some("focus"))
        .map_or(1, |i| i + 1)
        .min(sections.len());

    sections.insert(insert_at, serde_json::json!({ "type": "schedule" }));

    // Capture the pre-write payload so the changelog `before_json`
    // accurately reflects what the layout looked like before this
    // helper inserted the schedule section.
    let before_json: Option<Value> = raw
        .as_deref()
        .and_then(|raw| serde_json::from_str(raw).ok());
    let after_json = layout.clone();

    let new_raw = serde_json::to_string(&layout)?;
    let now = utc_now_iso();
    let mutation = EnsureDashboardScheduleSectionMutation {
        before: before_json,
        after: after_json,
        raw: new_raw,
        now,
    };
    execute_mcp_mutation(
        conn,
        &mutation,
        "save_focus_schedule",
        lorvex_domain::preference_keys::PREF_DASHBOARD_LAYOUT.to_string(),
    )?;
    Ok(())
}
