use crate::contract::{
    GetTasksByTagArgs, ListAllTagsArgs, MCP_RESULT_LIMIT_CAP, TASKS_BY_TAG_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::handler_support::{
    bounded_limit, enrich_and_fence_tasks_for_response, next_offset_for_page,
};
use crate::tasks::support::status_filter_to_sql_value;
use lorvex_domain::tag::normalize_lookup_key;
use lorvex_store::TASK_ORDER_BY;
use rusqlite::types::Value as SqlValue;
use rusqlite::{params_from_iter, Connection};
use serde_json::json;

use super::shared::{build_task_collection_payload_with_offset, serialize_payload};

const LIST_ALL_TAGS_DEFAULT: u32 = 100;
const LIST_ALL_TAGS_CAP: u32 = 1000;

pub(crate) fn list_all_tags(conn: &Connection, args: &ListAllTagsArgs) -> Result<String, McpError> {
    let limit = if args.limit == 0 {
        LIST_ALL_TAGS_DEFAULT
    } else {
        args.limit.min(LIST_ALL_TAGS_CAP)
    };
    let offset = args.offset;

    // #3019-M1: append OFFSET so callers can walk past the first
    // page's hard cap.
    // making rows beyond the cap silently inaccessible — the same
    // gap that `get_tasks_by_tag` already closed.
    let active_list = lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST;
    let (sql, count_sql): (String, String) = if args.include_inactive {
        (
            "SELECT tg.id, tg.display_name, COUNT(tt.task_id) AS task_count
             FROM tags tg
             JOIN task_tags tt ON tg.id = tt.tag_id
             JOIN tasks t ON tt.task_id = t.id AND t.archived_at IS NULL
             GROUP BY tg.id
             ORDER BY task_count DESC, tg.display_name ASC
             LIMIT ? OFFSET ?"
                .to_string(),
            "SELECT COUNT(DISTINCT tg.id)
             FROM tags tg
             JOIN task_tags tt ON tg.id = tt.tag_id
             JOIN tasks t ON tt.task_id = t.id AND t.archived_at IS NULL"
                .to_string(),
        )
    } else {
        (
            format!(
                "SELECT tg.id, tg.display_name, COUNT(tt.task_id) AS active_count
                 FROM tags tg
                 JOIN task_tags tt ON tg.id = tt.tag_id
                 JOIN tasks t ON tt.task_id = t.id AND t.status IN ({active_list}) AND t.archived_at IS NULL
                 GROUP BY tg.id
                 ORDER BY active_count DESC, tg.display_name ASC
                 LIMIT ? OFFSET ?"
            ),
            format!(
                "SELECT COUNT(DISTINCT tg.id)
                 FROM tags tg
                 JOIN task_tags tt ON tg.id = tt.tag_id
                 JOIN tasks t ON tt.task_id = t.id AND t.status IN ({active_list}) AND t.archived_at IS NULL"
            ),
        )
    };

    let total_matching: i64 = conn.query_row(&count_sql, [], |row| row.get(0))?;

    let mut stmt = conn.prepare_cached(&sql)?;

    let count_label = if args.include_inactive {
        "task_count"
    } else {
        "active_count"
    };

    let tags: Vec<serde_json::Value> = stmt
        .query_map([i64::from(limit), i64::from(offset)], |row| {
            let id: String = row.get(0)?;
            let display_name: String = row.get(1)?;
            let count: i64 = row.get(2)?;
            // #2422: tag display names are user-origin.
            let fenced = crate::system::text_hygiene::mcp_untrusted_text(&display_name);
            Ok(json!({ "id": id, "tag": fenced, count_label: count }))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let returned = tags.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let truncated = total_matching > consumed;
    // #3019-M1: `next_offset` is `null` when this page exhausted the
    // matched rows, otherwise `offset + returned`.
    let next_offset = next_offset_for_page(truncated, consumed, returned);

    // #2750 — canonical field names:
    //   `count` = length of the returned `tags` array
    //   `total_matching` = WHERE-matched rows in DB (not all returned when truncated)
    // Aliasing `count` to `total_matching` here would disagree with
    // every other read response and force LLMs to memorize the drift.
    let payload = json!({
        "count": returned,
        "total_matching": total_matching,
        "returned": returned,
        "truncated": truncated,
        "limit": limit,
        "offset": offset,
        "next_offset": next_offset,
        "tags": tags,
    });
    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn get_tasks_by_tag(
    conn: &Connection,
    args: &GetTasksByTagArgs,
) -> Result<String, McpError> {
    let limit = bounded_limit(args.limit, TASKS_BY_TAG_LIMIT_DEFAULT, MCP_RESULT_LIMIT_CAP);
    let offset = args.offset;
    // NFKC + casefold so CJK / emoji / decomposed Unicode tags resolve
    // through the same `lookup_key` column that `resolve_or_create_tag`
    // writes. Raw `to_lowercase()` is Unicode-naive.
    let tag_key = normalize_lookup_key(&args.tag);

    let mut conditions: Vec<String> = vec![
        "tasks.archived_at IS NULL".to_string(),
        "tasks.id IN (SELECT tt.task_id FROM task_tags tt JOIN tags t ON t.id = tt.tag_id WHERE t.lookup_key = ?)".to_string()
    ];
    let mut values: Vec<SqlValue> = vec![SqlValue::Text(tag_key)];

    if let Some(status_val) = status_filter_to_sql_value(args.status) {
        conditions.push("tasks.status = ?".to_string());
        values.push(SqlValue::Text(status_val.to_string()));
    }

    let where_sql = format!("WHERE {}", conditions.join(" AND "));

    let count_sql = format!("SELECT COUNT(*) FROM tasks {where_sql}");
    let total_matching: i64 =
        conn.query_row(&count_sql, params_from_iter(values.iter()), |row| {
            row.get(0)
        })?;

    // append LIMIT + OFFSET so callers can paginate
    // beyond the first hard-cap page. Order is stable per the canonical
    // `TASK_ORDER_BY` constant (priority_effective, due_date, id) so
    // OFFSET-based pagination doesn't re-shuffle rows mid-walk.
    let mut task_values = values;
    task_values.push(SqlValue::Integer(i64::from(limit)));
    task_values.push(SqlValue::Integer(i64::from(offset)));

    let tasks_sql =
        format!("SELECT tasks.* FROM tasks {where_sql} ORDER BY {TASK_ORDER_BY} LIMIT ? OFFSET ?");
    let mut tasks = query_all_as_json(conn, &tasks_sql, params_from_iter(task_values.iter()))?;
    enrich_and_fence_tasks_for_response(conn, &mut tasks)?;

    let payload = build_task_collection_payload_with_offset(limit, offset, total_matching, tasks);
    serialize_payload(&payload)
}
