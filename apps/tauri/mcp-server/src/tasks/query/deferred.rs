use crate::contract::{GetDeferredTasksArgs, DEFERRED_TASKS_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP};
use crate::error::McpError;
use crate::system::handler_support::{bounded_limit, enrich_and_fence_tasks_for_response};
use lorvex_domain::query::Pagination;
use lorvex_store::repositories::task::read;
use rusqlite::Connection;

use super::shared::{build_task_collection_payload_with_offset, rows_to_values, serialize_payload};

pub(crate) fn get_deferred_tasks(
    conn: &Connection,
    args: GetDeferredTasksArgs,
) -> Result<String, McpError> {
    let GetDeferredTasksArgs {
        list_id,
        limit,
        offset,
    } = args;
    let limit = bounded_limit(limit, DEFERRED_TASKS_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP);
    let total_matching = read::count_deferred_tasks(conn, list_id.as_deref())?;
    // thread offset into the store call.
    let rows = read::get_deferred_tasks(conn, list_id.as_deref(), Pagination { limit, offset })?;
    let mut tasks = rows_to_values(rows, "get_deferred_tasks rows")?;
    enrich_and_fence_tasks_for_response(conn, &mut tasks)?;

    let payload = build_task_collection_payload_with_offset(limit, offset, total_matching, tasks);
    serialize_payload(&payload)
}
