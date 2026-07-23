use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;

use crate::cli::OutputFormat;
use crate::commands::mutate::reviews::effects::{
    get_daily_review_history_with_conn, get_daily_review_with_conn,
    get_weekly_review_brief_with_conn, get_weekly_review_snapshot_with_conn,
};
use crate::render::{
    render_daily_review, render_daily_review_history, render_weekly_review_brief,
    render_weekly_review_snapshot,
};

pub(crate) fn run_review_get(
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let review = get_daily_review_with_conn(&conn, date)?;
    render_daily_review(review.as_ref(), &db_path, format)
}

pub(crate) fn run_review_history(
    since: Option<&str>,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let reviews = get_daily_review_history_with_conn(&conn, since, limit)?;
    render_daily_review_history(&reviews, &db_path, format)
}

pub(crate) fn run_review_weekly(
    completed_limit: u32,
    stalled_lists_limit: u32,
    deferred_limit: u32,
    someday_limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let snapshot = get_weekly_review_snapshot_with_conn(
        &conn,
        completed_limit,
        stalled_lists_limit,
        deferred_limit,
        someday_limit,
    )?;
    render_weekly_review_snapshot(&snapshot, &db_path, format)
}

pub(crate) fn run_review_brief(
    completed_limit: u32,
    stalled_lists_limit: u32,
    deferred_limit: u32,
    someday_limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let brief = get_weekly_review_brief_with_conn(
        &conn,
        completed_limit,
        stalled_lists_limit,
        deferred_limit,
        someday_limit,
    )?;
    render_weekly_review_brief(&brief, &db_path, format)
}
