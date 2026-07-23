//! List CRUD and the bulk task-to-list move.
//!
//! `lists` are the user's top-level grouping for tasks. The CLI
//! surface is small but the rules matter: deletion is gated on (a) at
//! least one other list existing — task creation needs a default
//! parent — and (b) the list having no assigned tasks. Moving tasks
//! into a list now runs through the shared mutation executor so row
//! writes, outbox envelopes, and audit rows share one HLC session.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_LIST, ENTITY_TASK, STATUS_CANCELLED};
use lorvex_domain::ListId;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::task::write::{self, TaskUpdatePatch};
use lorvex_store::repositories::{list_repo, task::read};
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_delete};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::commands::shared::{
    execute_cli_mutation_with_finalizer, load_task_row, log_cli_changelog_with_state,
};
use crate::hlc_guard::lock_shared;
use crate::models::TaskSummary;
use crate::render::task_row_to_summary;

fn enqueue_list_row_delete(
    conn: &Connection,
    device_id: &str,
    list_id: &str,
    payload: &Value,
    version: &str,
) -> Result<(), crate::error::CliError> {
    enqueue_payload_delete(
        conn,
        ENTITY_LIST,
        list_id,
        payload,
        crate::commands::shared::bare_outbox_ctx(version, device_id),
    )?;
    Ok(())
}

struct CreateCliListMutation<'a> {
    list_id: &'a ListId,
    name: &'a str,
    color: Option<&'a str>,
    icon: Option<&'a str>,
    description: Option<&'a str>,
}

impl<'a> Mutation for CreateCliListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let list = list_repo::create_list(
            conn,
            self.list_id,
            self.name,
            self.color,
            self.icon,
            self.description,
            &version,
        )?;
        Ok(MutationOutput::new(
            lorvex_store::payload_loaders::list_payload(&list),
            format!("Created list: {}", self.name),
        ))
    }
}

struct UpdateCliListMutation<'a> {
    list_id: &'a ListId,
    patch: list_repo::ListUpdatePatch<'a>,
    now: &'a str,
    before_json: Value,
}

impl<'a> Mutation for UpdateCliListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        list_repo::update_list_patched(conn, self.list_id, &self.patch, &version, self.now)?;
        let list =
            list_repo::get_list(conn, self.list_id)?.ok_or_else(|| StoreError::NotFound {
                entity: ENTITY_LIST,
                id: self.list_id.as_str().to_string(),
            })?;
        Ok(MutationOutput::new(
            lorvex_store::payload_loaders::list_payload(&list),
            format!("Updated list: {}", list.name),
        ))
    }
}

struct DeleteCliListMutation<'a> {
    list_id: &'a str,
    before_json: Value,
}

impl<'a> Mutation for DeleteCliListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "delete"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let list_id_typed = ListId::from_trusted(self.list_id.to_string());
        let deleted = list_repo::delete_list_lww(conn, &list_id_typed, &version)?;
        if deleted == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_LIST,
                id: self.list_id.to_string(),
            });
        }
        Ok(MutationOutput::new(
            json!({
                "id": self.list_id,
                "delete_version": version,
            }),
            format!("Deleted list: {}", self.list_id),
        ))
    }
}

struct MoveTasksToListMutation<'a> {
    list_id: &'a str,
    task_ids: &'a [String],
    now: &'a str,
}

impl<'a> Mutation for MoveTasksToListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "move"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut moved_snapshots = Vec::new();
        for task_id in self.task_ids {
            let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
            let task =
                read::get_task(conn, &task_id_typed)?.ok_or_else(|| StoreError::NotFound {
                    entity: ENTITY_TASK,
                    id: task_id.clone(),
                })?;
            if task.core().status() == STATUS_CANCELLED || task.core().list_id() == self.list_id {
                continue;
            }

            let before_json = serde_json::to_value(&task)?;
            let version = hlc.next_version().to_string();
            let patch = TaskUpdatePatch {
                task_id,
                list_id: lorvex_domain::Patch::Set(self.list_id),
                version: &version,
                now: self.now,
                before_status: Some(write::parse_task_status_for_update(
                    task_id,
                    task.core().status(),
                )?),
                ..Default::default()
            };
            write::apply_task_update(conn, &patch)?;
            let moved =
                read::get_task(conn, &task_id_typed)?.ok_or_else(|| StoreError::NotFound {
                    entity: ENTITY_TASK,
                    id: task_id.clone(),
                })?;
            moved_snapshots.push(json!({
                "task_id": task_id,
                "before": before_json,
                "after": serde_json::to_value(&moved)?,
            }));
        }

        Ok(MutationOutput::new(
            json!({
                "list_id": self.list_id,
                "moved": moved_snapshots,
            }),
            format!(
                "Moved {} task(s) to list {}",
                self.task_ids.len(),
                self.list_id
            ),
        ))
    }
}

