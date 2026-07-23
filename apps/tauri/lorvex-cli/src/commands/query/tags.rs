use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::tag_repo;
use lorvex_store::repositories::task::read;

use crate::cli::OutputFormat;
use crate::render::{render_tag_collection, render_task_collection, task_row_to_summary};

pub(crate) fn run_tags(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let tags = get_tag_summaries_with_conn(&conn)?;
    render_tag_collection(&db_path, &tags, format)
}

pub(super) fn get_tag_summaries_with_conn(
    conn: &rusqlite::Connection,
) -> Result<Vec<crate::models::TagSummary>, crate::error::CliError> {
    let mut stmt = conn.prepare(&format!(
        "SELECT t.id, t.display_name, t.color, COUNT(tk.id) AS task_count \
         FROM tags t \
         LEFT JOIN task_tags tt ON tt.tag_id = t.id \
         LEFT JOIN tasks tk ON tk.id = tt.task_id AND tk.status IN ({active_list}) AND tk.archived_at IS NULL \
         GROUP BY t.id \
         ORDER BY task_count DESC, t.display_name ASC",
        active_list = lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST,
    ))?;
    let tags: Vec<crate::models::TagSummary> = stmt
        .query_map([], |row| {
            Ok(crate::models::TagSummary {
                id: row.get(0)?,
                display_name: row.get(1)?,
                color: row.get(2)?,
                task_count: row.get(3)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(tags)
}

pub(crate) fn run_tag_tasks(
    tag_name: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    use lorvex_domain::query::{ByTagPredicate, Pagination};

    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let tag = tag_repo::get_tag_by_name(&conn, tag_name)?;
    let tag =
        tag.ok_or_else(|| crate::error::CliError::NotFound(format!("tag '{tag_name}' not found")))?;

    let rows = read::get_tasks_by_tag(
        &conn,
        &ByTagPredicate {
            tag_id: Some(tag.id.clone()),
            tag_lookup_key: None,
        },
        Pagination {
            limit: 100,
            offset: 0,
        },
    )?;
    let tasks = rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    render_task_collection(
        &format!("Tag: {}", tag.display_name),
        &db_path,
        tasks,
        format,
    )
}
