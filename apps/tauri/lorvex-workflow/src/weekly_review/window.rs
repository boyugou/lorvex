//! Trailing-day window math shared by every weekly-review entry point.
//!
//! [`load_weekly_review_window`] reads the configured timezone via
//! [`crate::timezone::trailing_day_window_utc_bounds_for_conn`] and
//! packages the resulting bounds into a [`WeeklyReviewQueryWindow`].
//! The public [`super::types::WeeklyReviewWindow`] inside it is what
//! every entry point returns on the wire; the bare `start_utc` /
//! `end_utc` / `to_day` strings outside the wire shape are convenience
//! references the section loaders rebind directly into `?N` params.

use lorvex_store::StoreError;
use rusqlite::Connection;

use crate::timezone::trailing_day_window_utc_bounds_for_conn;

use super::types::{WeeklyReviewWindow, WEEKLY_REVIEW_DAYS};

pub(super) struct WeeklyReviewQueryWindow {
    pub model: WeeklyReviewWindow,
    pub start_utc: String,
    pub end_utc: String,
    pub to_day: String,
}

pub(super) fn load_weekly_review_window(
    conn: &Connection,
) -> Result<WeeklyReviewQueryWindow, StoreError> {
    let window = trailing_day_window_utc_bounds_for_conn(conn, WEEKLY_REVIEW_DAYS)?;
    Ok(WeeklyReviewQueryWindow {
        start_utc: window.start_utc.clone(),
        end_utc: window.end_utc.clone(),
        to_day: window.to_day.clone(),
        model: WeeklyReviewWindow {
            from: window.from_day,
            to: window.to_day,
            start_utc: window.start_utc,
            end_utc: window.end_utc,
            days: WEEKLY_REVIEW_DAYS,
        },
    })
}