pub(crate) fn create_list_with_conn(
    conn: &mut Connection,
    name: &str,
    color: Option<&str>,
    icon: Option<&str>,
    description: Option<&str>,
) -> Result<list_repo::ListRow, crate::error::CliError> {
    // sanitize free-text user input before validation
    // and before persistence. Without this, RLO / ZWSP / control
    // codepoints in CLI args land verbatim in `lists.{name,description}`
    // and propagate via sync to every peer. The trim happens after
    // sanitize because `sanitize_user_text` preserves CR/LF and we
    // want trimmed-of-whitespace post-NFC.
    let sanitized_name = lorvex_domain::sanitize_user_text(name);
    let normalized_name = sanitized_name.trim();
    if normalized_name.is_empty() {
        return Err(crate::error::CliError::Validation(
            "list name must not be empty".to_string(),
        ));
    }
    lorvex_domain::validation::validate_title(normalized_name)?;
    let sanitized_description = description.map(lorvex_domain::sanitize_user_text);
    if let Some(desc) = sanitized_description.as_deref() {
        lorvex_domain::validation::validate_body(desc)?;
    }
    let sanitized_color = color.map(lorvex_domain::sanitize_user_text);
    let sanitized_icon = icon.map(lorvex_domain::sanitize_user_text);

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let list_id = ListId::from_trusted(lorvex_domain::new_entity_id_string());
    let mutation = CreateCliListMutation {
        list_id: &list_id,
        name: normalized_name,
        color: sanitized_color.as_deref(),
        icon: sanitized_icon.as_deref(),
        description: sanitized_description.as_deref(),
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                &tx,
                execution.entity_kind,
                list_id.as_str(),
                hlc_state,
                &device_id,
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: list_id.as_str(),
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let list = list_repo::get_list(&tx, &list_id)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!(
            "list '{}' not found after create",
            list_id.as_str()
        ))
    })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(list)
}

pub(crate) fn update_list_with_conn(
    conn: &mut Connection,
    list_id: &str,
    name: Option<&str>,
    // each nullable field is `Patch<&str>` matching the underlying
    // `ListUpdatePatch` tri-state. `Unset` skips, `Clear` clears,
    // `Set(v)` sets.
    color: lorvex_domain::Patch<&str>,
    icon: lorvex_domain::Patch<&str>,
    description: lorvex_domain::Patch<&str>,
    ai_notes: lorvex_domain::Patch<&str>,
) -> Result<list_repo::ListRow, crate::error::CliError> {
    // sanitize before validation, identical discipline
    // as `create_list_with_conn`. Sanitize-then-trim-then-length so a
    // megabyte description doesn't ride sync to peers and an
    // RLO-spoofed name can't shadow another list visually.
    let sanitized_name_owned = name.map(lorvex_domain::sanitize_user_text);
    let normalized_name = sanitized_name_owned.as_deref().map(str::trim);
    if let Some(value) = normalized_name {
        if value.is_empty() {
            return Err(crate::error::CliError::Validation(
                "list name must not be empty".to_string(),
            ));
        }
        lorvex_domain::validation::validate_title(value)?;
    }
    let sanitized_description: lorvex_domain::Patch<String> =
        description.map(lorvex_domain::sanitize_user_text);
    if let lorvex_domain::Patch::Set(desc) = &sanitized_description {
        lorvex_domain::validation::validate_body(desc)?;
    }
    let sanitized_color: lorvex_domain::Patch<String> =
        color.map(lorvex_domain::sanitize_user_text);
    let sanitized_icon: lorvex_domain::Patch<String> = icon.map(lorvex_domain::sanitize_user_text);
    let sanitized_ai_notes: lorvex_domain::Patch<String> =
        ai_notes.map(lorvex_domain::sanitize_user_text);
    if let lorvex_domain::Patch::Set(notes) = &sanitized_ai_notes {
        lorvex_domain::validation::validate_body(notes)?;
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let list_id_typed = ListId::from_trusted(list_id.to_string());
    let existing = list_repo::get_list(&tx, &list_id_typed)?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("list '{list_id}' not found")))?;
    let now = lorvex_domain::sync_timestamp_now();
    let patch = list_repo::ListUpdatePatch {
        name: normalized_name,
        color: sanitized_color.as_deref(),
        icon: sanitized_icon.as_deref(),
        description: sanitized_description.as_deref(),
        ai_notes: sanitized_ai_notes.as_deref(),
    };
    // thread pre/post snapshots so the audit row
    // captures exactly what changed.
    let before_json = lorvex_store::payload_loaders::list_payload(&existing);
    let mutation = UpdateCliListMutation {
        list_id: &list_id_typed,
        patch,
        now: &now,
        before_json,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(&tx, execution.entity_kind, list_id, hlc_state, &device_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: list_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let list = list_repo::get_list(&tx, &list_id_typed)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("list '{list_id}' not found after update"))
    })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(list)
}

