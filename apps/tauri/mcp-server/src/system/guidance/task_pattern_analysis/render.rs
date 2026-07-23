use super::metrics::LearningMetrics;
use crate::system::guidance_support::severity_by_count;
use serde_json::{json, Value};
use std::collections::HashSet;

pub(super) fn build_task_pattern_analysis(
    metrics: &LearningMetrics,
    window_days: u32,
) -> Vec<Value> {
    let mut insights: Vec<Value> = Vec::new();
    let weeks = (f64::from(window_days) / 7.0).max(1.0);

    if let Some(insight) = build_velocity_insight(metrics, window_days, weeks) {
        insights.push(insight);
    }
    if let Some(insight) = build_attention_distribution_insight(metrics, window_days) {
        insights.push(insight);
    }
    if let Some(insight) = build_frequently_deferred_insight(metrics, window_days) {
        insights.push(insight);
    }
    if let Some(insight) = build_due_date_miss_insight(metrics, window_days) {
        insights.push(insight);
    }
    if let Some(insight) = build_stalled_lists_insight(metrics) {
        insights.push(insight);
    }
    if let Some(insight) = build_overdue_backlog_insight(metrics) {
        insights.push(insight);
    }
    insights
}

/// Build refs of the form `task:<id>` from any iterable of task-like JSON
/// values that carry a string `id` field.
fn task_refs(tasks: &[Value]) -> Vec<Value> {
    tasks
        .iter()
        .filter_map(|task| task.get("id").and_then(Value::as_str))
        .map(|id| Value::String(format!("task:{id}")))
        .collect()
}

/// Build refs of the form `list:<id>` from any iterable of list-like JSON
/// values that carry a string `id` (or `list_id`) field.
fn list_refs(lists: &[Value], id_field: &str) -> Vec<Value> {
    lists
        .iter()
        .filter_map(|list| list.get(id_field).and_then(Value::as_str))
        .map(|id| Value::String(format!("list:{id}")))
        .collect()
}

/// Only emit a velocity insight when there is activity to summarize —
/// a "0 created, 0 completed" insight is noise for empty datasets.
fn build_velocity_insight(
    metrics: &LearningMetrics,
    window_days: u32,
    weeks: f64,
) -> Option<Value> {
    if metrics.created_total == 0 && metrics.completed_total == 0 {
        return None;
    }
    Some(json!({
        "type": "velocity",
        "severity": if metrics.completed_total == 0 && metrics.created_total > 0 {
            "medium"
        } else {
            "low"
        },
        "summary": format!(
            "{} task(s) were created and {} task(s) were completed in the last {} days.",
            metrics.created_total,
            metrics.completed_total,
            window_days,
        ),
        "metrics": {
            "created_total": metrics.created_total,
            "completed_total": metrics.completed_total,
            "completed_per_week": ((metrics.completed_total as f64 / weeks) * 10.0).round() / 10.0,
            "net_flow": metrics.created_total - metrics.completed_total,
        },
        "recommended_actions": [
            "Reduce intake if creation is materially outpacing completion.",
            "Protect focus blocks when completion velocity drops while backlog grows.",
        ],
        "source_refs": [],
    }))
}

fn build_attention_distribution_insight(
    metrics: &LearningMetrics,
    window_days: u32,
) -> Option<Value> {
    if metrics.attention_distribution.is_empty() {
        return None;
    }
    let refs = list_refs(&metrics.attention_distribution, "list_id");
    let top_touched = metrics
        .attention_distribution
        .first()
        .and_then(|entry| entry.get("touched_count"))
        .and_then(Value::as_i64)
        .unwrap_or(0);
    Some(json!({
        "type": "attention_distribution",
        "severity": if top_touched >= 5 { "medium" } else { "low" },
        "summary": format!(
            "Attention in the last {} days concentrated most heavily in {} list bucket(s).",
            window_days,
            metrics.attention_distribution.len(),
        ),
        "metrics": {
            "top_touched_count": top_touched,
        },
        "representative_samples": metrics.attention_distribution,
        "recommended_actions": [
            "Check whether low-attention active lists should be paused or promoted.",
            "Use this distribution to spot neglected commitments versus current focus.",
        ],
        "source_refs": refs,
    }))
}

