//! Canonical query predicates — pure business-rule definitions.
//!
//! These types encode *what* each query means in domain terms, with no SQL or
//! storage coupling. `lorvex-store` repositories accept these predicates and
//! translate them to SQL. Both the Tauri app and the MCP server construct
//! predicates from their own parameters and call the same repository method, so
//! the WHERE-clause logic exists in exactly one place.

use chrono::NaiveDate;

// ---------------------------------------------------------------------------
// Predicates
// ---------------------------------------------------------------------------

/// What counts as a "today" task.
///
/// Semantics:
/// - `planned_date <= date` while not already deadline-overdue, OR
/// - `planned_date IS NULL AND due_date = date`
///
/// All results are filtered to `status = 'open'`.
#[derive(Debug, Clone)]
pub struct TodayPredicate {
    pub date: NaiveDate,
}

/// What counts as "overdue".
///
/// Semantics: `due_date < as_of_date AND status = 'open'`.
///
/// This is intentionally deadline-overdue only. A task whose `planned_date`
/// has slipped into the past but whose deadline has not passed belongs in the
/// "today pool", not the "overdue" bucket.
#[derive(Debug, Clone)]
pub struct OverduePredicate {
    pub as_of_date: NaiveDate,
}

/// What counts as "upcoming".
///
/// Semantics: the effective action date (`planned_date` when present,
/// otherwise `due_date`) falls strictly after `from_date` and on or before
/// `from_date + days`, while the task is not already deadline-overdue.
#[derive(Debug, Clone)]
pub struct UpcomingPredicate {
    pub from_date: NaiveDate,
    pub days: u32,
}

/// Canonical lateness state for an open task.
///
/// `Overdue*` states mean the external deadline has passed. `PastPlanned`
/// means the intended work date slipped into the past, but the deadline has
/// not yet passed.
///
/// Mirrors the TypeScript `TaskLateness` union in `shared/src/types.ts`;
/// the `snake_case` serde tag is the canonical wire form for both Tauri
/// IPC and MCP responses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskLateness {
    PastPlanned,
    OverdueUnhandled,
    OverdueAcknowledged,
}

/// Deadline-overdue means the external due date has passed.
pub fn is_deadline_overdue(due_date: Option<NaiveDate>, as_of_date: NaiveDate) -> bool {
    due_date.is_some_and(|due| due < as_of_date)
}

/// Derive the canonical lateness state for an open task.
///
/// Rules:
/// - `due_date < today` => overdue
/// - overdue + `planned_date >= today` => acknowledged overdue
/// - overdue + no meaningful re-plan => unhandled overdue
/// - `planned_date < today` without deadline-overdue => past-planned
pub fn derive_open_task_lateness(
    planned_date: Option<NaiveDate>,
    due_date: Option<NaiveDate>,
    as_of_date: NaiveDate,
) -> Option<TaskLateness> {
    if is_deadline_overdue(due_date, as_of_date) {
        return Some(
            if planned_date.is_some_and(|planned| planned >= as_of_date) {
                TaskLateness::OverdueAcknowledged
            } else {
                TaskLateness::OverdueUnhandled
            },
        );
    }

    if planned_date.is_some_and(|planned| planned < as_of_date) {
        return Some(TaskLateness::PastPlanned);
    }

    None
}

/// Returns the effective action date: `planned_date` when present, otherwise `due_date`.
pub fn effective_action_date(
    planned_date: Option<NaiveDate>,
    due_date: Option<NaiveDate>,
) -> Option<NaiveDate> {
    planned_date.or(due_date)
}

/// Today-pool membership includes due-today work plus past-planned work whose
/// deadline has not already slipped into the overdue bucket.
pub fn is_today_pool_task(
    planned_date: Option<NaiveDate>,
    due_date: Option<NaiveDate>,
    as_of_date: NaiveDate,
) -> bool {
    match derive_open_task_lateness(planned_date, due_date, as_of_date) {
        Some(TaskLateness::PastPlanned) => return true,
        Some(TaskLateness::OverdueUnhandled | TaskLateness::OverdueAcknowledged) => {
            return false;
        }
        None => {}
    }
    planned_date.map_or_else(
        || due_date.is_some_and(|due| due == as_of_date),
        |planned| planned <= as_of_date,
    )
}

/// Upcoming membership is based on the effective action date and excludes
/// anything already in the overdue or today-pool buckets.
pub fn is_upcoming_task(
    planned_date: Option<NaiveDate>,
    due_date: Option<NaiveDate>,
    from_date: NaiveDate,
    days: u32,
) -> bool {
    // Cap the lookahead so a caller passing `u32::MAX` (or even
    // 100_000+ days) does not panic in `chrono::Date + Duration` on
    // date overflow. 10_000 days ≈ 27 years — orders of magnitude
    // beyond any realistic "upcoming" window the UI surfaces.
    const MAX_UPCOMING_LOOKAHEAD_DAYS: u32 = 10_000;
    if is_deadline_overdue(due_date, from_date)
        || is_today_pool_task(planned_date, due_date, from_date)
    {
        return false;
    }
    let Some(action_date) = effective_action_date(planned_date, due_date) else {
        return false;
    };
    let lookahead = i64::from(days.min(MAX_UPCOMING_LOOKAHEAD_DAYS));
    let Some(end_date) = from_date.checked_add_signed(chrono::Duration::days(lookahead)) else {
        return false;
    };
    action_date > from_date && action_date <= end_date
}

/// Full-text search with optional filters.
///
/// `query` is passed through FTS5 sanitization before use. Filters narrow
/// results by status, list, or tag.
#[derive(Debug, Clone)]
pub struct SearchPredicate {
    pub query: String,
    pub status_filter: Option<Vec<String>>,
    pub list_filter: Option<Vec<String>>,
    pub tag_filter: Option<Vec<String>>,
}

/// Filter tasks by tag identity.
///
/// Exactly one of `tag_id` or `tag_lookup_key` should be provided. If both are
/// given, `tag_id` takes precedence.
#[derive(Debug, Clone)]
pub struct ByTagPredicate {
    pub tag_id: Option<String>,
    pub tag_lookup_key: Option<String>,
}

/// Full-text search for calendar events.
///
/// `query` is passed through FTS5 sanitization before use. Optional
/// `from`/`to` date range narrows results.
#[derive(Debug, Clone)]
pub struct CalendarSearchPredicate {
    pub query: String,
    pub from: Option<String>,
    pub to: Option<String>,
}

// ---------------------------------------------------------------------------
// Pagination
// ---------------------------------------------------------------------------

/// Common pagination parameters for list queries.
#[derive(Debug, Clone, Copy)]
pub struct Pagination {
    pub limit: u32,
    pub offset: u32,
}

impl Default for Pagination {
    fn default() -> Self {
        Self {
            limit: 100,
            offset: 0,
        }
    }
}

#[cfg(test)]
mod tests;
