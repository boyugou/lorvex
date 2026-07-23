use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use serde_json::Value;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

struct LinkCliTaskProviderEventMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    provider_kind: &'a str,
    provider_scope: &'a str,
    provider_event_key: &'a str,
}

impl<'a> Mutation for LinkCliTaskProviderEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_PROVIDER_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        "link"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        provider_repo::get_provider_event_link(
            conn,
            self.task_id,
            self.provider_kind,
            self.provider_scope,
            self.provider_event_key,
        )?
        .map(serde_json::to_value)
        .transpose()
        .map_err(StoreError::from)
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let link = provider_repo::upsert_provider_event_link(
            conn,
            self.task_id,
            self.provider_kind,
            self.provider_scope,
            self.provider_event_key,
        )?;
        Ok(MutationOutput::new(
            serde_json::to_value(&link)?,
            format!(
                "Linked task '{}' to {} provider event",
                self.task_id, self.provider_kind
            ),
        ))
    }
}

struct UnlinkCliTaskProviderEventMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    provider_kind: &'a str,
    provider_scope: &'a str,
    provider_event_key: &'a str,
    before: &'a Value,
}

impl<'a> Mutation for UnlinkCliTaskProviderEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_PROVIDER_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let delete = provider_repo::delete_provider_event_link(
            conn,
            self.task_id,
            self.provider_kind,
            self.provider_scope,
            self.provider_event_key,
        )?;
        if !delete.deleted {
            return Err(StoreError::Invariant(format!(
                "provider link vanished during delete: {}:{}:{}:{}",
                self.task_id, self.provider_kind, self.provider_scope, self.provider_event_key
            )));
        }
        Ok(MutationOutput::new(
            serde_json::to_value(&delete.remaining_links)?,
            format!(
                "Unlinked task '{}' from {} provider event",
                self.task_id, self.provider_kind
            ),
        ))
    }
}

fn execute_provider_event_link_mutation<M: Mutation>(
    tx: &Connection,
    hlc_guard: &mut crate::hlc_guard::SharedHlcGuard,
    task_id: &str,
    mutation: &M,
) -> Result<MutationOutput, crate::error::CliError> {
    execute_cli_mutation_with_finalizer(
        tx,
        hlc_guard,
        mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let after_json = if execution.operation == OP_DELETE {
                None
            } else {
                Some(execution.output.after)
            };
            log_cli_changelog_with_state(
                tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: task_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json,
                },
            )?;
            bump_local_change_seq(tx)?;
            Ok(())
        },
    )
}

/// this is the CLI mirror of the MCP server's
/// `link_task_to_provider_event`
/// (`mcp-server/src/calendar/provider_event_links/`). The two surfaces share the
/// `provider_repo::upsert_provider_event_link` writer in `lorvex-store`,
/// so the row that lands in `task_provider_event_links` is byte-identical
/// regardless of which surface initiated the upsert. Audit metadata is
/// surface-owned: the CLI stamps "human" or `LORVEX_AGENT_NAME` in
/// `initiated_by`, while MCP stamps "ai" or the calling tool's actor name.
/// Keep the two sites in lockstep — if the MCP server starts shipping
/// new fields in the link payload (e.g. `provider_metadata`), bring the
/// same fields here.
pub(crate) fn link_task_to_provider_event_with_conn(
    conn: &mut Connection,
    task_id: &lorvex_domain::TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<TaskProviderEventLink, crate::error::CliError> {
    let task_id = normalize_nonempty_cli_id(task_id.as_str(), "task id")?;
    let fields = lorvex_domain::provider_link::normalize_provider_link_fields(
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;

    let tx = calendar_write_tx(conn)?;
    ensure_task_exists(&tx, &task_id)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
    let mutation = LinkCliTaskProviderEventMutation {
        task_id: &task_id_typed,
        provider_kind: &fields.provider_kind,
        provider_scope: &fields.provider_scope,
        provider_event_key: &fields.provider_event_key,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_provider_event_link_mutation(&tx, &mut hlc_guard, &task_id, &mutation)?;
    let link = serde_json::from_value(output.after)?;
    drop(hlc_guard);
    tx.commit()?;

    Ok(link)
}

pub(crate) fn unlink_task_from_provider_event_with_conn(
    conn: &mut Connection,
    task_id: &lorvex_domain::TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<CalendarProviderUnlinkResult, crate::error::CliError> {
    let task_id = normalize_nonempty_cli_id(task_id.as_str(), "task id")?;
    let fields = lorvex_domain::provider_link::normalize_provider_link_fields(
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;

    let tx = calendar_write_tx(conn)?;
    ensure_task_exists(&tx, &task_id)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
    let before_link = provider_repo::get_provider_event_link(
        &tx,
        &task_id_typed,
        &fields.provider_kind,
        &fields.provider_scope,
        &fields.provider_event_key,
    )?;
    let Some(before_link) = before_link else {
        return Err(crate::error::CliError::NotFound(format!(
            "Task-provider event link not found: {task_id}:{}:{}:{}",
            fields.provider_kind, fields.provider_scope, fields.provider_event_key
        )));
    };
    let before_json = serde_json::to_value(&before_link)?;
    let mutation = UnlinkCliTaskProviderEventMutation {
        task_id: &task_id_typed,
        provider_kind: &fields.provider_kind,
        provider_scope: &fields.provider_scope,
        provider_event_key: &fields.provider_event_key,
        before: &before_json,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_provider_event_link_mutation(&tx, &mut hlc_guard, &task_id, &mutation)?;
    let remaining_links = serde_json::from_value(output.after)?;
    drop(hlc_guard);
    tx.commit()?;

    Ok(CalendarProviderUnlinkResult {
        task_id,
        provider_kind: fields.provider_kind,
        provider_scope: fields.provider_scope,
        provider_event_key: fields.provider_event_key,
        remaining_links,
    })
}
