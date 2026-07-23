use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::{TAG_RENAME_RESPONSE, TAG_RENAME_SYNC_ACTIONS};
use rusqlite::OptionalExtension;
use serde_json::Value;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct TagRenameResult {
    pub(crate) old_name: String,
    pub(crate) new_name: String,
    pub(crate) tasks_updated: usize,
    pub(crate) task_ids: Vec<String>,
}

struct RenameCliTagMutation {
    old_tag_id: String,
    conflict_tag_id: Option<String>,
    survivor_tag_id: String,
    old_display_name: String,
    new_display_name: String,
    task_ids: Vec<String>,
    old_tag_payload: Value,
    audit_before: Value,
    now: String,
}

impl Mutation for RenameCliTagMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TAG
    }

    fn operation(&self) -> &'static str {
        "rename_tag"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.audit_before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        bump_renamed_tag_tasks(conn, hlc, &self.task_ids, &self.now)?;

        let mut sync_actions = if let Some(conflict_tag_id) = self.conflict_tag_id.as_deref() {
            apply_cli_tag_merge(
                conn,
                hlc,
                &self.old_tag_id,
                conflict_tag_id,
                &self.task_ids,
                &self.old_tag_payload,
                &self.now,
            )?
        } else {
            let version = hlc.next_version_string();
            let old_tag_id = lorvex_domain::TagId::from_trusted(self.old_tag_id.clone());
            tag_repo::rename_tag(
                conn,
                &old_tag_id,
                &self.new_display_name,
                &version,
                &self.now,
            )?;
            vec![RenameCliTagSyncAction::upsert(
                ENTITY_TAG,
                self.old_tag_id.clone(),
                None,
            )]
        };

        sync_actions.extend(
            self.task_ids
                .iter()
                .cloned()
                .map(|task_id| RenameCliTagSyncAction::upsert(ENTITY_TASK, task_id, None)),
        );

        let after = load_tag_value_by_id(conn, &self.survivor_tag_id)?.ok_or_else(|| {
            StoreError::NotFound {
                entity: ENTITY_TAG,
                id: self.survivor_tag_id.clone(),
            }
        })?;
        let summary = format!(
            "Renamed tag '{}' to '{}' across {} task(s)",
            self.old_display_name,
            self.new_display_name,
            self.task_ids.len()
        );
        let mut output = MutationOutput::new(after, summary);
        output.set_extra(
            &TAG_RENAME_RESPONSE,
            json!({
                "old_name": self.old_display_name,
                "new_name": self.new_display_name,
                "tasks_updated": self.task_ids.len(),
                "task_ids": self.task_ids,
            }),
        );
        output.set_extra(
            &TAG_RENAME_SYNC_ACTIONS,
            Value::Array(
                sync_actions
                    .into_iter()
                    .map(RenameCliTagSyncAction::into_json)
                    .collect(),
            ),
        );
        Ok(output)
    }
}

#[derive(Clone)]
struct RenameCliTagSyncAction {
    entity_type: &'static str,
    entity_id: String,
    operation: &'static str,
    payload: Option<Value>,
}

impl RenameCliTagSyncAction {
    const fn upsert(entity_type: &'static str, entity_id: String, payload: Option<Value>) -> Self {
        Self {
            entity_type,
            entity_id,
            operation: OP_UPSERT,
            payload,
        }
    }

    const fn delete(entity_type: &'static str, entity_id: String, payload: Value) -> Self {
        Self {
            entity_type,
            entity_id,
            operation: OP_DELETE,
            payload: Some(payload),
        }
    }

    fn into_json(self) -> Value {
        json!({
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "operation": self.operation,
            "payload": self.payload,
        })
    }
}

fn bump_renamed_tag_tasks(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_ids: &[String],
    now: &str,
) -> Result<(), StoreError> {
    for task_id in task_ids {
        let version = hlc.next_version_string();
        let affected = conn
            .prepare_cached(
                "UPDATE tasks
                 SET updated_at = ?1, version = ?2
                 WHERE id = ?3 AND ?2 > version",
            )?
            .execute(rusqlite::params![now, version, task_id])?;
        if affected == 0 {
            return Err(stale_or_missing_task(conn, task_id)?);
        }
    }
    Ok(())
}

