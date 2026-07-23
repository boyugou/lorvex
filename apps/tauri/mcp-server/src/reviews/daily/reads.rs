use crate::contract::{
    GetDailyReviewArgs, GetReviewHistoryArgs, REVIEW_HISTORY_LIMIT_CAP,
    REVIEW_HISTORY_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{
    bounded_limit_or_default, next_offset_for_page, resolve_optional_date,
};
use rusqlite::Connection;
use serde_json::json;

pub(crate) fn get_daily_review(
    conn: &Connection,
    args: GetDailyReviewArgs,
) -> Result<String, McpError> {
    let GetDailyReviewArgs { date } = args;
    let date = resolve_optional_date(conn, date)?;
    let row = lorvex_store::daily_review_ops::get_daily_review_row(conn, &date)?;
    match row {
        Some(row) => Ok(serde_json::to_string(&row)?),
        None => Ok(format!("No review found for {date}")),
    }
}

pub(crate) fn get_review_history(
    conn: &Connection,
    args: GetReviewHistoryArgs,
) -> Result<String, McpError> {
    let GetReviewHistoryArgs {
        limit,
        offset,
        since,
    } = args;
    let limit = bounded_limit_or_default(
        limit,
        REVIEW_HISTORY_LIMIT_DEFAULT,
        REVIEW_HISTORY_LIMIT_CAP,
    );
    let offset = offset.unwrap_or(0);
    // #3029-M1: wrap the response in the canonical
    // pagination envelope (mirrors `build_task_collection_payload_with_offset`).
    // `total_matching` slot — the args advertised `limit`/`offset` but
    // peers had no way to detect end-of-stream and the second page was
    // effectively unreachable. Match the `list_lists` / `list_all_tags`
    // remediation from #3019-M1.
    if let Some(ref since) = since {
        lorvex_domain::validation::validate_date_format(since)?;
    }
    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since: since.as_deref(),
            limit,
            offset,
        },
    )?;
    let rows = page.rows;
    let returned = rows.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let total_matching = page.total_matching;
    let next_offset = next_offset_for_page(total_matching > consumed, consumed, returned);
    Ok(serde_json::to_string(&json!({
        "limit": limit,
        "offset": offset,
        "count": rows.len(),
        "returned": rows.len(),
        "total_matching": total_matching,
        "truncated": total_matching > consumed,
        "next_offset": next_offset,
        "reviews": rows,
    }))?)
}
