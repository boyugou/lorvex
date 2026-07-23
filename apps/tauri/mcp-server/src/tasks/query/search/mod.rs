use crate::contract::{
    SearchTasksArgs, TaskStatusFilter, MCP_RESULT_LIMIT_CAP, SEARCH_TASKS_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{bounded_limit, enrich_and_fence_tasks_for_response};
use crate::tasks::support::status_filter_to_sql_value;
use lorvex_store::repositories::task::read;
use rusqlite::Connection;
use serde_json::Value;

use super::shared::{
    build_task_collection_payload_with_offset, insert_object_field, rows_to_values,
    serialize_payload,
};

fn status_filter_values(status: TaskStatusFilter) -> Result<Option<Vec<String>>, McpError> {
    match status {
        TaskStatusFilter::All => Ok(None),
        other => status_filter_to_sql_value(other)
            .map(|value| Some(vec![value.to_string()]))
            .ok_or_else(|| {
                McpError::Validation(format!("unsupported task status filter: {other:?}"))
            }),
    }
}

pub(crate) fn search_tasks(conn: &Connection, args: SearchTasksArgs) -> Result<String, McpError> {
    let SearchTasksArgs {
        query,
        status,
        limit,
        offset,
    } = args;
    let limit = bounded_limit(limit, SEARCH_TASKS_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP);

    // Map MCP-specific TaskStatusFilter to the shared SearchPredicate's status_filter.
    let status_filter = status_filter_values(status)?;

    let pred = lorvex_domain::query::SearchPredicate {
        query: query.clone(),
        status_filter,
        list_filter: None,
        tag_filter: None,
    };
    // forward the request offset; the underlying
    // store helper already supports paginated reads.
    let page = lorvex_domain::query::Pagination { limit, offset };

    let result = read::search_tasks_with_fallback(conn, &pred, page)?;

    let total_matching = result.total_matching;

    // Convert TaskRow -> serde_json::Value for MCP enrichment pipeline.
    let mut tasks: Vec<Value> = rows_to_values(result.rows, "task rows")?;

    enrich_and_fence_tasks_for_response(conn, &mut tasks)?;

    let mut payload =
        build_task_collection_payload_with_offset(limit, offset, total_matching, tasks);
    insert_object_field(&mut payload, "query", Value::String(query))?;
    serialize_payload(&payload)
}

#[cfg(test)]
mod tests;