fn apply_cli_tag_merge(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    old_tag_id: &str,
    conflict_tag_id: &str,
    task_ids: &[String],
    old_tag_payload: &Value,
    now: &str,
) -> Result<Vec<RenameCliTagSyncAction>, StoreError> {
    let old_edges = load_task_tag_edges_by_tag_id_store(conn, old_tag_id)?;
    let target_task_ids = load_task_tag_edges_by_tag_id_store(conn, conflict_tag_id)?
        .into_iter()
        .map(|edge| edge.task_id)
        .collect::<std::collections::HashSet<_>>();
    let moved_edges = old_edges
        .iter()
        .filter(|edge| !target_task_ids.contains(&edge.task_id))
        .cloned()
        .collect::<Vec<_>>();

    conn.execute(
        "DELETE FROM task_tags
         WHERE tag_id = ?1
           AND task_id IN (SELECT task_id FROM task_tags WHERE tag_id = ?2)",
        rusqlite::params![old_tag_id, conflict_tag_id],
    )?;

    let mut moved_edge_versions: std::collections::HashMap<String, String> =
        std::collections::HashMap::with_capacity(moved_edges.len());
    let mut update_edge = conn.prepare_cached(
        "UPDATE task_tags
         SET tag_id = ?1, version = ?2
         WHERE tag_id = ?3 AND task_id = ?4 AND ?2 > version",
    )?;
    for edge in &moved_edges {
        let edge_version = hlc.next_version_string();
        let affected = update_edge.execute(rusqlite::params![
            conflict_tag_id,
            &edge_version,
            old_tag_id,
            &edge.task_id,
        ])?;
        if affected == 0 {
            return Err(StoreError::StaleVersion {
                entity: EDGE_TASK_TAG,
                id: format!("{}:{old_tag_id}", edge.task_id),
            });
        }
        moved_edge_versions.insert(edge.task_id.clone(), edge_version);
    }
    drop(update_edge);

    let deleted = conn.execute("DELETE FROM tags WHERE id = ?1", [old_tag_id])?;
    if deleted == 0 {
        return Err(StoreError::NotFound {
            entity: ENTITY_TAG,
            id: old_tag_id.to_string(),
        });
    }
    let conflict_version = hlc.next_version_string();
    let updated = conn.execute(
        "UPDATE tags
         SET updated_at = ?1, version = ?2
         WHERE id = ?3 AND ?2 > version",
        rusqlite::params![now, &conflict_version, conflict_tag_id],
    )?;
    if updated == 0 {
        return Err(stale_or_missing_tag(conn, conflict_tag_id)?);
    }

    let mut sync_actions = Vec::with_capacity(old_edges.len() + moved_edges.len() + 2);
    for edge in &old_edges {
        sync_actions.push(RenameCliTagSyncAction::delete(
            EDGE_TASK_TAG,
            format!("{}:{}", edge.task_id, edge.tag_id),
            task_tag_payload(&edge.task_id, &edge.tag_id, &edge.version, &edge.created_at),
        ));
    }
    for edge in &moved_edges {
        let edge_version = moved_edge_versions.get(&edge.task_id).ok_or_else(|| {
            StoreError::Invariant(format!(
                "moved task-tag edge '{}' missing minted version",
                edge.task_id
            ))
        })?;
        sync_actions.push(RenameCliTagSyncAction::upsert(
            EDGE_TASK_TAG,
            format!("{}:{conflict_tag_id}", edge.task_id),
            Some(task_tag_payload(
                &edge.task_id,
                conflict_tag_id,
                edge_version,
                &edge.created_at,
            )),
        ));
    }
    sync_actions.push(RenameCliTagSyncAction::delete(
        ENTITY_TAG,
        old_tag_id.to_string(),
        old_tag_payload.clone(),
    ));
    sync_actions.push(RenameCliTagSyncAction::upsert(
        ENTITY_TAG,
        conflict_tag_id.to_string(),
        None,
    ));

    let expected: std::collections::HashSet<_> = task_ids.iter().collect();
    let actual: std::collections::HashSet<_> = old_edges.iter().map(|edge| &edge.task_id).collect();
    if expected != actual {
        return Err(StoreError::Invariant(
            "rename_tag task id preflight drifted before merge apply".to_string(),
        ));
    }

    Ok(sync_actions)
}

