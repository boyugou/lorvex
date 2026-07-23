use crate::contract::{
    GetWeeklyReviewBriefArgs, WEEKLY_BRIEF_COMPLETED_DEFAULT, WEEKLY_BRIEF_DEFERRED_DEFAULT,
    WEEKLY_BRIEF_LIMIT_CAP, WEEKLY_BRIEF_SOMEDAY_DEFAULT, WEEKLY_BRIEF_STALLED_DEFAULT,
};
use crate::error::McpError;
use crate::runtime::cancellation::check_cancelled;
use crate::system::handler_support::bounded_limit;
use crate::system::text_hygiene::fence_object_field;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::weekly_review::{
    load_weekly_review_brief, WeeklyReviewBrief, WeeklyReviewBriefLimits,
};
use rusqlite::Connection;
use serde::Serialize;
use serde_json::{json, Value};
use tokio_util::sync::CancellationToken;

pub(crate) fn get_weekly_review_brief(
    conn: &Connection,
    args: &GetWeeklyReviewBriefArgs,
    ct: &CancellationToken,
) -> Result<String, McpError> {
    check_cancelled(ct)?;
    with_deferred_read_transaction(conn, |conn| {
        let brief = load_weekly_review_brief(conn, mcp_brief_limits(args))?;
        check_cancelled(ct)?;
        let payload = brief_to_mcp_payload(brief)?;
        Ok(serde_json::to_string(&payload)?)
    })
}

fn mcp_brief_limits(args: &GetWeeklyReviewBriefArgs) -> WeeklyReviewBriefLimits {
    WeeklyReviewBriefLimits {
        completed_this_week: bounded_limit(
            args.completed_limit,
            WEEKLY_BRIEF_COMPLETED_DEFAULT,
            WEEKLY_BRIEF_LIMIT_CAP,
        ),
        stalled_lists: bounded_limit(
            args.stalled_lists_limit,
            WEEKLY_BRIEF_STALLED_DEFAULT,
            WEEKLY_BRIEF_LIMIT_CAP,
        ),
        frequently_deferred: bounded_limit(
            args.deferred_limit,
            WEEKLY_BRIEF_DEFERRED_DEFAULT,
            WEEKLY_BRIEF_LIMIT_CAP,
        ),
        someday_items: bounded_limit(
            args.someday_limit,
            WEEKLY_BRIEF_SOMEDAY_DEFAULT,
            WEEKLY_BRIEF_LIMIT_CAP,
        ),
    }
}

fn brief_to_mcp_payload(brief: WeeklyReviewBrief) -> Result<Value, McpError> {
    let mut completed_this_week = rows_to_json(brief.completed_this_week)?;
    fence_rows_field(&mut completed_this_week, "title");

    let mut stalled_lists = rows_to_json(brief.stalled_lists)?;
    fence_rows_field(&mut stalled_lists, "name");

    let mut frequently_deferred = rows_to_json(brief.frequently_deferred)?;
    fence_rows_field(&mut frequently_deferred, "title");

    let mut someday_items = rows_to_json(brief.someday_items)?;
    fence_rows_field(&mut someday_items, "title");

    Ok(json!({
        "completed_this_week": completed_this_week,
        "stalled_lists": stalled_lists,
        "frequently_deferred": frequently_deferred,
        "overdue_count": brief.overdue_count,
        "someday_items": someday_items,
        "created_this_week": brief.created_this_week,
        "estimate_summary": {
            "completed_total": brief.estimate_summary.completed_total,
            "completed_with_estimate_count": brief.estimate_summary.completed_with_estimate_count,
            "estimate_coverage_ratio": brief.estimate_summary.estimate_coverage_ratio,
        },
        "section_meta": brief.section_meta,
    }))
}

fn rows_to_json<T: Serialize>(rows: Vec<T>) -> Result<Vec<Value>, McpError> {
    match serde_json::to_value(rows)? {
        Value::Array(rows) => Ok(rows),
        other => Err(McpError::Internal(format!(
            "weekly review rows serialized to non-array JSON: {other}"
        ))),
    }
}

fn fence_rows_field(rows: &mut [Value], field: &str) {
    for row in rows {
        if let Some(obj) = row.as_object_mut() {
            fence_object_field(obj, field);
        }
    }
}
