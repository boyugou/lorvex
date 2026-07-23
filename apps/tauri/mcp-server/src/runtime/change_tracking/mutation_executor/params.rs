//! Shared `LogChangeParams` builders consumed by the per-shape
//! delegates in [`super::delegates`].

use lorvex_workflow::mutation::MutationExecution;

use crate::runtime::change_tracking::LogChangeParams;

pub(super) fn audit_params(
    execution: &MutationExecution,
    mcp_tool: &'static str,
    entity_id: String,
) -> LogChangeParams {
    LogChangeParams::new(
        execution.operation,
        execution.entity_kind,
        mcp_tool,
        execution.output.summary.clone(),
    )
    .with_entity_id(entity_id)
    .with_before_opt(execution.before.clone())
    .with_after(execution.output.after.clone())
}

pub(super) fn batch_audit_params(
    execution: &MutationExecution,
    mcp_tool: &'static str,
    entity_ids: Vec<String>,
) -> LogChangeParams {
    LogChangeParams::new(
        execution.operation,
        execution.entity_kind,
        mcp_tool,
        execution.output.summary.clone(),
    )
    .with_entity_ids(entity_ids)
    .with_before_opt(execution.before.clone())
    .with_after(execution.output.after.clone())
}

pub(super) fn tombstone_audit_params(
    execution: &MutationExecution,
    mcp_tool: &'static str,
    entity_id: String,
) -> LogChangeParams {
    LogChangeParams::new(
        execution.operation,
        execution.entity_kind,
        mcp_tool,
        execution.output.summary.clone(),
    )
    .with_entity_id(entity_id)
    .with_before_opt(execution.before.clone())
}
