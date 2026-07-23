//! Shared daily-review write date resolution.
//!
//! Daily reviews are intentionally backdateable only within a short window:
//! a stale draft from weeks ago should not overwrite history, and a far-future
//! date is almost certainly timezone drift or bad input. Keep the policy here
//! so App, MCP, and CLI write surfaces accept and reject the same dates.

use chrono::NaiveDate;

pub const DAILY_REVIEW_MAX_STALENESS_DAYS: i64 = 7;
pub const DAILY_REVIEW_FUTURE_SLACK_DAYS: i64 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DailyReviewDateError {
    InvalidDate { field: &'static str, value: String },
    TooStale { date: String, today: String },
    TooFarFuture { date: String, today: String },
}

impl std::fmt::Display for DailyReviewDateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidDate { field, value } => {
                write!(f, "{field} '{value}' is not a valid YYYY-MM-DD calendar date")
            }
            Self::TooStale { date, today } => write!(
                f,
                "daily review date '{date}' is more than {DAILY_REVIEW_MAX_STALENESS_DAYS} days before today ({today}); refusing to write a stale daily review."
            ),
            Self::TooFarFuture { date, today } => write!(
                f,
                "daily review date '{date}' is more than {DAILY_REVIEW_FUTURE_SLACK_DAYS} day in the future of today ({today}); refusing to write."
            ),
        }
    }
}

impl std::error::Error for DailyReviewDateError {}

fn parse_ymd(field: &'static str, value: &str) -> Result<NaiveDate, DailyReviewDateError> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| DailyReviewDateError::InvalidDate {
        field,
        value: value.to_string(),
    })
}

pub fn resolve_daily_review_write_date(
    requested_date: Option<&str>,
    today: &str,
) -> Result<String, DailyReviewDateError> {
    let today_date = parse_ymd("today", today)?;
    let raw = requested_date.unwrap_or(today);
    let parsed = parse_ymd("daily review date", raw)?;
    let diff = (today_date - parsed).num_days();
    if diff < -DAILY_REVIEW_FUTURE_SLACK_DAYS {
        return Err(DailyReviewDateError::TooFarFuture {
            date: raw.to_string(),
            today: today.to_string(),
        });
    }
    if diff > DAILY_REVIEW_MAX_STALENESS_DAYS {
        return Err(DailyReviewDateError::TooStale {
            date: raw.to_string(),
            today: today.to_string(),
        });
    }
    Ok(parsed.format("%Y-%m-%d").to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_missing_to_today() {
        assert_eq!(
            resolve_daily_review_write_date(None, "2026-05-13").unwrap(),
            "2026-05-13"
        );
    }

    #[test]
    fn accepts_today_stale_edge_and_one_day_future() {
        assert_eq!(
            resolve_daily_review_write_date(Some("2026-05-13"), "2026-05-13").unwrap(),
            "2026-05-13"
        );
        assert_eq!(
            resolve_daily_review_write_date(Some("2026-05-06"), "2026-05-13").unwrap(),
            "2026-05-06"
        );
        assert_eq!(
            resolve_daily_review_write_date(Some("2026-05-14"), "2026-05-13").unwrap(),
            "2026-05-14"
        );
    }

    #[test]
    fn rejects_malformed_stale_and_far_future() {
        assert!(matches!(
            resolve_daily_review_write_date(Some("not-a-date"), "2026-05-13"),
            Err(DailyReviewDateError::InvalidDate { .. })
        ));
        assert!(matches!(
            resolve_daily_review_write_date(Some("2026-05-05"), "2026-05-13"),
            Err(DailyReviewDateError::TooStale { .. })
        ));
        assert!(matches!(
            resolve_daily_review_write_date(Some("2026-05-15"), "2026-05-13"),
            Err(DailyReviewDateError::TooFarFuture { .. })
        ));
    }
}
