//! List-level mutations that aren't part of the structured task-write
//! batch surface — `reorganize_list` (re-sort by a strategy) and
//! `permanent_delete_task` (irreversible cascade after trash).

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::{hlc_session::HlcSession, naming::ENTITY_LIST};
use lorvex_runtime::resolve_db_path;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use lorvex_workflow::list_reorganize::{self, ReorganizeListInput, ReorganizeListStrategy};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_permanent_delete::{
    self, PermanentDeleteTaskInput, PermanentDeleteTaskResult,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

use crate::cli::OutputFormat;
use crate::commands::shared::{
    bare_outbox_ctx, execute_cli_mutation_with_finalizer, log_cli_changelog_with_state,
    CliChangelogParams,
};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::render_mutation_response;

struct ReorganizeListCliMutation {
    input: ReorganizeListInput,
    before_json: Value,
    result: RefCell<Option<list_reorganize::ReorganizeListResult>>,
}

impl ReorganizeListCliMutation {
    fn new(input: ReorganizeListInput) -> Self {
        let before_json = json!({
            "list_id": input.list_id.as_str(),
            "strategy": input.strategy.as_str(),
        });
        Self {
            input,
            before_json,
            result: RefCell::new(None),
        }
    }
}

impl Mutation for ReorganizeListCliMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let result = list_reorganize::reorganize_list(conn, self.input.clone())?;
        let output = MutationOutput::new(result.after_json.clone(), result.summary.clone());
        self.result.replace(Some(result));
        Ok(output)
    }
}

struct PermanentDeleteWorkflowCliMutation {
    input: PermanentDeleteTaskInput,
    result: RefCell<Option<PermanentDeleteTaskResult>>,
}

impl Mutation for PermanentDeleteWorkflowCliMutation {
    fn entity_kind(&self) -> &'static str {
        lorvex_domain::naming::ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "permanent_delete"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        let task_id = self.input.task_id.to_string();
        let before = lorvex_store::repositories::task::read::get_task(conn, &self.input.task_id)?
            .ok_or_else(|| StoreError::NotFound {
            entity: lorvex_domain::naming::ENTITY_TASK,
            id: task_id,
        })?;
        Ok(Some(serde_json::to_value(&before)?))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = task_permanent_delete::permanent_delete_task(conn, hlc, self.input.clone())?;
        let output = MutationOutput::new(result.payload.clone(), result.summary.clone());
        self.result.replace(Some(result));
        Ok(output)
    }
}

pub(crate) fn run_reorganize_list(
    list_id: &str,
    strategy: &str,
    task_ids: &[String],
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let strategy = parse_reorganize_strategy(strategy)?;
    let input = ReorganizeListInput {
        list_id: list_id.to_string(),
        strategy,
        task_ids: (!task_ids.is_empty()).then(|| task_ids.to_vec()),
    };
    let result = if dry_run {
        list_reorganize::reorganize_list(&conn, input)?
    } else {
        let mutation = ReorganizeListCliMutation::new(input);
        lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
            let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
            execute_cli_mutation_with_finalizer(
                conn,
                &mut hlc_guard,
                &mutation,
                CliError::from,
                |execution, hlc_state| {
                    log_cli_changelog_with_state(
                        conn,
                        hlc_state,
                        CliChangelogParams {
                            operation: execution.operation,
                            entity_type: execution.entity_kind,
                            entity_id: &mutation.input.list_id,
                            summary: &execution.output.summary,
                            before_json: execution.before,
                            after_json: Some(execution.output.after),
                        },
                    )?;
                    lorvex_runtime::bump_local_change_seq(conn)?;
                    Ok(())
                },
            )?;
            drop(hlc_guard);
            Ok::<_, CliError>(
                mutation
                    .result
                    .take()
                    .expect("Mutation contract: reorganize result staged by apply"),
            )
        })?
    };
    let raw = serde_json::to_string(&result.payload)?;
    render_mutation_response(
        "list.reorganize",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload, "dry_run": dry_run }),
    )
}