fn build_frequently_deferred_insight(metrics: &LearningMetrics, window_days: u32) -> Option<Value> {
    if metrics.deferred_total == 0 {
        return None;
    }
    let refs = task_refs(&metrics.deferred_tasks);
    Some(json!({
        "type": "frequently_deferred",
        "severity": severity_by_count(metrics.deferred_total, metrics.thresholds.deferred_severity_high, metrics.thresholds.deferred_severity_medium),
        "summary": format!(
            "{} open task(s) were deferred {}+ times in the last {} days.",
            metrics.deferred_total,
            metrics.thresholds.defer_count_min,
            window_days,
        ),
        "recommended_actions": [
            "Schedule one concrete next step for top deferred tasks.",
            "Move non-committed items to someday to reduce active drag.",
            "Break oversized tasks into smaller executable actions.",
        ],
        "source_refs": refs,
    }))
}

fn build_due_date_miss_insight(metrics: &LearningMetrics, window_days: u32) -> Option<Value> {
    if metrics.due_date_total == 0 {
        return None;
    }
    let refs = task_refs(&metrics.due_date_miss_tasks);
    let miss_rate = metrics.due_date_miss_total as f64 / metrics.due_date_total as f64;
    Some(json!({
        "type": "due_date_miss_rate",
        "severity": if miss_rate >= 0.5 { "high" } else if miss_rate >= 0.25 { "medium" } else { "low" },
        "summary": format!(
            "{} of {} due-dated completed task(s) finished after their due date in the last {} days.",
            metrics.due_date_miss_total,
            metrics.due_date_total,
            window_days,
        ),
        "metrics": {
            "due_date_total": metrics.due_date_total,
            "miss_total": metrics.due_date_miss_total,
            "miss_rate": miss_rate,
        },
        "representative_samples": metrics.due_date_miss_tasks,
        "recommended_actions": [
            "Treat due_date as an external commitment and use planned_date for intended work timing.",
            "When due-date misses cluster, reduce simultaneous hard deadlines or renegotiate scope earlier.",
        ],
        "source_refs": refs,
    }))
}

fn build_stalled_lists_insight(metrics: &LearningMetrics) -> Option<Value> {
    if metrics.stalled_total == 0 {
        return None;
    }
    let refs = list_refs(&metrics.stalled_lists, "id");
    Some(json!({
        "type": "stalled_lists",
        "severity": severity_by_count(metrics.stalled_total, metrics.thresholds.stalled_severity_high, metrics.thresholds.stalled_severity_medium),
        "summary": format!(
            "{} list(s) have been inactive for {}+ days while still containing open tasks.",
            metrics.stalled_total,
            metrics.thresholds.stalled_window_days,
        ),
        "recommended_actions": [
            "Shelve low-value stalled lists to someday.",
            "Promote one unblocker task per stalled list.",
            "Reconfirm whether each list is still an active commitment.",
        ],
        "source_refs": refs,
    }))
}

fn build_overdue_backlog_insight(metrics: &LearningMetrics) -> Option<Value> {
    if metrics.overdue_total == 0 {
        return None;
    }
    let refs = task_refs(&metrics.overdue_tasks);
    Some(json!({
        "type": "overdue_backlog",
        "severity": severity_by_count(metrics.overdue_total, metrics.thresholds.overdue_severity_high, metrics.thresholds.overdue_severity_medium),
        "summary": format!(
            "{} open task(s) are overdue as of {}.",
            metrics.overdue_total,
            metrics.today,
        ),
        "recommended_actions": [
            "Reschedule overdue tasks to realistic dates.",
            "Cancel or defer stale overdue items that no longer matter.",
            "Prioritize a short overdue-clearance block this week.",
        ],
        "source_refs": refs,
    }))
}

pub(super) fn collect_source_refs(insights: &[Value]) -> Vec<String> {
    let mut source_refs: Vec<String> = Vec::new();
    let mut seen_refs: HashSet<String> = HashSet::new();
    for insight in insights {
        if let Some(refs) = insight.get("source_refs").and_then(Value::as_array) {
            for raw_ref in refs.iter().filter_map(Value::as_str) {
                let raw_ref = raw_ref.to_string();
                if seen_refs.insert(raw_ref.clone()) {
                    source_refs.push(raw_ref);
                }
            }
        }
    }
    source_refs
}
