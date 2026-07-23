use crate::calendar;
use crate::contract::{
    GetAiChangelogArgs, GetCalendarEventsArgs, GetCurrentFocusArgs, GetGuideArgs,
};
use crate::focus::current;
use crate::habits;
use crate::memory;
use crate::system::guidance;
use crate::system::logs;
use crate::system::overview;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::Connection;
use serde_json::{json, Value};

/// Session-start changelog limit — enough to recall recent activity without
/// dominating the context budget.
const SESSION_CHANGELOG_LIMIT: u32 = 10;

/// Build a unified session context by composing existing read-path functions.
///
/// Each section is independently faulted: if one section fails, its value is
/// set to an error string rather than aborting the entire response. This
/// maximises the useful information returned even when individual queries hit
/// transient issues.
pub(crate) fn get_session_context(conn: &Connection) -> Result<String, crate::error::McpError> {
    // snapshot-pin the composite read so memory/overview/focus/
    // events/changelog/guide/habits all observe the same DB state. The
    // inner `with_deferred_read_transaction` calls in each sub-handler are
    // no-ops when a transaction is already active (reuses the outer
    // snapshot via `conn.is_autocommit()`).
    with_deferred_read_transaction(conn, |conn| {
        let today = today_ymd_for_conn(conn)?;

        // ── Memory (bounded summary) ───────────────────────────────────
        let memory = match memory::read_memory_session_summary(conn, 10, 500) {
            Ok(val) => val,
            Err(err) => json!({ "error": err.to_string() }),
        };

        // ── Compact overview ────────────────────────────────────────────
        let overview = parse_section(overview::get_overview_compact(conn));

        // ── Current focus (today) ───────────────────────────────────────
        let current_focus = parse_section(current::get_current_focus(
            conn,
            GetCurrentFocusArgs { date: None },
        ));

        // ── Today's calendar events ─────────────────────────────────────
        let today_events = parse_section(calendar::get_calendar_events(
            conn,
            GetCalendarEventsArgs {
                from: today.clone(),
                to: today.clone(),
                limit: 50,
                offset: 0,
                include_provider: true,
            },
        ));

        // ── Recent AI changelog ─────────────────────────────────────────
        let recent_changelog = parse_section(logs::get_ai_changelog(
            conn,
            GetAiChangelogArgs {
                limit: Some(SESSION_CHANGELOG_LIMIT),
                offset: None,
                entity_type: None,
                operation: None,
                entity_id: None,
                since: None,
            },
        ));

        // ── Contextual guide (auto-detected topic) ──────────────────────
        let guide = parse_section(guidance::get_guide(conn, &GetGuideArgs { topic: None }));

        // ── Habits summary (lightweight, typically <10 habits) ─────────
        let habits = parse_section(habits::get_habits_summary(conn, false));

        let payload = json!({
            "date": today,
            "memory": memory,
            "overview": overview,
            "current_focus": current_focus,
            "today_events": today_events,
            "recent_changelog": recent_changelog,
            "guide": guide,
            "habits": habits,
        });

        Ok(serde_json::to_string(&payload)?)
    })
}

/// Parse a JSON string result into a `Value`, or return the error message as a
/// string `Value` so the session context is still usable when one section fails.
fn parse_section(result: Result<String, impl std::fmt::Display>) -> Value {
    match result {
        Ok(json_str) => match serde_json::from_str(&json_str) {
            Ok(value) => value,
            Err(error) => json!({
                "error": format!("section returned malformed JSON: {error}"),
            }),
        },
        Err(err) => json!({ "error": err.to_string() }),
    }
}

#[cfg(test)]
mod tests;
