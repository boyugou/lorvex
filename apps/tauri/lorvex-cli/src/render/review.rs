//! Daily-review + weekly-review render helpers.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::{DailyReviewView, WeeklyReviewBrief, WeeklyReviewSnapshot};
use crate::render::format::style_empty_hint;

/// Empty-state hint reused across the weekly-review surfaces. The
/// suggestion is intentionally invariant across both the rich
/// snapshot and the brief — these sections are derived views, not
/// surfaces a user mutates directly, so the helpful pointer is
/// "widen the window or capture activity," not a one-shot command.
const HINT_TOP_COMPLETED: &str =
    "No completed tasks in window — finish one with `lorvex task complete <task-id>` to see it show here.";
const HINT_STALLED_LISTS: &str = "No stalled lists — every list saw activity in the window.";
const HINT_FREQUENTLY_DEFERRED: &str =
    "No frequently-deferred tasks — nothing has been pushed back repeatedly.";
const HINT_SOMEDAY_ITEMS: &str =
    "No someday items — shelve a task with `lorvex task defer <task-id> --to someday`.";

pub(crate) fn render_daily_review(
    review: Option<&DailyReviewView>,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => review.map_or_else(
            || {
                Ok(format!(
                    "Lorvex Daily Review\nDB: {}\nReview: none",
                    db_path.display()
                ))
            },
            |review| {
                Ok(format!(
                    "Lorvex Daily Review\nDB: {}\nDate: {}\nMood: {}\nEnergy: {}\nSummary: {}\nWins: {}\nBlockers: {}\nLearnings: {}\nAI synthesis: {}\nLinked tasks: {}\nLinked lists: {}\n",
                    db_path.display(),
                    review.date,
                    review
                        .mood.map_or_else(|| "none".to_string(), |value| value.to_string()),
                    review
                        .energy_level.map_or_else(|| "none".to_string(), |value| value.to_string()),
                    review.summary,
                    review.wins.as_deref().unwrap_or("none"),
                    review.blockers.as_deref().unwrap_or("none"),
                    review.learnings.as_deref().unwrap_or("none"),
                    review.ai_synthesis.as_deref().unwrap_or("none"),
                    review.linked_task_ids.len(),
                    review.linked_list_ids.len(),
                ))
            },
        ),
        // route through render_query_envelope.
        OutputFormat::Json => render_query_envelope(
            "query.review.daily",
            db_path,
            json!({ "review": review }),
        ),
    }
}

pub(crate) fn render_daily_review_history(
    reviews: &[DailyReviewView],
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Lorvex Daily Review History\nDB: {}\nReviews: {}\n",
                db_path.display(),
                reviews.len()
            );
            for review in reviews {
                let _ = writeln!(output, "- {}: {}", review.date, review.summary);
            }
            Ok(output)
        }
        OutputFormat::Json => render_query_envelope(
            "query.review.daily_history",
            db_path,
            json!({ "reviews": reviews }),
        ),
    }
}

