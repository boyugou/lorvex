use crate::startup_maintenance::open_db_at_path;
use lorvex_domain::query::{
    OverduePredicate, Pagination, SearchPredicate, TodayPredicate, UpcomingPredicate,
};
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::list_repo;
use lorvex_store::repositories::task::dependencies::graph;
use lorvex_store::repositories::task::read;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::commands::shared::{load_task_row, today_naivedate_for_conn};
use crate::models::{
    DeferredTaskSummary, DeferredTasksSnapshot, DependencyGraphEdge, DependencyGraphNode,
    DependencyGraphSnapshot, TaskListSnapshot,
};
use crate::render::{
    render_deferred_tasks_snapshot, render_dependency_graph_snapshot, render_task_collection,
    render_task_detail, render_task_list_snapshot, task_row_to_summary,
};

pub(crate) struct TaskListCliQuery {
    pub(crate) list_id: Option<String>,
    pub(crate) status: String,
    pub(crate) priority: Option<u8>,
    pub(crate) due_from: Option<String>,
    pub(crate) due_to: Option<String>,
    pub(crate) planned_from: Option<String>,
    pub(crate) planned_to: Option<String>,
    pub(crate) completed_from: Option<String>,
    pub(crate) completed_to: Option<String>,
    pub(crate) created_from: Option<String>,
    pub(crate) created_to: Option<String>,
    pub(crate) has_due_date: Option<bool>,
    pub(crate) has_planned_date: Option<bool>,
    pub(crate) tags: Vec<String>,
    pub(crate) text: Option<String>,
    pub(crate) blocked_only: bool,
    pub(crate) blocking_others: bool,
    pub(crate) sort_by: String,
    pub(crate) sort_direction: String,
    pub(crate) limit: u32,
}

pub(crate) struct DependencyGraphCliQuery {
    pub(crate) task_id: Option<String>,
    pub(crate) list_id: Option<String>,
    pub(crate) include_inactive: bool,
    pub(crate) limit_nodes: u32,
    pub(crate) limit_edges: u32,
}

pub(crate) fn run_today(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_naivedate_for_conn(&conn)?;
    let rows = read::get_today_tasks(
        &conn,
        &TodayPredicate { date: today },
        Pagination { limit, offset: 0 },
    )?;
    let tasks = rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();

    if tasks.is_empty() && format == OutputFormat::Text {
        let open_count = open_task_count_for_today_hint_with_conn(&conn)?;
        let mut rendered = format!("Lorvex Today\nDB: {}\n", db_path.display());
        rendered.push_str("  - none\n");
        if open_count > 0 {
            let _ = write!(
                rendered,
                "\nHint: you have {open_count} open task(s) without a due_date or planned_date set for today.\n\
                 Set due_date or planned_date to today's date to see them here.\n"
            );
        } else {
            rendered
                .push_str("\nNo open tasks exist. Capture a task with 'lorvex capture <title>'.\n");
        }
        return Ok(rendered);
    }

    render_task_collection("Today", &db_path, tasks, format)
}

pub(super) fn open_task_count_for_today_hint_with_conn(
    conn: &rusqlite::Connection,
) -> Result<i64, crate::error::CliError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM tasks WHERE status = 'open' AND archived_at IS NULL",
        [],
        |row| row.get(0),
    )?)
}

pub(crate) fn run_overdue(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_naivedate_for_conn(&conn)?;
    let rows = read::get_overdue_tasks(
        &conn,
        &OverduePredicate { as_of_date: today },
        Pagination { limit, offset: 0 },
    )?;
    let tasks = rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    render_task_collection("Overdue", &db_path, tasks, format)
}

pub(crate) fn run_upcoming(
    days: u32,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_naivedate_for_conn(&conn)?;
    let rows = read::get_upcoming_tasks(
        &conn,
        &UpcomingPredicate {
            from_date: today,
            days,
        },
        Pagination { limit, offset: 0 },
    )?;
    let tasks = rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    render_task_collection("Upcoming", &db_path, tasks, format)
}

const DEFERRED_TASKS_LIMIT_DEFAULT: u32 = 100;
const DEFERRED_TASKS_LIMIT_CAP: u32 = 500;

