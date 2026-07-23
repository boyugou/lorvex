use crate::contract::{
    GetUpcomingTasksArgs, GET_UPCOMING_DAYS_DEFAULT, GET_UPCOMING_LIMIT_CAP,
    GET_UPCOMING_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{
    bounded_limit, enrich_and_fence_tasks_for_response, next_offset_for_page,
};
use crate::tasks::query::rows_to_values;
use lorvex_store::repositories::task::read;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::Connection;
use serde_json::{json, Map, Value};

pub(crate) fn get_upcoming_tasks(
    conn: &Connection,
    args: &GetUpcomingTasksArgs,
) -> Result<String, McpError> {
    // snapshot-pin so `total_matching` and the returned rows
    // stay consistent.
    with_deferred_read_transaction(conn, |conn| {
        let &GetUpcomingTasksArgs {
            days,
            limit,
            offset,
        } = args;
        let days = if days == 0 {
            GET_UPCOMING_DAYS_DEFAULT
        } else {
            days
        };
        let limit = bounded_limit(limit, GET_UPCOMING_LIMIT_DEFAULT, GET_UPCOMING_LIMIT_CAP);
        let today = today_ymd_for_conn(conn)?;
        let from_date = lorvex_domain::time::parse_iso_date(&today)?;

        let pred = lorvex_domain::query::UpcomingPredicate { from_date, days };

        let total_matching = read::count_upcoming_tasks(conn, &pred)?;

        // #3029-M3: thread the contract `offset` through the
        // shared `Pagination` shape so callers can walk past page 1
        // of the upcoming window.
        // `offset: 0`, silently dropping anything beyond the limit.
        let page = lorvex_domain::query::Pagination { limit, offset };
        let rows = read::get_upcoming_tasks(conn, &pred, page)?;

        // Convert TaskRow -> serde_json::Value for MCP enrichment pipeline.
        let mut tasks: Vec<Value> = rows_to_values(rows, "upcoming task rows")?;

        enrich_and_fence_tasks_for_response(conn, &mut tasks)?;

        let end = (from_date + chrono::Duration::days(i64::from(days)))
            .format("%Y-%m-%d")
            .to_string();

        let mut grouped: Map<String, Value> = Map::new();
        for task in &tasks {
            let date = task
                .get("planned_date")
                .and_then(Value::as_str)
                .or_else(|| task.get("due_date").and_then(Value::as_str));
            let Some(date) = date else {
                continue;
            };
            let entry = grouped
                .entry(date.to_string())
                .or_insert_with(|| Value::Array(Vec::new()));
            if let Value::Array(items) = entry {
                items.push(task.clone());
            }
        }

        let mut day_counts: Map<String, Value> = Map::new();
        for (date, tasks_for_day) in &grouped {
            let count = tasks_for_day.as_array().map_or(0, Vec::len);
            day_counts.insert(date.clone(), json!(count));
        }

        // #3029-M3: surface `next_offset` so callers can walk past
        // the page-1 cap. Mirrors the canonical envelope.
        let returned = tasks.len() as i64;
        let consumed = i64::from(offset).saturating_add(returned);
        let next_offset = next_offset_for_page(total_matching > consumed, consumed, returned);

        let payload = json!({
            "from": today,
            "to": end,
            "days_requested": days,
            "limit": limit,
            "offset": offset,
            "returned": tasks.len(),
            "total_matching": total_matching,
            "total_tasks": tasks.len(),
            "truncated": total_matching > consumed,
            "next_offset": next_offset,
            "by_date": Value::Object(grouped),
            "day_counts": Value::Object(day_counts),
        });
        Ok(serde_json::to_string(&payload)?)
    })
}