pub(crate) fn render_weekly_review_snapshot(
    snapshot: &WeeklyReviewSnapshot,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Json => render_query_envelope(
            "query.review.weekly",
            db_path,
            json!({ "weekly_review": snapshot }),
        ),
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Weekly Review\nDB: {}\nWindow: {}..{} ({} days)\nCompleted: {}\nCreated: {}\nOverdue open: {}\nFrequently deferred: {}\nSomeday: {}\nEstimate coverage: {}\n",
                db_path.display(),
                snapshot.window.from,
                snapshot.window.to,
                snapshot.window.days,
                snapshot.counts.completed_this_week,
                snapshot.counts.created_this_week,
                snapshot.counts.overdue_open,
                snapshot.counts.deferred_open,
                snapshot.counts.someday,
                snapshot
                    .estimate_summary
                    .estimate_coverage_ratio.map_or_else(|| "none".to_string(), |value| format!("{:.0}%", value * 100.0)),
            );

            rendered.push_str("\nTop completed:\n");
            if snapshot.top_completed.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_TOP_COMPLETED));
            } else {
                for task in &snapshot.top_completed {
                    let completed = task.completed_at.as_deref().unwrap_or("unknown");
                    let _ = writeln!(rendered, "  - {}: {} ({completed})", task.id, task.title);
                }
            }

            rendered.push_str("\nStalled lists:\n");
            if snapshot.stalled_lists.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_STALLED_LISTS));
            } else {
                for list in &snapshot.stalled_lists {
                    let last_activity = list.last_activity.as_deref().unwrap_or("unknown");
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (open: {}, last activity: {last_activity})",
                        list.id, list.name, list.open_task_count
                    );
                }
            }

            rendered.push_str("\nFrequently deferred:\n");
            if snapshot.frequently_deferred.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_FREQUENTLY_DEFERRED));
            } else {
                for task in &snapshot.frequently_deferred {
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (deferred {}x)",
                        task.id, task.title, task.defer_count
                    );
                }
            }

            rendered.push_str("\nSomeday items:\n");
            if snapshot.someday_items.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_SOMEDAY_ITEMS));
            } else {
                for task in &snapshot.someday_items {
                    let _ = writeln!(rendered, "  - {}: {}", task.id, task.title);
                }
            }

            Ok(rendered)
        }
    }
}

pub(crate) fn render_weekly_review_brief(
    brief: &WeeklyReviewBrief,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Json => render_query_envelope(
            "query.review.weekly_brief",
            db_path,
            json!({ "weekly_brief": brief }),
        ),
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Weekly Review Brief\nDB: {}\nWindow: {}..{} ({} days)\nOverdue open: {}\nCreated this week: {}\nEstimate coverage: {}\n",
                db_path.display(),
                brief.window.from,
                brief.window.to,
                brief.window.days,
                brief.overdue_count,
                brief.created_this_week,
                brief
                    .estimate_summary
                    .estimate_coverage_ratio.map_or_else(|| "none".to_string(), |value| format!("{:.0}%", value * 100.0)),
            );

            let meta = &brief.section_meta;
            let _ = write!(
                rendered,
                "\nCompleted this week ({} of {}, truncated: {}):\n",
                meta.completed_this_week.returned,
                meta.completed_this_week.total_matching,
                meta.completed_this_week.truncated,
            );
            if brief.completed_this_week.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_TOP_COMPLETED));
            } else {
                for task in &brief.completed_this_week {
                    let completed = task.completed_at.as_deref().unwrap_or("unknown");
                    let _ = writeln!(rendered, "  - {}: {} ({completed})", task.id, task.title);
                }
            }

            let _ = write!(
                rendered,
                "\nStalled lists ({} of {}, truncated: {}):\n",
                meta.stalled_lists.returned,
                meta.stalled_lists.total_matching,
                meta.stalled_lists.truncated,
            );
            if brief.stalled_lists.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_STALLED_LISTS));
            } else {
                for list in &brief.stalled_lists {
                    let last_activity = list.last_activity.as_deref().unwrap_or("unknown");
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (open: {}, last activity: {last_activity})",
                        list.id, list.name, list.open_task_count
                    );
                }
            }

            let _ = write!(
                rendered,
                "\nFrequently deferred ({} of {}, truncated: {}):\n",
                meta.frequently_deferred.returned,
                meta.frequently_deferred.total_matching,
                meta.frequently_deferred.truncated,
            );
            if brief.frequently_deferred.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_FREQUENTLY_DEFERRED));
            } else {
                for task in &brief.frequently_deferred {
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (deferred {}x)",
                        task.id, task.title, task.defer_count
                    );
                }
            }

            let _ = write!(
                rendered,
                "\nSomeday items ({} of {}, truncated: {}):\n",
                meta.someday_items.returned,
                meta.someday_items.total_matching,
                meta.someday_items.truncated,
            );
            if brief.someday_items.is_empty() {
                rendered.push_str(&style_empty_hint(HINT_SOMEDAY_ITEMS));
            } else {
                for task in &brief.someday_items {
                    let _ = writeln!(rendered, "  - {}: {}", task.id, task.title);
                }
            }

            Ok(rendered)
        }
    }
}