/// Permanently delete `list_id` and return the **full pre-delete
/// `ListRow` snapshot** so the CLI command layer can ship the
/// canonical `delete` envelope (`{action, db_path, deleted: <row>}`)
/// — symmetric with `delete_calendar_event_with_conn` /
/// `permanent_delete_task_with_conn` (#2905 M6).
pub(crate) fn delete_list_with_conn(
    conn: &mut Connection,
    list_id: &str,
) -> Result<list_repo::ListRow, crate::error::CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let list_id_typed = ListId::from_trusted(list_id.to_string());
    let list = list_repo::get_list(&tx, &list_id_typed)?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("list '{list_id}' not found")))?;
    let total_lists: i64 = tx.query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))?;
    if total_lists <= 1 {
        return Err(crate::error::CliError::Validation(
            "cannot delete the last list; at least one list must exist for task creation"
                .to_string(),
        ));
    }
    let assigned_task_count = list_repo::count_assigned_tasks_in_list(&tx, &list_id_typed)?;
    if assigned_task_count > 0 {
        return Err(crate::error::CliError::Validation(format!(
            "cannot delete list '{}' while {} task(s) are still assigned; reassign or permanently delete those tasks first",
            list.name, assigned_task_count
        )));
    }
    // Ship the full canonical pre-delete row so peers can reconstruct the
    // deleted list, including sync-owned fields the CLI display row omits.
    let before_json =
        lorvex_sync::outbox_enqueue::read_entity_payload_snapshot(&tx, ENTITY_LIST, list_id)?;
    let mutation = DeleteCliListMutation {
        list_id,
        before_json: before_json.clone(),
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let delete_version = execution
                .output
                .after
                .get("delete_version")
                .and_then(Value::as_str)
                .expect("Mutation contract: delete_list must surface delete_version");
            enqueue_list_row_delete(&tx, &device_id, list_id, &before_json, delete_version)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: list_id,
                    summary: &format!("Deleted list: {}", list.name),
                    before_json: execution.before,
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(list)
}

pub(crate) fn move_tasks_to_list_with_conn(
    conn: &mut Connection,
    list_id: &str,
    task_ids: &[String],
) -> Result<Vec<TaskSummary>, crate::error::CliError> {
    if task_ids.is_empty() {
        return Err(crate::error::CliError::Validation(
            "move requires at least one task id".to_string(),
        ));
    }
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let list_id_typed = ListId::from_trusted(list_id.to_string());
    list_repo::get_list(&tx, &list_id_typed)?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("list '{list_id}' not found")))?;
    let now = lorvex_domain::sync_timestamp_now();
    for task_id in task_ids {
        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
        load_task_row(&tx, &task_id_typed)?;
    }

    let mutation = MoveTasksToListMutation {
        list_id,
        task_ids,
        now: &now,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let moved_snapshots = execution
                .output
                .after
                .get("moved")
                .and_then(Value::as_array)
                .expect("Mutation contract: move_tasks_to_list must surface moved snapshots");
            for snapshot in moved_snapshots {
                let task_id = snapshot
                    .get("task_id")
                    .and_then(Value::as_str)
                    .expect("Mutation contract: moved snapshot must surface task_id");
                let before_json = snapshot
                    .get("before")
                    .cloned()
                    .expect("Mutation contract: moved snapshot must surface before");
                let after_json = snapshot
                    .get("after")
                    .cloned()
                    .expect("Mutation contract: moved snapshot must surface after");
                enqueue_entity_upsert(&tx, ENTITY_TASK, task_id, hlc_state, &device_id)?;
                log_cli_changelog_with_state(
                    &tx,
                    hlc_state,
                    crate::commands::shared::CliChangelogParams {
                        operation: execution.operation,
                        entity_type: execution.entity_kind,
                        entity_id: task_id,
                        summary: &format!("Moved task to list {list_id}"),
                        before_json: Some(before_json),
                        after_json: Some(after_json),
                    },
                )?;
            }
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;

    let mut summaries = Vec::new();
    for task_id in task_ids {
        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
        let task = load_task_row(&tx, &task_id_typed)?;
        if task.core().status() == STATUS_CANCELLED {
            continue;
        }
        summaries.push(task_row_to_summary(task));
    }
    drop(hlc_guard);
    tx.commit()?;
    Ok(summaries)
}
