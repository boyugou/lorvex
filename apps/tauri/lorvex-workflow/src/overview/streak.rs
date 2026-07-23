//! Completion-streak query + global cache.
//!
//! The streak walks up to 365 days of completion timestamps and folds
//! them into local dates so a day with any completed task counts as
//! "active". A global [`STREAK_CACHE`] keyed on
//! `(today, timezone, local_change_seq)` short-circuits repeat queries
//! on the same render snapshot — when nothing has changed since the
//! last walk, the cached result is reused instead of re-scanning the
//! completion history.

use std::sync::{Arc, RwLock};

use chrono::NaiveDate;
use lorvex_store::StoreError;
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct CompletionStreak {
    pub count: i64,
    pub active_today: bool,
}

struct StreakCacheEntry {
    today: String,
    timezone_name: Option<String>,
    local_change_seq: u64,
    result: Arc<CompletionStreak>,
}

static STREAK_CACHE: RwLock<Option<StreakCacheEntry>> = RwLock::new(None);

pub(super) fn query_completion_streak(
    conn: &Connection,
    today: &str,
    timezone_name: Option<&str>,
) -> Result<Arc<CompletionStreak>, StoreError> {
    let current_seq = read_local_change_seq(conn)?;
    {
        let guard = STREAK_CACHE
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(entry) = guard.as_ref() {
            if entry.today == today
                && entry.timezone_name.as_deref() == timezone_name
                && entry.local_change_seq == current_seq
            {
                return Ok(Arc::clone(&entry.result));
            }
        }
    }

    let today_parsed = lorvex_domain::time::parse_iso_date(today)
        .map_err(|_| StoreError::Validation(format!("invalid overview day '{today}'")))?;
    let tz_parsed = timezone_name.and_then(lorvex_domain::parse_timezone_name);

    let to_local_date = |completed_at: &str| -> Option<NaiveDate> {
        let dt = chrono::DateTime::parse_from_rfc3339(completed_at).ok()?;
        let utc = dt.with_timezone(&chrono::Utc);
        if let Some(tz) = tz_parsed {
            Some(utc.with_timezone(&tz).date_naive())
        } else {
            Some(utc.with_timezone(&chrono::Local).date_naive())
        }
    };

    let earliest_cutoff = {
        let earliest_local = today_parsed - chrono::Duration::days(400);
        let naive = earliest_local
            .and_hms_opt(0, 0, 0)
            .expect("midnight is always valid");
        let dt = chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(
            naive - chrono::Duration::hours(14),
            chrono::Utc,
        );
        lorvex_domain::format_sync_timestamp(dt)
    };

    let mut completed_days = std::collections::HashSet::new();
    let mut stmt = conn.prepare_cached(
        "SELECT completed_at FROM tasks \
         WHERE status = 'completed' \
           AND archived_at IS NULL \
           AND completed_at IS NOT NULL \
           AND completed_at >= ?1",
    )?;
    let rows = stmt.query_map(params![earliest_cutoff], |row| row.get::<_, String>(0))?;
    for row in rows {
        if let Some(day) = to_local_date(&row?) {
            completed_days.insert(day);
        }
    }
    drop(stmt);

    let active_today = completed_days.contains(&today_parsed);
    let start_date = if active_today {
        today_parsed
    } else {
        let yesterday = today_parsed - chrono::Duration::days(1);
        if completed_days.contains(&yesterday) {
            yesterday
        } else {
            let result = Arc::new(CompletionStreak {
                count: 0,
                active_today: false,
            });
            store_streak_cache_entry(today, timezone_name, current_seq, Arc::clone(&result));
            return Ok(result);
        }
    };

    let mut streak = 0;
    for offset in 0..365 {
        let check_date = start_date - chrono::Duration::days(offset);
        if completed_days.contains(&check_date) {
            streak += 1;
        } else {
            break;
        }
    }

    let result = Arc::new(CompletionStreak {
        count: streak,
        active_today,
    });
    store_streak_cache_entry(today, timezone_name, current_seq, Arc::clone(&result));
    Ok(result)
}

fn read_local_change_seq(conn: &Connection) -> Result<u64, StoreError> {
    let value: Option<i64> = conn
        .query_row(
            "SELECT value FROM local_counters WHERE name = 'local_change_seq'",
            [],
            |row| row.get(0),
        )
        .optional()?;
    match value {
        None => Ok(0),
        Some(value) if value < 0 => Err(StoreError::Invariant(format!(
            "local_change_seq has negative value {value}"
        ))),
        Some(value) => Ok(value as u64),
    }
}

fn store_streak_cache_entry(
    today: &str,
    timezone_name: Option<&str>,
    local_change_seq: u64,
    result: Arc<CompletionStreak>,
) {
    let mut guard = STREAK_CACHE
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *guard = Some(StreakCacheEntry {
        today: today.to_string(),
        timezone_name: timezone_name.map(str::to_string),
        local_change_seq,
        result,
    });
}