fn enqueue_rename_tag_sync_actions(
    tx: &Connection,
    device_id: &str,
    execution: &MutationExecution,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    let Some(actions_value) = execution.output.get_extra(&TAG_RENAME_SYNC_ACTIONS) else {
        return Ok(());
    };
    let actions = actions_value.as_array().ok_or_else(|| {
        crate::error::CliError::Internal(
            "Mutation contract: rename_tag sync actions extra is an array".to_string(),
        )
    })?;
    for action in actions {
        let entity_type = action
            .get("entity_type")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: rename_tag sync action has entity_type".to_string(),
                )
            })?;
        let entity_id = action
            .get("entity_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: rename_tag sync action has entity_id".to_string(),
                )
            })?;
        let operation = action
            .get("operation")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: rename_tag sync action has operation".to_string(),
                )
            })?;
        let payload = action
            .get("payload")
            .filter(|value| !value.is_null())
            .cloned();
        match (operation, payload) {
            (OP_UPSERT, Some(payload)) => {
                let version = hlc_state.generate().to_string();
                enqueue_payload_upsert(
                    tx,
                    entity_type,
                    entity_id,
                    &payload,
                    crate::commands::shared::bare_outbox_ctx(&version, device_id),
                )?;
            }
            (OP_UPSERT, None) => {
                enqueue_entity_upsert(tx, entity_type, entity_id, hlc_state, device_id)?;
            }
            (OP_DELETE, Some(payload)) => {
                let version = hlc_state.generate().to_string();
                enqueue_payload_delete(
                    tx,
                    entity_type,
                    entity_id,
                    &payload,
                    crate::commands::shared::bare_outbox_ctx(&version, device_id),
                )?;
            }
            (OP_DELETE, None) => {
                return Err(crate::error::CliError::Internal(format!(
                    "Mutation contract: rename_tag delete action '{entity_type}:{entity_id}' has payload"
                )));
            }
            (other, _) => {
                return Err(crate::error::CliError::Internal(format!(
                    "Mutation contract: unsupported rename_tag sync operation '{other}'"
                )));
            }
        }
    }
    Ok(())
}

