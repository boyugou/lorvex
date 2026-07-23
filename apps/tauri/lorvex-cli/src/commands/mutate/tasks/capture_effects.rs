//! Task capture path: the AI-first "create a task" entry point used by the
//! CLI `add`/`capture` commands. Validates the title, resolves the target
//! list (explicit `--list` flag → `default_list_id` preference → single-list
//! auto-pick), inserts the task row, and enqueues the outbox upserts +
//! tag edges. Sibling helpers in `super::tags` handle the tag normalization
//! and edge insertion.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TAG, ENTITY_TASK};
use lorvex_domain::Patch;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::list_repo;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_upsert};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;
use std::cell::RefCell;

use crate::hlc_guard::lock_shared;

use crate::commands::mutate::tags::effects as tags;
use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};

struct CreateCliCapturedTaskMutation {
    input: lorvex_workflow::task_create::CreateTaskInput,
    result: RefCell<Option<lorvex_workflow::task_create::CreateTaskResult>>,
}

impl Mutation for CreateCliCapturedTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = lorvex_workflow::task_create::create_task(conn, hlc, self.input.clone())?;
        let output = MutationOutput::new(result.task.clone(), result.summary.clone());
        self.result.replace(Some(result));
        Ok(output)
    }
}

fn flush_cli_capture_create_effects(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    result: &lorvex_workflow::task_create::CreateTaskResult,
) -> Result<(), crate::error::CliError> {
    for task_id in &result.sync_effects.task_upsert_ids {
        enqueue_entity_upsert(conn, ENTITY_TASK, task_id, hlc_state, device_id)?;
    }
    for tag_id in &result.sync_effects.tag_upsert_ids {
        enqueue_entity_upsert(conn, ENTITY_TAG, tag_id, hlc_state, device_id)?;
    }
    for edge_id in &result.sync_effects.task_tag_edge_upsert_ids {
        let (typed_task_id, typed_tag_id) = lorvex_domain::TaskTagEdgeId::try_parse(edge_id)
            .map_err(|err| crate::error::CliError::Internal(err.to_string()))?;
        let (edge_version, created_at): (String, String) = conn.query_row(
            "SELECT version, created_at FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
            rusqlite::params![typed_task_id.as_str(), typed_tag_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        let payload = lorvex_store::payload_loaders::task_tag_payload(
            &typed_task_id,
            &typed_tag_id,
            &edge_version,
            &created_at,
        );
        let outbox_version = hlc_state.generate().to_string();
        enqueue_payload_upsert(
            conn,
            EDGE_TASK_TAG,
            edge_id,
            &payload,
            crate::commands::shared::bare_outbox_ctx(&outbox_version, device_id),
        )?;
    }

    if !result.sync_effects.reminder_upsert_ids.is_empty()
        || !result.sync_effects.cancelled_reminder_ids.is_empty()
        || !result.sync_effects.dependency_edge_upsert_ids.is_empty()
        || !result.sync_effects.spawned_successors.is_empty()
        || !result.sync_effects.spawned_successor_tag_edges.is_empty()
        || !result
            .sync_effects
            .spawned_successor_checklist_item_ids
            .is_empty()
        || !result
            .sync_effects
            .spawned_successor_reminder_ids
            .is_empty()
        || !result.sync_effects.rewired_focus_schedule_dates.is_empty()
        || !result.sync_effects.rewired_current_focus_dates.is_empty()
        || !result.sync_effects.focus_rewire_audits.is_empty()
    {
        return Err(crate::error::CliError::Internal(
            "CLI task capture produced workflow side effects this surface does not enqueue"
                .to_string(),
        ));
    }

    Ok(())
}

#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct CaptureTaskOptions<'a> {
    pub(crate) list_id_override: Option<&'a str>,
    pub(crate) priority: Option<i64>,
    pub(crate) due_date: Option<&'a str>,
    pub(crate) planned_date: Option<&'a str>,
    pub(crate) estimated_minutes: Option<i64>,
    pub(crate) tags: Option<&'a [String]>,
}

/// Resolve the list ID for a capture command.
///
/// Priority: explicit `--list` flag > `default_list_id` preference > auto-select
/// if exactly one list exists > clear error listing available lists.
fn resolve_capture_list_id(
    conn: &Connection,
    explicit_list_id: Option<&str>,
) -> Result<String, crate::error::CliError> {
    // 1. If --list is provided, validate and use it
    if let Some(list_id) = explicit_list_id {
        let exists = list_repo::get_list(
            conn,
            &lorvex_domain::ListId::from_trusted(list_id.to_string()),
        )?;
        if exists.is_none() {
            return Err(crate::error::CliError::NotFound(format!(
                "list '{list_id}' not found"
            )));
        }
        return Ok(list_id.to_string());
    }

    // 2. Try default_list_id preference (via the store's resolver).
    // previously, ANY store error here collapsed into
    //    single-list auto-pick, silently hiding a dangling preference
    //    ("default_list_id points at a list that was deleted"). App and
    //    MCP correctly surface that error. Split the two failure modes:
    //      * "default_list_id does not reference an existing list" →
    //        propagate so the user can fix their preference.
    //      * "Task creation requires a real list..." (no preference at
    //        all) → fall through to single-list auto-pick.
    match lorvex_store::resolve_required_task_list_id(conn, None) {
        Ok(list_id) => return Ok(list_id),
        Err(err) => {
            let message = err.to_string();
            if message.contains("does not reference an existing list") {
                return Err(crate::error::CliError::NotFound(message));
            }
            // Preference absent — fall through to single-list auto-pick.
        }
    }

    // 3. Auto-select if exactly one list exists
    let all_lists = list_repo::get_all_lists(conn)?;
    match all_lists.len() {
        0 => Err(crate::error::CliError::NotFound(
            "no lists exist; create a list first with 'lorvex list create <name>'".to_string(),
        )),
        1 => Ok(all_lists[0].id.clone()),
        _ => {
            let names: Vec<String> = all_lists
                .iter()
                .map(|l| format!("  {} ({})", l.name, l.id))
                .collect();
            Err(crate::error::CliError::Validation(format!(
                "multiple lists exist but no default is configured. Use --list <id> or set default_list_id.\nAvailable lists:\n{}",
                names.join("\n")
            )))
        }
    }
}

pub(crate) fn create_captured_task_with_conn(
    conn: &mut Connection,
    title: &str,
    options: CaptureTaskOptions<'_>,
) -> Result<String, crate::error::CliError> {
    // parity with `update_task_with_conn` — sanitize
    // free-text BEFORE validating.
    // and length-checked; bidi overrides / zero-width / null bytes
    // landed verbatim in `tasks.title`. A subsequent `update title=...`
    // sanitized the same text and the row's title silently changed —
    // looks like a content edit triggered by an unrelated update.
    let sanitized = lorvex_domain::sanitize_user_text(title);
    let normalized_title = sanitized.trim();
    if normalized_title.is_empty() {
        return Err(crate::error::CliError::Validation(
            "task title must not be empty".to_string(),
        ));
    }
    // parity with the MCP + Tauri paths.
    // CLI accepted unbounded titles, so a pasted log or
    // `$(cat bigfile)` argument created a multi-MB title that then
    // synced everywhere and poisoned the row for MCP/Tauri callers
    // whose defense-in-depth length checks would reject future
    // updates.
    lorvex_domain::validation::validate_title(normalized_title)?;
    if let Some(priority) = options.priority {
        lorvex_domain::validation::validate_priority(priority)?;
    }
    if let Some(due_date) = options.due_date {
        lorvex_domain::validation::validate_date_format(due_date)?;
    }
    if let Some(planned_date) = options.planned_date {
        lorvex_domain::validation::validate_date_format(planned_date)?;
    }
    if let Some(estimated_minutes) = options.estimated_minutes {
        lorvex_domain::validation::validate_estimated_minutes(estimated_minutes)?;
    }
    let tags = tags::normalize_capture_tags(options.tags)?;

    let task_id = lorvex_domain::new_entity_id_string();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let resolved_list_id = resolve_capture_list_id(&tx, options.list_id_override)?;
    let priority = options
        .priority
        .map(u8::try_from)
        .transpose()
        .map_err(|error| crate::error::CliError::Validation(error.to_string()))?;
    let estimated_minutes = options
        .estimated_minutes
        .map(u32::try_from)
        .transpose()
        .map_err(|error| crate::error::CliError::Validation(error.to_string()))?;
    fn lift<T>(value: Option<T>) -> Patch<T> {
        match value {
            None => Patch::Unset,
            Some(v) => Patch::Set(v),
        }
    }
    let task_input = lorvex_workflow::task_create::TaskCreateInput {
        title: normalized_title.to_string(),
        list_id: Patch::Set(resolved_list_id),
        priority: lift(priority),
        due_date: lift(options.due_date.map(str::to_string)),
        due_time: Patch::Unset,
        estimated_minutes: lift(estimated_minutes),
        tags: (!tags.is_empty()).then_some(tags),
        body: Patch::Unset,
        raw_input: Patch::Unset,
        ai_notes: Patch::Unset,
        depends_on: None,
        reminders: None,
        recurrence_json: Patch::Unset,
        planned_date: lift(options.planned_date.map(str::to_string)),
        completed: None,
        status: Patch::Unset,
    };
    let mutation = CreateCliCapturedTaskMutation {
        input: lorvex_workflow::task_create::CreateTaskInput {
            id: Some(task_id.clone()),
            task: task_input,
            include_advice: false,
        },
        result: RefCell::new(None),
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            {
                let result_ref = mutation.result.borrow();
                let result = result_ref
                    .as_ref()
                    .expect("Mutation contract: CLI task capture result staged by apply");
                flush_cli_capture_create_effects(&tx, hlc_state, &device_id, result)?;
            }
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &task_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;

    Ok(task_id)
}