pub(crate) fn run_tasks(
    args: TaskListCliQuery,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let limit = args.limit.min(500);
    let result = read::list_tasks(
        &conn,
        &read::ListTasksQuery {
            list_id: args.list_id,
            status: task_status_filter(&args.status)?,
            priority: args.priority,
            due_range: task_date_range(args.due_from, args.due_to),
            planned_range: task_date_range(args.planned_from, args.planned_to),
            completed_range: task_date_range(args.completed_from, args.completed_to),
            created_range: task_date_range(args.created_from, args.created_to),
            due_presence: cli_date_presence(args.has_due_date),
            planned_presence: cli_date_presence(args.has_planned_date),
            tags: args.tags,
            text: args.text,
            // feed the legacy `(bool, bool)` flag pair
            // through the typed normalizer.
            blocking: read::BlockingFilter::from_flags(args.blocked_only, args.blocking_others),
            sort_by: task_sort_by(&args.sort_by)?,
            sort_direction: task_sort_direction(&args.sort_direction)?,
            limit,
            offset: 0,
        },
    )?;
    let tasks = result
        .rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    let snapshot = TaskListSnapshot {
        limit,
        returned: tasks.len(),
        total_matching: result.total_matching,
        truncated: result.total_matching > i64::from(limit),
        tasks,
    };
    render_task_list_snapshot(&db_path, &snapshot, format)
}

const DEPENDENCY_GRAPH_LIMIT_NODES_CAP: u32 = 500;
const DEPENDENCY_GRAPH_LIMIT_EDGES_CAP: u32 = 2_000;

pub(crate) fn run_dependency_graph(
    args: DependencyGraphCliQuery,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let limit_nodes = args.limit_nodes.min(DEPENDENCY_GRAPH_LIMIT_NODES_CAP);
    let limit_edges = args.limit_edges.min(DEPENDENCY_GRAPH_LIMIT_EDGES_CAP);
    let result = graph::get_dependency_graph(
        &conn,
        &graph::DependencyGraphParams {
            task_id: args.task_id,
            list_id: args.list_id,
            include_inactive: args.include_inactive,
            limit_nodes,
            limit_edges,
        },
    )?;
    let snapshot = DependencyGraphSnapshot {
        limit_nodes,
        limit_edges,
        node_count: result.nodes.len(),
        edge_count: result.edges.len(),
        nodes: result
            .nodes
            .into_iter()
            .map(|node| DependencyGraphNode {
                id: node.id,
                title: node.title,
                status: node.status,
                priority: node.priority,
                due_date: node.due_date,
                planned_date: node.planned_date,
                list_id: node.list_id,
            })
            .collect(),
        edges: result
            .edges
            .into_iter()
            .map(|edge| DependencyGraphEdge {
                from: edge.task_id,
                to: edge.depends_on_task_id,
            })
            .collect(),
        roots: result.roots,
        blocked: result.blocked,
        leaf_blockers: result.leaf_blockers,
        truncated: result.truncated,
    };
    render_dependency_graph_snapshot(&db_path, &snapshot, format)
}

/// bridge the existing `Option<bool>` CLI envelope to
/// the typed `DateFilter` enum. `None` (no flag) → `Any`; `Some(true)`
/// → `Present`; `Some(false)` → `Absent`. Centralized here so the
/// translation is identical for due/planned and any future shape
/// change is one site.
const fn cli_date_presence(flag: Option<bool>) -> read::DateFilter {
    match flag {
        None => read::DateFilter::Any,
        Some(true) => read::DateFilter::Present,
        Some(false) => read::DateFilter::Absent,
    }
}

fn task_date_range(from: Option<String>, to: Option<String>) -> Option<read::TaskDateRange> {
    if from.is_none() && to.is_none() {
        None
    } else {
        Some(read::TaskDateRange { from, to })
    }
}

fn task_status_filter(status: &str) -> Result<read::TaskStatusListFilter, crate::error::CliError> {
    match status {
        "open" => Ok(read::TaskStatusListFilter::Open),
        "completed" => Ok(read::TaskStatusListFilter::Completed),
        "cancelled" => Ok(read::TaskStatusListFilter::Cancelled),
        "someday" => Ok(read::TaskStatusListFilter::Someday),
        "all" => Ok(read::TaskStatusListFilter::All),
        _ => Err(crate::error::CliError::Validation(format!(
            "invalid task status filter: {status}"
        ))),
    }
}

fn task_sort_by(sort_by: &str) -> Result<read::TaskListSortBy, crate::error::CliError> {
    match sort_by {
        "priority_due" => Ok(read::TaskListSortBy::PriorityDue),
        "due_date" => Ok(read::TaskListSortBy::DueDate),
        "planned_date" => Ok(read::TaskListSortBy::PlannedDate),
        "updated_at" => Ok(read::TaskListSortBy::UpdatedAt),
        "created_at" => Ok(read::TaskListSortBy::CreatedAt),
        "title" => Ok(read::TaskListSortBy::Title),
        _ => Err(crate::error::CliError::Validation(format!(
            "invalid task sort: {sort_by}"
        ))),
    }
}

