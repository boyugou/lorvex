use crate::contract::{
    GetListHealthSnapshotArgs, LIST_HEALTH_LIMIT_CAP, LIST_HEALTH_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::diagnostics::clamp_rows_text_field;
use crate::system::handler_support::{bounded_limit, next_offset_for_page};
use lorvex_domain::naming::STATUS_OPEN;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::{json, Value};

const LIST_HEALTH_NAME_MAX_CHARS: usize = 80;

pub(crate) fn get_list_health_snapshot(
    conn: &Connection,
    args: &GetListHealthSnapshotArgs,
) -> Result<String, McpError> {
    let &GetListHealthSnapshotArgs { limit, offset } = args;
    let limit = bounded_limit(limit, LIST_HEALTH_LIMIT_DEFAULT, LIST_HEALTH_LIMIT_CAP);
    let today = today_ymd_for_conn(conn)?;

    let mut lists = query_all_as_json(
        conn,
        &format!(
            "SELECT \
               l.id, \
               l.name, \
               l.color, \
               l.icon, \
               COALESCE(SUM(CASE WHEN t.status = '{STATUS_OPEN}' THEN 1 ELSE 0 END), 0) AS open_count, \
               COALESCE(SUM(CASE WHEN t.status = '{STATUS_OPEN}' AND t.due_date < ? THEN 1 ELSE 0 END), 0) AS overdue_open_count, \
               COALESCE(SUM(CASE WHEN t.status = '{STATUS_OPEN}' AND t.due_date = ? THEN 1 ELSE 0 END), 0) AS due_today_open_count, \
               COUNT(*) OVER() AS total_lists \
             FROM lists l \
             LEFT JOIN tasks t ON t.list_id = l.id \
             GROUP BY l.id \
             ORDER BY l.created_at ASC \
             LIMIT ? OFFSET ?"
        ),
        [
            SqlValue::Text(today.clone()),
            SqlValue::Text(today.clone()),
            SqlValue::Integer(i64::from(limit)),
            SqlValue::Integer(i64::from(offset)),
        ],
    )?;

    let total_lists = extract_and_remove_total_lists(&mut lists)?;
    clamp_rows_text_field(&mut lists, "name", LIST_HEALTH_NAME_MAX_CHARS);
    // #2422: fence user-origin list names after clamping.
    for list in &mut lists {
        if let Some(obj) = list.as_object_mut() {
            crate::system::text_hygiene::fence_object_field(obj, "name");
        }
    }

    // #3029-M2: paginate the lists window so workspaces with
    // >LIST_HEALTH_LIMIT_CAP lists can walk past the cap. Mirrors
    // the `next_offset` shape on `get_list`.
    let returned = lists.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(total_lists > consumed, consumed, returned);

    let payload = json!({
        "date": today,
        "summary": {
            "total_lists": total_lists,
            "returned_lists": lists.len(),
            "limit": limit,
            "offset": offset,
            "next_offset": next_offset,
            "truncated": total_lists > consumed,
        },
        "lists": lists,
        "limits": {
            "lists": limit,
            "name_max_chars": LIST_HEALTH_NAME_MAX_CHARS,
        }
    });

    Ok(serde_json::to_string(&payload)?)
}

fn extract_and_remove_total_lists(rows: &mut [Value]) -> Result<i64, McpError> {
    let rows_are_empty = rows.is_empty();
    let mut total_lists: Option<i64> = None;

    for row in rows.iter_mut() {
        let Some(object) = row.as_object_mut() else {
            continue;
        };
        if total_lists.is_none() {
            total_lists = object.get("total_lists").and_then(Value::as_i64);
        }
        object.remove("total_lists");
    }

    match total_lists {
        Some(value) => Ok(value),
        None if rows_are_empty => Ok(0),
        None => Err(McpError::Internal(
            "list health query returned rows without total_lists".to_string(),
        )),
    }
}

#[cfg(test)]
mod tests;
