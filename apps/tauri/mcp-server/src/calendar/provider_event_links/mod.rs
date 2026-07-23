use crate::contract::{
    GetProviderEventLinksForTaskArgs, LinkTaskToProviderEventArgs, UnlinkTaskFromProviderEventArgs,
};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming;
use lorvex_store::repositories::provider_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

struct LinkTaskToProviderEventMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    provider_kind: &'a str,
    provider_scope: &'a str,
    provider_event_key: &'a str,
}

impl<'a> Mutation for LinkTaskToProviderEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        naming::EDGE_TASK_PROVIDER_EVENT_LINK
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
        .map_err(|error| StoreError::Serialization(error.to_string()))
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
            serde_json::to_value(&link)
                .map_err(|error| StoreError::Serialization(error.to_string()))?,
            format!("Linked task to {} event", self.provider_kind),
        ))
    }
}

struct UnlinkTaskFromProviderEventMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    provider_kind: &'a str,
    provider_scope: &'a str,
    provider_event_key: &'a str,
    before: &'a Value,
}

impl<'a> Mutation for UnlinkTaskFromProviderEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        naming::EDGE_TASK_PROVIDER_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        "unlink"
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
            serde_json::to_value(&delete.remaining_links)
                .map_err(|error| StoreError::Serialization(error.to_string()))?,
            format!("Unlinked task from {} event", self.provider_kind),
        ))
    }
}

/// Validate the four-tuple and return the normalized values.
/// the validator returned `()` and callers passed the *raw* args
/// straight into `provider_repo::*`, which silently bypassed the
/// scrub. We now return the canonicalized strings so every downstream
/// SQL parameter and ai_changelog entry uses the same value the
/// validator approved.
fn validate_provider_link_args(
    task_id: &str,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<(String, String, String, String), McpError> {
    let task_id = crate::tasks::validation::validate_uuid_arg(task_id, "task_id")?;
    let fields = lorvex_domain::provider_link::normalize_provider_link_fields(
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;
    Ok((
        task_id,
        fields.provider_kind,
        fields.provider_scope,
        fields.provider_event_key,
    ))
}

pub(crate) fn link_task_to_provider_event(
    conn: &Connection,
    args: LinkTaskToProviderEventArgs,
) -> Result<String, McpError> {
    args.validate_shape()?;
    // #3029-M4: idempotency cache. Provider links are local-only
    // (no sync outbox) so a retry without the cache inserts a
    // duplicate row directly.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "link_task_to_provider_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let provider_kind = args.provider_kind.as_canonical_str();
    let (task_id, provider_kind, provider_scope, provider_event_key) = validate_provider_link_args(
        &args.task_id,
        provider_kind,
        &args.provider_scope,
        &args.provider_event_key,
    )?;
    // Verify task exists (nicer error than FK violation)
    let task_id = lorvex_domain::TaskId::from_trusted(task_id);
    if !lorvex_store::task_exists_active(conn, &task_id)? {
        return Err(McpError::NotFound(format!("task not found: {task_id}")));
    }

    let mutation = LinkTaskToProviderEventMutation {
        task_id: &task_id,
        provider_kind: provider_kind.as_str(),
        provider_scope: provider_scope.as_str(),
        provider_event_key: provider_event_key.as_str(),
    };
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "link_task_to_provider_event",
        task_id.as_str().to_string(),
        McpError::from,
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "link_task_to_provider_event",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn unlink_task_from_provider_event(
    conn: &Connection,
    args: UnlinkTaskFromProviderEventArgs,
) -> Result<String, McpError> {
    args.validate_shape()?;
    // #3029-M4: idempotency cache. Cf. `link_task_to_provider_event`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "unlink_task_from_provider_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let provider_kind = args.provider_kind.as_canonical_str();
    let (task_id, provider_kind, provider_scope, provider_event_key) = validate_provider_link_args(
        &args.task_id,
        provider_kind,
        &args.provider_scope,
        &args.provider_event_key,
    )?;

    let task_id = lorvex_domain::TaskId::from_trusted(task_id);
    if !lorvex_store::task_exists_active(conn, &task_id)? {
        return Err(McpError::NotFound(format!("task not found: {task_id}")));
    }

    let before_link = provider_repo::get_provider_event_link(
        conn,
        &task_id,
        &provider_kind,
        &provider_scope,
        &provider_event_key,
    )?;
    let Some(before_link) = before_link else {
        return Err(McpError::NotFound(format!(
            "task-provider event link not found: {task_id}:{provider_kind}:{provider_scope}:{provider_event_key}"
        )));
    };
    let before_json = serde_json::to_value(&before_link)?;

    let mutation = UnlinkTaskFromProviderEventMutation {
        task_id: &task_id,
        provider_kind: provider_kind.as_str(),
        provider_scope: provider_scope.as_str(),
        provider_event_key: provider_event_key.as_str(),
        before: &before_json,
    };
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "unlink_task_from_provider_event",
        task_id.as_str().to_string(),
        McpError::from,
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "unlink_task_from_provider_event",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn get_provider_event_links_for_task(
    conn: &Connection,
    args: GetProviderEventLinksForTaskArgs,
) -> Result<String, McpError> {
    args.validate_shape()?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(args.task_id);
    if !lorvex_store::task_exists_active(conn, &task_id_typed)? {
        return Err(McpError::NotFound(format!(
            "task not found: {task_id_typed}"
        )));
    }
    let links = provider_repo::get_resolved_provider_links_for_task(conn, &task_id_typed)?;

    Ok(serde_json::to_string(&links)?)
}

#[cfg(test)]
mod tests;
