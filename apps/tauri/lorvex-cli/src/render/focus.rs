//! Today's-focus + focus-schedule render helpers.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::{CurrentFocusView, FocusScheduleView, TaskListItem};
use crate::render::format::{style_banner, style_empty_hint};
use crate::render::tasks::render_task_section;

/// Issue #2994 H8 / #2978-H6 holdout: the "no focus today" branch
/// printed `chrono::Local::now()` regardless of the user's
/// stored timezone preference. Callers now thread a `today_ymd`
/// already computed via `today_ymd_for_conn` (which honors the
/// preference), so the render layer is timezone-policy free and the
/// CLI agrees with the rest of the system on what "today" means.
pub(crate) fn render_current_focus(
    focus: Option<&CurrentFocusView>,
    today_ymd: &str,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => focus.map_or_else(
            || {
                Ok(format!(
                    "{}\nDB: {}\nDate: {}\nToday's focus: none",
                    style_banner("Lorvex Today's Focus"),
                    db_path.display(),
                    today_ymd,
                ))
            },
            // `as_deref().unwrap_or("none")` borrows briefing/timezone in
            // place. The previous `clone().unwrap_or_else(|| "none".to_string())`
            // allocated a fresh owned String for both the present-and-absent
            // branches — the format! call only needs a `&str`.
            |focus| {
                Ok(format!(
                    "{}\nDB: {}\nDate: {}\nBriefing: {}\nTimezone: {}\nTask count: {}\n{}",
                    style_banner("Lorvex Today's Focus"),
                    db_path.display(),
                    focus.date,
                    focus.briefing.as_deref().unwrap_or("none"),
                    focus.timezone.as_deref().unwrap_or("none"),
                    focus.task_ids.len(),
                    render_task_section(
                        "Focus tasks",
                        &focus
                            .tasks
                            .iter()
                            .map(|task| TaskListItem {
                                id: task.id.clone(),
                                title: task.title.clone(),
                                // Borrow both options, pick the first present
                                // one, then clone the inner string once.
                                // Equivalent to the previous
                                // `planned_date.clone().or_else(|| due_date.clone())`
                                // (Option::clone on a `None` is a no-op), but
                                // drops the closure and reads more directly as
                                // "first available date".
                                when: task.planned_date.or(task.due_date).map(|d| d.to_string()),
                            })
                            .collect::<Vec<_>>(),
                    ),
                ))
            },
        ),
        OutputFormat::Json => render_query_envelope(
            "query.focus.current",
            db_path,
            json!({ "current_focus": focus }),
        ),
    }
}

/// render the result of a focus-clear operation. The
/// text output mirrors the "no focus" branch of `render_current_focus`
/// — there is no live row to print — but the JSON envelope ships the
/// pre-clear focus under `cleared_focus` so scripts and tests can
/// audit what was just removed. `current_focus` is always `null` in
/// the clear-result envelope to make the post-state explicit.
///
/// `today_ymd` is the tz-aware fallback used when the
/// caller has nothing to clear (`cleared` is `None`); the render
/// layer no longer reaches for `chrono::Local::now()`.
pub(crate) fn render_focus_cleared(
    cleared: Option<&CurrentFocusView>,
    today_ymd: &str,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => Ok(format!(
            "{}\nDB: {}\nDate: {}\nToday's focus: none",
            style_banner("Lorvex Today's Focus"),
            db_path.display(),
            cleared.map_or_else(|| today_ymd.to_string(), |focus| focus.date.clone()),
        )),
        // focus-clear is a write — route through
        // the mutation envelope.
        OutputFormat::Json => crate::commands::shared::render_mutation_envelope(
            "mutation.focus.clear",
            db_path,
            json!({
                "current_focus": serde_json::Value::Null,
                "cleared_focus": cleared,
            }),
        ),
    }
}

