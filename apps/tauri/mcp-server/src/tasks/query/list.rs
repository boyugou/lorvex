use crate::contract::{
    ListTasksArgs, ListTasksSortBy, SortDirection, LIST_TASKS_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP,
};
use crate::error::McpError;
use crate::system::handler_support::{bounded_limit, enrich_and_fence_tasks_for_response};
use lorvex_store::repositories::task::read::{
    self, BlockingFilter, DateFilter, ListTasksQuery, TaskDateRange, TaskListSortBy,
    TaskStatusListFilter,
};
use rusqlite::Connection;

use super::shared::{build_task_collection_payload_with_offset, rows_to_values, serialize_payload};

pub(crate) fn list_tasks(conn: &Connection, args: ListTasksArgs) -> Result<String, McpError> {
    let limit = bounded_limit(args.limit, LIST_TASKS_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP);
    // thread the request `offset` into the underlying
    // `ListTasksQuery` (the store layer already supports it; the MCP
    let offset = args.offset;
    let query = ListTasksQuery {
        limit,
        list_id: args.list_id,
        status: map_status(args.status),
        priority: args.priority,
        due_range: map_date_range("due_range", args.due_range)?,
        planned_range: map_date_range("planned_range", args.planned_range)?,
        completed_range: map_date_range("completed_range", args.completed_range)?,
        created_range: map_date_range("created_range", args.created_range)?,
        due_presence: map_date_presence(args.has_due_date),
        planned_presence: map_date_presence(args.has_planned_date),
        tags: args.tags.unwrap_or_default(),
        text: args.text,
        // collapse the two independent boolean
        // arguments into a single `BlockingFilter` so the wire
        // contract still accepts both knobs but the store layer
        // sees a single closed enum.
        blocking: BlockingFilter::from_flags(
            args.blocked_only.unwrap_or(false),
            args.blocking_others.unwrap_or(false),
        ),
        sort_by: map_sort_by(args.sort_by.unwrap_or(ListTasksSortBy::PriorityDue)),
        sort_direction: map_sort_direction(args.sort_direction.unwrap_or(SortDirection::Asc)),
        offset,
    };
    let result = read::list_tasks(conn, &query)?;
    let mut tasks = rows_to_values(result.rows, "list_tasks rows")?;
    enrich_and_fence_tasks_for_response(conn, &mut tasks)?;

    let payload =
        build_task_collection_payload_with_offset(limit, offset, result.total_matching, tasks);
    serialize_payload(&payload)
}

/// lift the `Option<bool>` MCP wire shape into the
/// typed `DateFilter`. `None` (key omitted) → `Any`; `Some(true)` →
/// `Present`; `Some(false)` → `Absent`. Centralizing the mapping here
/// means both `has_due_date` and `has_planned_date` go through the same
/// translation and any future wire-shape change has exactly one site
/// to update.
const fn map_date_presence(flag: Option<bool>) -> DateFilter {
    match flag {
        None => DateFilter::Any,
        Some(true) => DateFilter::Present,
        Some(false) => DateFilter::Absent,
    }
}

const fn map_status(status: crate::contract::TaskStatusFilter) -> TaskStatusListFilter {
    match status {
        crate::contract::TaskStatusFilter::Open => TaskStatusListFilter::Open,
        crate::contract::TaskStatusFilter::Completed => TaskStatusListFilter::Completed,
        crate::contract::TaskStatusFilter::Cancelled => TaskStatusListFilter::Cancelled,
        crate::contract::TaskStatusFilter::Someday => TaskStatusListFilter::Someday,
        crate::contract::TaskStatusFilter::All => TaskStatusListFilter::All,
    }
}

fn map_date_range(
    field_name: &str,
    range: Option<crate::contract::ListTasksDueRangeArgs>,
) -> Result<Option<TaskDateRange>, McpError> {
    range
        .map(|range| {
            validate_date_range_bound(field_name, "from", range.from.as_deref())?;
            validate_date_range_bound(field_name, "to", range.to.as_deref())?;
            Ok(TaskDateRange {
                from: range.from,
                to: range.to,
            })
        })
        .transpose()
}

fn validate_date_range_bound(
    field_name: &str,
    bound_name: &str,
    value: Option<&str>,
) -> Result<(), McpError> {
    if let Some(value) = value {
        if chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d").is_err() {
            return Err(McpError::Validation(format!(
                "invalid {field_name}.{bound_name} '{value}', expected YYYY-MM-DD"
            )));
        }
    }
    Ok(())
}

const fn map_sort_by(sort_by: ListTasksSortBy) -> TaskListSortBy {
    match sort_by {
        ListTasksSortBy::PriorityDue => TaskListSortBy::PriorityDue,
        ListTasksSortBy::DueDate => TaskListSortBy::DueDate,
        ListTasksSortBy::PlannedDate => TaskListSortBy::PlannedDate,
        ListTasksSortBy::UpdatedAt => TaskListSortBy::UpdatedAt,
        ListTasksSortBy::CreatedAt => TaskListSortBy::CreatedAt,
        ListTasksSortBy::Title => TaskListSortBy::Title,
    }
}

const fn map_sort_direction(sort_direction: SortDirection) -> read::SortDirection {
    match sort_direction {
        SortDirection::Asc => read::SortDirection::Asc,
        SortDirection::Desc => read::SortDirection::Desc,
    }
}
