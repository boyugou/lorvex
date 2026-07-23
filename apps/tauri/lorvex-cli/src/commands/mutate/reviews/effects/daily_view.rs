//! Daily review read paths.
//!
//! `load_daily_review_view_for_date` is the single-row loader used by
//! the add/amend pipelines (re-read after a write so the returned view
//! and the changelog `after` snapshot match what landed on disk).
//! `get_daily_review_with_conn` and `get_daily_review_history_with_conn`
//! are the user-facing read entry points; the history loader is
//! deliberately written as one SELECT per table so reading the trailing
//! 90-day window is O(3) round-trips regardless of `limit`.

use rusqlite::Connection;

use crate::commands::shared::effects::resolve_date_or_today;
use crate::commands::shared::validate_calendar_date;
use crate::models::DailyReviewView;

pub(super) fn load_daily_review_view_for_date(
    conn: &Connection,
    date: &str,
) -> Result<Option<DailyReviewView>, crate::error::CliError> {
    Ok(lorvex_store::daily_review_ops::get_daily_review_row(
        conn, date,
    )?)
}

pub(crate) fn get_daily_review_with_conn(
    conn: &Connection,
    date: Option<&str>,
) -> Result<Option<DailyReviewView>, crate::error::CliError> {
    let date = resolve_date_or_today(conn, date)?;
    load_daily_review_view_for_date(conn, &date)
}

pub(crate) fn get_daily_review_history_with_conn(
    conn: &Connection,
    since: Option<&str>,
    limit: u32,
) -> Result<Vec<DailyReviewView>, crate::error::CliError> {
    if limit == 0 || limit > 90 {
        return Err(crate::error::CliError::Validation(
            "review history limit must be between 1 and 90".to_string(),
        ));
    }
    if let Some(since) = since {
        validate_calendar_date(since)?;
    }
    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since,
            limit,
            offset: 0,
        },
    )?;
    Ok(page.rows)
}