pub(crate) fn render_focus_schedule(
    schedule: Option<&FocusScheduleView>,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => schedule.map_or_else(
            || {
                Ok(format!(
                    "Lorvex Focus Schedule\nDB: {}\nSaved schedule: none",
                    db_path.display(),
                ))
            },
            |schedule| {
                // Same `as_deref().unwrap_or("none")` allocation-free
                // borrow as in `render_current_focus` above.
                let mut out = format!(
                    "Lorvex Focus Schedule\nDB: {}\nDate: {}\nRationale: {}\nTimezone: {}\nBlock count: {}",
                    db_path.display(),
                    schedule.date,
                    schedule.rationale.as_deref().unwrap_or("none"),
                    schedule.timezone.as_deref().unwrap_or("none"),
                    schedule.blocks.len(),
                );
                if let Some(applied) = schedule.task_ids_applied.as_ref() {
                    let _ = write!(out, "\nApplied focus tasks: {}", applied.len());
                }
                out.push_str("\nBlocks:\n");
                if schedule.blocks.is_empty() {
                    out.push_str(&style_empty_hint(
                        "Schedule has no blocks — propose one with `lorvex focus schedule propose --date <YYYY-MM-DD>`.",
                    ));
                } else {
                    for block in &schedule.blocks {
                        let label = block
                            .task_id
                            .as_deref()
                            .or(block.event_id.as_deref())
                            .or(block.title.as_deref())
                            .unwrap_or("none");
                        let _ = writeln!(
                            out,
                            "  - {} {}-{} {}",
                            block.block_type, block.start_time, block.end_time, label
                        );
                    }
                }
                Ok(out)
            },
        ),
        OutputFormat::Json => render_query_envelope(
            "query.focus.schedule",
            db_path,
            json!({ "focus_schedule": schedule }),
        ),
    }
}

pub(crate) fn render_focus_schedule_proposal(
    proposal: &lorvex_store::focus_schedule_proposal::FocusScheduleProposal,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Json => render_query_envelope(
            "query.focus.schedule_proposal",
            db_path,
            json!({ "focus_schedule_proposal": proposal }),
        ),
        OutputFormat::Text => {
            let mut out = format!(
                "Lorvex Focus Schedule Proposal\nDB: {}\nDate: {}\nWorking hours: {}-{}\nAvailable minutes: {}\nCalendar blockers: {}\nScheduled tasks: {}\nUnscheduled tasks: {}\n",
                db_path.display(),
                proposal.date(),
                proposal.working_hours().start(),
                proposal.working_hours().end(),
                proposal.total_minutes_available(),
                proposal.calendar_events_count(),
                proposal.slots().len(),
                proposal.unscheduled().len(),
            );

            out.push_str("Slots:\n");
            if proposal.slots().is_empty() {
                out.push_str(&style_empty_hint(
                    "No tasks could be slotted — widen working hours, lower priority threshold, or add `estimated_minutes` to candidate tasks.",
                ));
            } else {
                for slot in proposal.slots() {
                    let _ = writeln!(
                        out,
                        "  - {}-{} {}: {}",
                        slot.start_time(),
                        slot.end_time(),
                        slot.task().id(),
                        slot.task().title()
                    );
                }
            }

            out.push_str("Timeline blocks:\n");
            if proposal.blocks().is_empty() {
                out.push_str(&style_empty_hint(
                    "Timeline has no blocks — proposals only emit blocks when slots fit; check working hours and calendar blockers above.",
                ));
            } else {
                for block in proposal.blocks() {
                    let label = block
                        .task_id()
                        .or_else(|| block.event_id())
                        .or_else(|| block.title())
                        .unwrap_or("none");
                    let _ = writeln!(
                        out,
                        "  - {} {}-{} {}",
                        block.block_type(),
                        block.start_time(),
                        block.end_time(),
                        label
                    );
                }
            }

            if !proposal.unscheduled().is_empty() {
                out.push_str("Unscheduled:\n");
                for task in proposal.unscheduled() {
                    let _ = writeln!(out, "  - {}: {}", task.id(), task.title());
                }
            }

            Ok(out)
        }
    }
}