fn parse_reorganize_strategy(raw: &str) -> Result<ReorganizeListStrategy, CliError> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "deadline" => Ok(ReorganizeListStrategy::Deadline),
        "priority" => Ok(ReorganizeListStrategy::Priority),
        "manual" => Ok(ReorganizeListStrategy::Manual),
        _ => Err(CliError::Validation(
            "strategy must be one of priority, deadline, manual".to_string(),
        )),
    }
}

pub(crate) fn run_permanent_delete(
    task_id: &str,
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = lorvex_domain::TaskId::parse(task_id)?;
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let result = if dry_run {
        lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
            let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
            let result = {
                let handle = CliHlcStateHandle::new(&mut hlc_guard);
                let session = HlcSession::new(&handle);
                lorvex_store::with_savepoint_then_rollback(
                    conn,
                    "cli_permanent_delete_dry_run",
                    |conn| {
                        task_permanent_delete::permanent_delete_task(
                            conn,
                            &session,
                            PermanentDeleteTaskInput { task_id },
                        )
                    },
                )?
            };
            Ok::<_, CliError>(with_dry_run_flag(result))
        })?
    } else {
        run_permanent_delete_workflow(&conn, PermanentDeleteTaskInput { task_id })?
    };
    let raw = serde_json::to_string(&result.payload)?;
    render_mutation_response(
        "task.permanent_delete",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload, "dry_run": dry_run }),
    )
}

fn with_dry_run_flag(mut result: PermanentDeleteTaskResult) -> PermanentDeleteTaskResult {
    match &mut result.payload {
        Value::Object(object) => {
            object.insert("dry_run".to_string(), Value::Bool(true));
        }
        other => {
            result.payload = json!({ "dry_run": true, "preview": other });
        }
    }
    result
}

fn run_permanent_delete_workflow(
    conn: &Connection,
    input: PermanentDeleteTaskInput,
) -> Result<PermanentDeleteTaskResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mutation = PermanentDeleteWorkflowCliMutation {
            input,
            result: RefCell::new(None),
        };
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        execute_cli_mutation_with_finalizer(
            conn,
            &mut hlc_guard,
            &mutation,
            CliError::from,
            |execution, hlc_state| {
                let result_ref = mutation.result.borrow();
                let result = result_ref
                    .as_ref()
                    .expect("Mutation contract: permanent delete result staged by apply");
                for change in &result.delete_syncs {
                    let version = hlc_state.generate().to_string();
                    enqueue_payload_delete(
                        conn,
                        change.entity_type,
                        &change.entity_id,
                        &change.payload,
                        bare_outbox_ctx(&version, &device_id),
                    )?;
                }
                for date in &result.focus_parent_dates.current_focus {
                    enqueue_aggregate_root_upsert_if_present(
                        conn,
                        hlc_state,
                        &device_id,
                        lorvex_domain::naming::ENTITY_CURRENT_FOCUS,
                        date,
                    )?;
                }
                for date in &result.focus_parent_dates.focus_schedule {
                    enqueue_aggregate_root_upsert_if_present(
                        conn,
                        hlc_state,
                        &device_id,
                        lorvex_domain::naming::ENTITY_FOCUS_SCHEDULE,
                        date,
                    )?;
                }
                if result.deleted {
                    log_cli_changelog_with_state(
                        conn,
                        hlc_state,
                        CliChangelogParams {
                            operation: execution.operation,
                            entity_type: execution.entity_kind,
                            entity_id: &result.task_id,
                            summary: &execution.output.summary,
                            before_json: execution.before,
                            after_json: None,
                        },
                    )?;
                    lorvex_runtime::bump_local_change_seq(conn)?;
                }
                Ok(())
            },
        )?;
        drop(hlc_guard);
        Ok::<_, CliError>(
            mutation
                .result
                .take()
                .expect("Mutation contract: permanent delete result staged by apply"),
        )
    })
}

fn enqueue_aggregate_root_upsert_if_present(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    entity_type: &'static str,
    entity_id: &str,
) -> Result<(), CliError> {
    let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        entity_type,
        entity_id,
    )?
    else {
        return Ok(());
    };
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}
