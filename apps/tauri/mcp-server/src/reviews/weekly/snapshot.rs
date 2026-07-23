use crate::error::McpError;
use crate::system::diagnostics::clamp_rows_text_field;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::weekly_review::{load_weekly_review_snapshot, WeeklyReviewSnapshotLimits};
use rusqlite::Connection;
use serde::Serialize;
use serde_json::{json, Value};

const REVIEW_SNAPSHOT_COMPLETED_LIMIT: u16 = 5;
const REVIEW_SNAPSHOT_STALLED_LIMIT: u16 = 3;
const REVIEW_SNAPSHOT_DEFERRED_LIMIT: u16 = 5;
const REVIEW_SNAPSHOT_TITLE_MAX_CHARS: usize = 120;
const REVIEW_SNAPSHOT_LIST_NAME_MAX_CHARS: usize = 80;

pub(crate) fn get_weekly_review_snapshot(conn: &Connection) -> Result<String, McpError> {
    // snapshot-pin the aggregate.
    with_deferred_read_transaction(conn, |conn| {
        let snapshot = load_weekly_review_snapshot(
            conn,
            WeeklyReviewSnapshotLimits {
                top_completed: u32::from(REVIEW_SNAPSHOT_COMPLETED_LIMIT),
                stalled_lists: u32::from(REVIEW_SNAPSHOT_STALLED_LIMIT),
                frequently_deferred: u32::from(REVIEW_SNAPSHOT_DEFERRED_LIMIT),
                someday_items: REVIEW_SNAPSHOT_DEFERRED_LIMIT.into(),
            },
        )?;

        let mut top_completed = rows_to_json(snapshot.top_completed)?;
        clamp_rows_text_field(&mut top_completed, "title", REVIEW_SNAPSHOT_TITLE_MAX_CHARS);

        let mut top_stalled_lists = rows_to_json(snapshot.stalled_lists)?;
        clamp_rows_text_field(
            &mut top_stalled_lists,
            "name",
            REVIEW_SNAPSHOT_LIST_NAME_MAX_CHARS,
        );

        let mut top_deferred = rows_to_json(snapshot.frequently_deferred)?;
        clamp_rows_text_field(&mut top_deferred, "title", REVIEW_SNAPSHOT_TITLE_MAX_CHARS);

        let payload = json!({
            "window": {
                "from": snapshot.window.from,
                "to": snapshot.window.to,
                "days": snapshot.window.days
            },
            "counts": {
                "completed_this_week": snapshot.counts.completed_this_week,
                "created_this_week": snapshot.counts.created_this_week,
                "overdue_open": snapshot.counts.overdue_open,
                "deferred_open": snapshot.counts.deferred_open,
                "someday": snapshot.counts.someday,
                "completed_with_estimate_count": snapshot.estimate_summary.completed_with_estimate_count,
                "estimate_coverage_ratio": snapshot.estimate_summary.estimate_coverage_ratio
            },
            "top_completed": top_completed,
            "top_stalled_lists": top_stalled_lists,
            "top_deferred": top_deferred,
            "limits": {
                "top_completed": REVIEW_SNAPSHOT_COMPLETED_LIMIT,
                "top_stalled_lists": REVIEW_SNAPSHOT_STALLED_LIMIT,
                "top_deferred": REVIEW_SNAPSHOT_DEFERRED_LIMIT,
                "title_max_chars": REVIEW_SNAPSHOT_TITLE_MAX_CHARS,
                "list_name_max_chars": REVIEW_SNAPSHOT_LIST_NAME_MAX_CHARS
            }
        });

        Ok(serde_json::to_string(&payload)?)
    })
}

fn rows_to_json<T: Serialize>(rows: Vec<T>) -> Result<Vec<Value>, McpError> {
    match serde_json::to_value(rows)? {
        Value::Array(rows) => Ok(rows),
        other => Err(McpError::Internal(format!(
            "weekly review rows serialized to non-array JSON: {other}"
        ))),
    }
}