fn task_sort_direction(direction: &str) -> Result<read::SortDirection, crate::error::CliError> {
    match direction {
        "asc" => Ok(read::SortDirection::Asc),
        "desc" => Ok(read::SortDirection::Desc),
        _ => Err(crate::error::CliError::Validation(format!(
            "invalid task sort direction: {direction}"
        ))),
    }
}

pub(crate) fn run_deferred(
    list_id: Option<&str>,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let snapshot = get_deferred_tasks_snapshot_with_conn(&conn, list_id, limit)?;
    render_deferred_tasks_snapshot(&db_path, &snapshot, format)
}

pub(super) fn get_deferred_tasks_snapshot_with_conn(
    conn: &rusqlite::Connection,
    list_id: Option<&str>,
    limit: u32,
) -> Result<DeferredTasksSnapshot, crate::error::CliError> {
    let limit = match limit {
        0 => DEFERRED_TASKS_LIMIT_DEFAULT,
        value => value.min(DEFERRED_TASKS_LIMIT_CAP),
    };
    let total_matching = read::count_deferred_tasks(conn, list_id)?;
    let rows = read::get_deferred_tasks(conn, list_id, Pagination { limit, offset: 0 })?;
    let tasks = rows
        .into_iter()
        .map(|row| {
            // #3289: TaskRow fields are sealed; destructure into owned
            // sub-struct field carriers so each `String` field can move
            // into the downstream summary without cloning.
            let (core, scheduling, _, _) = row.into_parts();
            let core = core.into_fields();
            let scheduling = scheduling.into_fields();
            DeferredTaskSummary {
                id: core.id,
                title: core.title,
                status: core.status,
                list_id: core.list_id,
                due_date: scheduling.due.date(),
                planned_date: scheduling.planned_date,
                priority: core.priority,
                defer_count: scheduling.defer_count,
                last_deferred_at: scheduling.last_deferred_at,
                last_defer_reason: scheduling.last_defer_reason,
                updated_at: core.updated_at,
            }
        })
        .collect::<Vec<_>>();
    Ok(DeferredTasksSnapshot {
        limit,
        returned: tasks.len(),
        total_matching,
        truncated: total_matching > i64::from(limit),
        list_id: list_id.map(ToOwned::to_owned),
        tasks,
    })
}

pub(crate) fn run_search(
    query: &str,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    if query.trim().is_empty() {
        return Err(crate::error::CliError::Validation(
            "search query must not be empty".to_string(),
        ));
    }

    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let pred = SearchPredicate {
        query: query.to_string(),
        status_filter: Some(vec![
            "open".to_string(),
            "someday".to_string(),
            "completed".to_string(),
        ]),
        list_filter: None,
        tag_filter: None,
    };
    let result = read::search_tasks_with_fallback(&conn, &pred, Pagination { limit, offset: 0 })?;
    let tasks = result
        .rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    render_task_collection("Search", &db_path, tasks, format)
}

pub(crate) fn run_show(
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let task = load_task_row(&conn, &task_id_typed)?;

    match format {
        OutputFormat::Text => {
            // `.ok().flatten()` silently turned any DB
            // error (lock contention, schema drift, corrupt row) into
            // a missing list_name. Propagate the error so the user
            // sees the actual failure; `list_repo::get_list` already
            // returns Ok(None) for a genuinely missing list, so the
            // unwrap-or-none pattern survives the real absence case.
            let list_name = list_repo::get_list(
                &conn,
                &lorvex_domain::ListId::from_trusted(task.core().list_id().to_string()),
            )?
            .map(|l| l.name);
            Ok(render_task_detail(&task, &db_path, list_name.as_deref()))
        }
        // Wrap the task payload in a `{db_path, task}` envelope so
        // `lorvex show <task_id> --format json` matches the same
        // shape every other JSON-emitting query uses (`{db_path,
        // label, tasks}` for collections, `{db_path, ...}` for
        // snapshots). Without the envelope, downstream agents that
        // diff the parent doc by `db_path` had to special-case this
        // single command.
        OutputFormat::Json => render_query_envelope(
            "query.task.show",
            &db_path,
            serde_json::json!({ "task": task }),
        ),
    }
}