fn load_task_tag_edges_by_tag_id_store(
    conn: &Connection,
    tag_id: &str,
) -> Result<Vec<TaskTagEdgeWithTaskRow>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT task_id, tag_id, created_at, version
         FROM task_tags
         WHERE tag_id = ?1
         ORDER BY task_id ASC",
    )?;
    let rows = stmt
        .query_map([tag_id], |row| {
            Ok(TaskTagEdgeWithTaskRow {
                task_id: row.get(0)?,
                tag_id: row.get(1)?,
                created_at: row.get(2)?,
                version: row.get(3)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

fn load_tag_value_by_id(conn: &Connection, tag_id: &str) -> Result<Option<Value>, StoreError> {
    Ok(conn
        .query_row(
            "SELECT id, display_name, lookup_key, color, created_at, updated_at, version
             FROM tags WHERE id = ?1",
            [tag_id],
            |row| {
                Ok(json!({
                    "id": row.get::<_, String>(0)?,
                    "display_name": row.get::<_, String>(1)?,
                    "lookup_key": row.get::<_, String>(2)?,
                    "color": row.get::<_, Option<String>>(3)?,
                    "created_at": row.get::<_, String>(4)?,
                    "updated_at": row.get::<_, String>(5)?,
                    "version": row.get::<_, String>(6)?,
                }))
            },
        )
        .optional()?)
}

fn tag_payload(tag: &tag_repo::Tag) -> Value {
    json!({
        "id": tag.id,
        "display_name": tag.display_name,
        "lookup_key": tag.lookup_key,
        "color": tag.color,
        "created_at": tag.created_at.as_string(),
        "updated_at": tag.updated_at.as_string(),
        "version": tag.version,
    })
}

fn task_tag_payload(task_id: &str, tag_id: &str, version: &str, created_at: &str) -> Value {
    lorvex_store::payload_loaders::task_tag_payload(
        &lorvex_domain::TaskId::from_trusted(task_id.to_string()),
        &lorvex_domain::TagId::from_trusted(tag_id.to_string()),
        version,
        created_at,
    )
}

fn stale_or_missing_task(conn: &Connection, task_id: &str) -> Result<StoreError, StoreError> {
    let exists = conn
        .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1")?
        .query_row([task_id], |_| Ok(true))
        .optional()?
        .unwrap_or(false);
    Ok(if exists {
        StoreError::StaleVersion {
            entity: ENTITY_TASK,
            id: task_id.to_string(),
        }
    } else {
        StoreError::NotFound {
            entity: ENTITY_TASK,
            id: task_id.to_string(),
        }
    })
}

fn stale_or_missing_tag(conn: &Connection, tag_id: &str) -> Result<StoreError, StoreError> {
    let exists = conn
        .prepare_cached("SELECT 1 FROM tags WHERE id = ?1")?
        .query_row([tag_id], |_| Ok(true))
        .optional()?
        .unwrap_or(false);
    Ok(if exists {
        StoreError::StaleVersion {
            entity: ENTITY_TAG,
            id: tag_id.to_string(),
        }
    } else {
        StoreError::NotFound {
            entity: ENTITY_TAG,
            id: tag_id.to_string(),
        }
    })
}

pub(crate) fn rename_tag_with_conn(
    conn: &mut Connection,
    old_name: &str,
    new_name: &str,
) -> Result<TagRenameResult, crate::error::CliError> {
    let old_display_name = normalize_single_tag_name(old_name, "old_name")?;
    let new_display_name = normalize_single_tag_name(new_name, "new_name")?;
    let old_lookup_key = lorvex_domain::tag::normalize_lookup_key(&old_display_name);
    let new_lookup_key = lorvex_domain::tag::normalize_lookup_key(&new_display_name);
    if old_lookup_key == new_lookup_key {
        return Err(crate::error::CliError::Validation(
            "old_name and new_name are the same after normalization".to_string(),
        ));
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let old_tag = tag_repo::get_tag_by_name(&tx, &old_display_name)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("tag '{old_display_name}' not found"))
    })?;
    let old_tag_id_typed = lorvex_domain::TagId::from_trusted(old_tag.id.clone());
    let old_edges = load_task_tag_edges_by_tag_id(&tx, &old_tag_id_typed)?;
    let task_ids = old_edges
        .iter()
        .map(|edge| edge.task_id.clone())
        .collect::<Vec<_>>();
    let conflict_tag_id =
        tag_repo::get_tag_by_name(&tx, &new_display_name)?.map(|conflict_tag| conflict_tag.id);
    let surviving_tag_id = conflict_tag_id
        .clone()
        .unwrap_or_else(|| old_tag.id.clone());
    let old_tag_payload = tag_payload(&old_tag);
    let audit_before = json!({
        "id": old_tag.id,
        "display_name": old_display_name,
    });
    let mutation = RenameCliTagMutation {
        old_tag_id: old_tag.id,
        conflict_tag_id,
        survivor_tag_id: surviving_tag_id.clone(),
        old_display_name,
        new_display_name,
        task_ids,
        old_tag_payload,
        audit_before,
        now: lorvex_domain::sync_timestamp_now(),
    };

    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_rename_tag_sync_actions(&tx, &device_id, &execution, hlc_state)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &surviving_tag_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let response = output
        .get_extra(&TAG_RENAME_RESPONSE)
        .cloned()
        .ok_or_else(|| {
            crate::error::CliError::Internal(
                "Mutation contract: rename_tag response extra is present".to_string(),
            )
        })?;
    let response = serde_json::from_value(response)?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(response)
}
