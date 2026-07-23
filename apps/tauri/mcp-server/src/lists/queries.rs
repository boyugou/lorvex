use crate::contract::{GetListArgs, ListListsArgs, GET_LIST_LIMIT_CAP, GET_LIST_LIMIT_DEFAULT};
use crate::error::McpError;
use crate::json_row::{query_all_as_json, query_one_as_json};
use crate::system::handler_support::{bounded_limit, next_offset_for_page};
use crate::system::time_support::trailing_day_window_bounds_for_conn;
use lorvex_domain::naming::{STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_store::repositories::list_repo;
use lorvex_store::TASK_ORDER_BY;
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::{json, Value};

/// Serialize a `ListWithCounts` from the shared repo into the JSON shape
/// that the MCP response contract expects.
fn list_with_counts_to_json(lwc: &list_repo::ListWithCounts) -> Value {
    let l = &lwc.list;
    // #2422: fence user-origin strings before they enter an MCP response.
    let fenced_name = crate::system::text_hygiene::mcp_untrusted_text(&l.name);
    let fenced_description = l.description.as_deref().map_or(Value::Null, |s| {
        Value::String(crate::system::text_hygiene::mcp_untrusted_text(s))
    });
    let fenced_ai_notes = l.ai_notes.as_deref().map_or(Value::Null, |s| {
        Value::String(crate::system::text_hygiene::mcp_untrusted_text(s))
    });
    json!({
        "id": l.id,
        "name": fenced_name,
        "color": l.color,
        "icon": l.icon,
        "description": fenced_description,
        "ai_notes": fenced_ai_notes,
        "created_at": l.created_at,
        "updated_at": l.updated_at,
        "version": l.version,
        "open_count": lwc.open_count,
        "total_count": lwc.total_count,
    })
}

/// Default page size for `list_lists`. Matches the M1 audit's
/// proposed default of 100 — large enough to cover most workspaces
/// in a single round-trip while still bounding the response
/// envelope size.
const LIST_LISTS_LIMIT_DEFAULT: u32 = 100;
/// Hard cap for `list_lists` — same as `LIST_ALL_TAGS_CAP` so the
/// two catalog tools share a paging budget.
const LIST_LISTS_LIMIT_CAP: u32 = 1000;

pub(crate) fn list_lists(conn: &Connection, args: &ListListsArgs) -> Result<String, McpError> {
    // #3019-M1: paginate the lists catalog so workspaces with
    // hundreds of lists can walk the response in pages instead of
    // forcing a single unbounded array. We delegate the WHERE-matched
    // SELECT to the shared repo (single source of truth for counts),
    // then slice in memory — the dataset is small enough that the
    // saved DB round-trip from a SQL `LIMIT/OFFSET` doesn't beat the
    // simplicity of slicing here.
    let limit = if args.limit == 0 {
        LIST_LISTS_LIMIT_DEFAULT
    } else {
        args.limit.min(LIST_LISTS_LIMIT_CAP)
    };
    let offset = args.offset as usize;
    let lists = list_repo::get_all_lists_with_counts(conn)?;
    let total_matching = lists.len() as i64;
    let page: Vec<Value> = lists
        .iter()
        .skip(offset)
        .take(limit as usize)
        .map(list_with_counts_to_json)
        .collect();
    let returned = page.len() as i64;
    let consumed = i64::from(args.offset).saturating_add(returned);
    let truncated = total_matching > consumed;
    let next_offset = next_offset_for_page(truncated, consumed, returned);
    let payload = json!({
        "count": page.len(),
        "returned": page.len(),
        "total_matching": total_matching,
        "limit": limit,
        "offset": args.offset,
        "next_offset": next_offset,
        "truncated": truncated,
        "lists": page,
    });
    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn get_list(conn: &Connection, args: GetListArgs) -> Result<String, McpError> {
    let GetListArgs { id, limit, offset } = args;
    // #3684 — defense-in-depth membership pre-check. The SELECT below
    // would also surface NotFound, but routing list-ID arguments
    // through `validate_list_exists` keeps the runtime contract
    // consistent with the #3607 audit's claim that every list-ID
    // surface validates through the same membership predicate.
    crate::tasks::validation::validate_list_exists(conn, Some(&id))?;
    let list = query_one_as_json(conn, "SELECT * FROM lists WHERE id = ?", [id.clone()])?;
    let Some(Value::Object(mut payload)) = list else {
        return Err(McpError::NotFound(format!("List '{id}' not found")));
    };

    let limit = bounded_limit(limit, GET_LIST_LIMIT_DEFAULT, GET_LIST_LIMIT_CAP);
    let retention_window = trailing_day_window_bounds_for_conn(conn, 7)?;
    static COUNT_SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let total_matching: i64 = conn
        .prepare_cached(COUNT_SQL.get_or_init(|| {
            format!(
                "SELECT COUNT(*) FROM tasks \
                 WHERE list_id = ? \
                   AND status != '{STATUS_CANCELLED}' \
                   AND ( \
                         status != '{STATUS_COMPLETED}' \
                         OR ( \
                             completed_at >= ? \
                             AND completed_at < ? \
                         ) \
                   )"
            )
        }))?
        .query_row(
            [
                id.clone(),
                retention_window.start_utc.clone(),
                retention_window.end_utc.clone(),
            ],
            |row| row.get(0),
        )?;

    static TASKS_SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let mut tasks = query_all_as_json(
        conn,
        TASKS_SQL.get_or_init(|| {
            format!(
                "SELECT * FROM tasks \
                 WHERE list_id = ? \
                   AND status != '{STATUS_CANCELLED}' \
                   AND ( \
                         status != '{STATUS_COMPLETED}' \
                         OR ( \
                             completed_at >= ? \
                             AND completed_at < ? \
                         ) \
                   ) \
                 ORDER BY {TASK_ORDER_BY} \
                 LIMIT ? OFFSET ?"
            )
        }),
        [
            SqlValue::Text(id),
            SqlValue::Text(retention_window.start_utc.clone()),
            SqlValue::Text(retention_window.end_utc),
            SqlValue::Integer(i64::from(limit)),
            SqlValue::Integer(i64::from(offset)),
        ],
    )?;

    // #2422: fence user-origin strings on the returned list + tasks.
    crate::system::text_hygiene::fence_object_field(&mut payload, "name");
    crate::system::text_hygiene::fence_object_field(&mut payload, "description");
    crate::system::text_hygiene::fence_object_field(&mut payload, "ai_notes");
    crate::system::text_hygiene::fence_tasks_user_fields(&mut tasks);

    // #3029-M2: paginate the page slice and surface
    // `next_offset` so callers can walk past the page-1 cap.
    // the only escape hatch was raising `limit` up to the
    // GET_LIST_LIMIT_CAP (1000), which still silently dropped
    // anything beyond — now `next_offset` mirrors the
    // `build_task_collection_payload_with_offset` envelope.
    let returned = tasks.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(total_matching > consumed, consumed, returned);

    payload.insert("tasks".to_string(), Value::Array(tasks.clone()));
    payload.insert("total_matching".to_string(), json!(total_matching));
    payload.insert("returned".to_string(), json!(tasks.len()));
    payload.insert("count".to_string(), json!(tasks.len()));
    payload.insert("limit".to_string(), json!(limit));
    payload.insert("offset".to_string(), json!(offset));
    payload.insert("next_offset".to_string(), json!(next_offset));
    payload.insert("truncated".to_string(), json!(total_matching > consumed));

    Ok(serde_json::to_string(&Value::Object(payload))?)
}
