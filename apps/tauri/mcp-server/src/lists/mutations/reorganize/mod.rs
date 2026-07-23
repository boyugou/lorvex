use super::*;
use lorvex_workflow::list_reorganize::{self, ReorganizeListInput};

#[allow(clippy::missing_const_for_fn)]
fn workflow_strategy(strategy: ReorganizeListStrategy) -> list_reorganize::ReorganizeListStrategy {
    match strategy {
        ReorganizeListStrategy::Deadline => list_reorganize::ReorganizeListStrategy::Deadline,
        ReorganizeListStrategy::Priority => list_reorganize::ReorganizeListStrategy::Priority,
        ReorganizeListStrategy::Manual => list_reorganize::ReorganizeListStrategy::Manual,
    }
}

pub(crate) fn reorganize_list(
    conn: &Connection,
    args: ReorganizeListArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let ReorganizeListArgs {
        id: list_id,
        strategy,
        task_ids,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "reorganize_list",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let result = list_reorganize::reorganize_list(
        conn,
        ReorganizeListInput {
            list_id,
            strategy: workflow_strategy(strategy),
            task_ids,
        },
    )?;

    log_change(
        conn,
        LogChangeParams::new("update", ENTITY_LIST, "reorganize_list", result.summary)
            .with_entity_id(result.list_id)
            .with_before(result.before_json)
            .with_after(result.after_json)
            .skip_sync(),
        None,
    )?;

    let response = serde_json::to_string(&result.payload)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "reorganize_list",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests;
