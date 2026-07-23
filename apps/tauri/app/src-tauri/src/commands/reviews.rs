use lorvex_domain::naming::{ENTITY_DAILY_REVIEW, OP_UPSERT};

use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use super::{
    enqueue_to_outbox_typed, fetch_ordered_tasks_by_ids, sync_timestamp_now,
    with_immediate_transaction, Task,
};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StalledList {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub open_task_count: i64,
    pub last_activity: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct WeeklyReview {
    pub completed_this_week: Vec<Task>,
    pub stalled_lists: Vec<StalledList>,
    pub frequently_deferred: Vec<Task>,
    pub overdue_count: i64,
    pub overdue_tasks: Vec<Task>,
    pub someday_items: Vec<Task>,
    pub created_this_week: i64,
    pub completed_with_estimate_count: i64,
    pub estimate_coverage_ratio: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DailyReview {
    pub date: String,
    pub summary: String,
    pub mood: Option<i64>,
    pub energy_level: Option<i64>,
    pub wins: Option<String>,
    pub blockers: Option<String>,
    pub learnings: Option<String>,
    // Derived from daily_review_task_links / daily_review_list_links join tables.
    // Present in export/import snapshots; absent from direct DB reads (enriched separately).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub linked_task_ids: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub linked_list_ids: Option<Vec<String>>,
    pub ai_synthesis: Option<String>,
    pub timezone: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

fn daily_review_from_store_row(row: lorvex_store::daily_review_ops::DailyReviewRow) -> DailyReview {
    DailyReview {
        date: row.date,
        summary: row.summary,
        mood: row.mood,
        energy_level: row.energy_level,
        wins: row.wins,
        blockers: row.blockers,
        learnings: row.learnings,
        linked_task_ids: (!row.linked_task_ids.is_empty()).then_some(row.linked_task_ids),
        linked_list_ids: (!row.linked_list_ids.is_empty()).then_some(row.linked_list_ids),
        ai_synthesis: row.ai_synthesis,
        timezone: row.timezone,
        created_at: row.created_at,
        updated_at: row.updated_at,
    }
}

#[tauri::command]
pub fn get_weekly_review() -> Result<WeeklyReview, String> {
    get_weekly_review_inner().map_err(String::from)
}

fn get_weekly_review_inner() -> AppResult<WeeklyReview> {
    let conn = get_read_conn()?;
    get_weekly_review_with_conn(&conn)
}

pub(crate) fn get_weekly_review_with_conn(conn: &Connection) -> AppResult<WeeklyReview> {
    let read_model = lorvex_workflow::weekly_review::load_weekly_review(
        conn,
        lorvex_workflow::weekly_review::WeeklyReviewLimits::app_defaults(),
    )?;

    let completed_this_week = fetch_ordered_tasks_by_ids(
        conn,
        &weekly_task_ids(&read_model.completed_this_week),
        "weekly review completed_this_week",
    )?;
    let frequently_deferred = fetch_ordered_tasks_by_ids(
        conn,
        &weekly_task_ids(&read_model.frequently_deferred),
        "weekly review frequently_deferred",
    )?;
    let overdue_tasks = fetch_ordered_tasks_by_ids(
        conn,
        &weekly_task_ids(&read_model.overdue_tasks),
        "weekly review overdue_tasks",
    )?;
    let someday_items = fetch_ordered_tasks_by_ids(
        conn,
        &weekly_task_ids(&read_model.someday_items),
        "weekly review someday_items",
    )?;
    let stalled_lists = read_model
        .stalled_lists
        .into_iter()
        .map(|list| StalledList {
            id: list.id,
            name: list.name,
            icon: list.icon,
            color: list.color,
            open_task_count: list.open_task_count,
            last_activity: list.last_activity.unwrap_or_default(),
        })
        .collect();

    Ok(WeeklyReview {
        completed_this_week,
        stalled_lists,
        frequently_deferred,
        overdue_count: read_model.counts.overdue_open,
        overdue_tasks,
        someday_items,
        created_this_week: read_model.counts.created_this_week,
        completed_with_estimate_count: read_model.estimate_summary.completed_with_estimate_count,
        estimate_coverage_ratio: read_model.estimate_summary.estimate_coverage_ratio,
    })
}

fn weekly_task_ids(items: &[lorvex_workflow::weekly_review::WeeklyReviewTaskItem]) -> Vec<String> {
    items.iter().map(|task| task.id.clone()).collect()
}

#[tauri::command]
pub fn get_daily_reviews(limit: Option<i64>) -> Result<Vec<DailyReview>, String> {
    get_daily_reviews_inner(limit).map_err(String::from)
}

fn get_daily_reviews_inner(limit: Option<i64>) -> AppResult<Vec<DailyReview>> {
    let conn = get_read_conn()?;
    let raw_limit = limit.unwrap_or(30).min(365);
    let limit = if raw_limit < 0 {
        u32::MAX
    } else {
        raw_limit as u32
    };
    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        &conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since: None,
            limit,
            offset: 0,
        },
    )?;
    Ok(page
        .rows
        .into_iter()
        .map(daily_review_from_store_row)
        .collect())
}

#[tauri::command]
pub fn get_daily_review_by_date(date: String) -> Result<Option<DailyReview>, String> {
    get_daily_review_by_date_inner(date).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn get_daily_review_by_date_inner(date: String) -> AppResult<Option<DailyReview>> {
    let conn = get_read_conn()?;
    let row = lorvex_store::daily_review_ops::get_daily_review_row(&conn, &date)?;
    Ok(row.map(daily_review_from_store_row))
}

#[derive(Debug, Deserialize)]
pub struct UpsertDailyReviewInput {
    pub summary: String,
    pub mood: Option<i64>,
    pub energy_level: Option<i64>,
    pub wins: Option<String>,
    pub blockers: Option<String>,
    pub learnings: Option<String>,
    /// The date (YYYY-MM-DD) the review panel was showing when the user
    /// opened it. This is used as the UPSERT key instead of
    /// `today_ymd_for_conn` to prevent silent misattribution when a
    /// user composes near local midnight and hits Save after the date has
    /// rolled over to the next day. See issue #2353.
    ///
    /// Must be within the last 7 days (and not more than one day in the
    /// future, to tolerate timezone-preference drift); otherwise the
    /// write is rejected as a likely stale autosave or manipulation.
    pub expected_date: String,
}

fn validate_review_scale(value: Option<i64>, field: &str) -> AppResult<()> {
    if let Some(v) = value {
        if !(1..=5).contains(&v) {
            return Err(AppError::Validation(format!(
                "{field} must be between 1 and 5, got {v}"
            )));
        }
    }
    Ok(())
}

pub(crate) fn resolve_review_date(expected_date: &str, today: &str) -> AppResult<String> {
    lorvex_workflow::daily_review_date::resolve_daily_review_write_date(Some(expected_date), today)
        .map_err(|error| AppError::Validation(error.to_string()))
}

#[tauri::command]
pub fn upsert_daily_review(input: UpsertDailyReviewInput) -> Result<DailyReview, String> {
    upsert_daily_review_inner(input).map_err(String::from)
}

/// Scrub Unicode and enforce length caps for the four free-text
/// fields a daily review carries. The Tauri upsert path runs this
/// before forwarding to `daily_review_ops`, matching the hygiene
/// contract sibling free-text surfaces apply to user input. Shared by
/// the production handler and the `_for_test` twin so both walk
/// identical preprocessing.
struct SanitizedDailyReview {
    summary: String,
    wins: Option<String>,
    blockers: Option<String>,
    learnings: Option<String>,
}

fn sanitize_daily_review_input(input: &UpsertDailyReviewInput) -> AppResult<SanitizedDailyReview> {
    use lorvex_domain::validation::{MAX_BODY_LENGTH, MAX_TITLE_LENGTH};
    let summary = lorvex_domain::sanitize_user_text(&input.summary);
    if summary.chars().count() > MAX_TITLE_LENGTH {
        return Err(AppError::Validation(format!(
            "summary exceeds maximum length of {MAX_TITLE_LENGTH}"
        )));
    }
    let scrub_long = |label: &str, raw: &Option<String>| -> AppResult<Option<String>> {
        match raw {
            Some(value) => {
                let cleaned = lorvex_domain::sanitize_user_text(value);
                if cleaned.chars().count() > MAX_BODY_LENGTH {
                    return Err(AppError::Validation(format!(
                        "{label} exceeds maximum length of {MAX_BODY_LENGTH}"
                    )));
                }
                Ok(Some(cleaned))
            }
            None => Ok(None),
        }
    };
    Ok(SanitizedDailyReview {
        summary,
        wins: scrub_long("wins", &input.wins)?,
        blockers: scrub_long("blockers", &input.blockers)?,
        learnings: scrub_long("learnings", &input.learnings)?,
    })
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn upsert_daily_review_inner(input: UpsertDailyReviewInput) -> AppResult<DailyReview> {
    validate_review_scale(input.mood, "mood")?;
    validate_review_scale(input.energy_level, "energy_level")?;

    let SanitizedDailyReview {
        summary,
        wins,
        blockers,
        learnings,
    } = sanitize_daily_review_input(&input)?;

    let conn = get_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)?;
    let target_date = resolve_review_date(&input.expected_date, &today)?;
    let now = sync_timestamp_now();
    let timezone = lorvex_workflow::timezone::anchored_timezone_name(&conn)?;
    let version = crate::hlc::generate_version_result()?;

    let review = with_immediate_transaction(&conn, |conn| {
        let applied = lorvex_store::daily_review_ops::upsert_daily_review(
            conn,
            &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
                date: &target_date,
                summary: &summary,
                mood: input.mood,
                energy_level: input.energy_level,
                wins: wins.as_deref(),
                blockers: blockers.as_deref(),
                learnings: learnings.as_deref(),
                ai_synthesis: None,
                timezone: &timezone,
                version: &version,
                now: &now,
            },
        )
        .map_err(AppError::from)?;
        lorvex_store::daily_review_ops::require_daily_review_write_applied(applied, &target_date)
            .map_err(AppError::from)?;

        let review = lorvex_store::daily_review_ops::get_daily_review_row(conn, &target_date)?
            .map(daily_review_from_store_row)
            .ok_or_else(|| {
                AppError::Internal(format!(
                    "daily review '{target_date}' vanished after upsert"
                ))
            })?;

        let payload = serde_json::to_value(&review).map_err(AppError::from)?;
        enqueue_to_outbox_typed(conn, ENTITY_DAILY_REVIEW, &target_date, OP_UPSERT, &payload)?;
        Ok(review)
    })?;

    event_bus::emit_data_changed(event_bus::Entity::DailyReview);
    Ok(review)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Test-only helper that performs the full upsert flow against an
/// explicit connection and "today" value, bypassing the global
/// connection pool and `event_bus` emission. This lets tests exercise
/// the real transaction / outbox / changelog path without needing a
/// Tauri runtime.
#[cfg(test)]
pub(crate) fn upsert_daily_review_with_conn_for_test(
    conn: &Connection,
    input: UpsertDailyReviewInput,
    today: &str,
) -> AppResult<DailyReview> {
    validate_review_scale(input.mood, "mood")?;
    validate_review_scale(input.energy_level, "energy_level")?;

    let SanitizedDailyReview {
        summary,
        wins,
        blockers,
        learnings,
    } = sanitize_daily_review_input(&input)?;

    let target_date = resolve_review_date(&input.expected_date, today)?;
    let now = sync_timestamp_now();
    let timezone = lorvex_workflow::timezone::anchored_timezone_name(conn)?;
    let version = crate::hlc::generate_version_result()?;

    with_immediate_transaction(conn, |conn| {
        let applied = lorvex_store::daily_review_ops::upsert_daily_review(
            conn,
            &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
                date: &target_date,
                summary: &summary,
                mood: input.mood,
                energy_level: input.energy_level,
                wins: wins.as_deref(),
                blockers: blockers.as_deref(),
                learnings: learnings.as_deref(),
                ai_synthesis: None,
                timezone: &timezone,
                version: &version,
                now: &now,
            },
        )
        .map_err(AppError::from)?;
        lorvex_store::daily_review_ops::require_daily_review_write_applied(applied, &target_date)
            .map_err(AppError::from)?;

        let review = lorvex_store::daily_review_ops::get_daily_review_row(conn, &target_date)?
            .map(daily_review_from_store_row)
            .ok_or_else(|| {
                AppError::Internal(format!(
                    "daily review '{target_date}' vanished after upsert"
                ))
            })?;

        let payload = serde_json::to_value(&review).map_err(AppError::from)?;
        enqueue_to_outbox_typed(conn, ENTITY_DAILY_REVIEW, &target_date, OP_UPSERT, &payload)?;
        Ok(review)
    })
}
