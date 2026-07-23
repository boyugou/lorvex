mod metrics;
mod render;

use self::metrics::collect_task_pattern_metrics;
use self::render::{build_task_pattern_analysis, collect_source_refs};
use crate::contract::{
    AnalyzeTaskPatternsArgs, TASK_PATTERN_ANALYSIS_TOP_N_CAP, TASK_PATTERN_ANALYSIS_TOP_N_DEFAULT,
    TASK_PATTERN_ANALYSIS_WINDOW_CAP, TASK_PATTERN_ANALYSIS_WINDOW_DEFAULT,
};
use crate::error::McpError;
use crate::runtime::cancellation::check_cancelled;
use crate::system::handler_support::utc_now_iso;
use lorvex_store::with_deferred_read_transaction;
use rusqlite::Connection;
use serde_json::json;
use tokio_util::sync::CancellationToken;

pub(crate) fn analyze_task_patterns(
    conn: &Connection,
    args: &AnalyzeTaskPatternsArgs,
    ct: &CancellationToken,
) -> Result<String, McpError> {
    let &AnalyzeTaskPatternsArgs { window_days, top_n } = args;
    let window_days = window_days
        .unwrap_or(TASK_PATTERN_ANALYSIS_WINDOW_DEFAULT)
        .min(TASK_PATTERN_ANALYSIS_WINDOW_CAP);
    let top_n = top_n
        .unwrap_or(TASK_PATTERN_ANALYSIS_TOP_N_DEFAULT)
        .min(TASK_PATTERN_ANALYSIS_TOP_N_CAP);

    // #2133: short-circuit before any work if the client already
    // cancelled (e.g. the user hit Stop while the tool was being
    // dispatched).
    check_cancelled(ct)?;

    // snapshot-pin the metric collection so the aggregate
    // counters and the representative-sample rows (top deferred, top
    // stalled lists, etc.) stay consistent with each other.
    let metrics = with_deferred_read_transaction(conn, |conn| {
        collect_task_pattern_metrics(conn, window_days, top_n, ct)
    })?;
    // #2133: check between the SQL pipeline and the in-Rust insight
    // rendering. The render step walks the metric vectors; bailing
    // here avoids a bunch of json allocation when the client has
    // already stopped listening.
    check_cancelled(ct)?;
    let insights = build_task_pattern_analysis(&metrics, window_days);
    let source_refs = collect_source_refs(&insights);
    let generated_at = utc_now_iso();

    Ok(serde_json::to_string(&json!({
        "generated_at": generated_at,
        "window_days": window_days,
        "top_n": top_n,
        "metrics": {
            "created_total": metrics.created_total,
            "completed_total": metrics.completed_total,
            "due_date_total": metrics.due_date_total,
            "due_date_miss_total": metrics.due_date_miss_total,
            "frequently_deferred": metrics.deferred_total,
            "stalled_lists": metrics.stalled_total,
            "overdue_backlog": metrics.overdue_total,
        },
        "representative_samples": {
            "attention_distribution": metrics.attention_distribution,
            "frequently_deferred": metrics.deferred_tasks,
            "due_date_miss_rate": metrics.due_date_miss_tasks,
            "stalled_lists": metrics.stalled_lists,
            "overdue_backlog": metrics.overdue_tasks,
        },
        "sections": insights,
        "insights": insights,
        "source_refs": source_refs,
    }))?)
}
