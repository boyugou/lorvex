use super::*;
use crate::commands::reviews::{
    resolve_review_date, upsert_daily_review_with_conn_for_test, UpsertDailyReviewInput,
};
use serde_json::json;

/// Insert a daily review directly for test setup.
fn insert_test_daily_review(
    conn: &Connection,
    date: &str,
    summary: &str,
    mood: Option<i64>,
    energy_level: Option<i64>,
) {
    insert_test_daily_review_with_version(conn, date, summary, mood, energy_level, TEST_VERSION);
}

fn insert_test_daily_review_with_version(
    conn: &Connection,
    date: &str,
    summary: &str,
    mood: Option<i64>,
    energy_level: Option<i64>,
    version: &str,
) {
    conn.execute(
        "INSERT INTO daily_reviews (date, summary, mood, energy_level, wins, blockers, learnings, ai_synthesis, timezone, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, NULL, NULL, NULL, NULL, 'America/Los_Angeles', ?5, '2026-03-15T08:00:00Z', '2026-03-15T08:00:00Z')",
        params![date, summary, mood, energy_level, version],
    )
    .expect("insert test daily review");
}

// ---------------------------------------------------------------------------
// upsert_daily_review (via lorvex_store::daily_review_ops::DailyReviewRow)
// ---------------------------------------------------------------------------

#[test]
fn upsert_daily_review_creates_review() {
    let conn = setup_sync_test_conn();

    lorvex_store::daily_review_ops::upsert_daily_review(
        &conn,
        &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
            date: "2026-03-15",
            summary: "Great day of progress",
            mood: Some(4),
            energy_level: Some(3),
            wins: Some("Shipped feature X"),
            blockers: None,
            learnings: Some("Learned about async Rust"),
            ai_synthesis: None,
            timezone: "America/New_York",
            version: TEST_VERSION,
            now: "2026-03-15T20:00:00Z",
        },
    )
    .expect("upsert_daily_review create");

    let review = lorvex_store::daily_review_ops::get_daily_review_row(&conn, "2026-03-15")
        .expect("reload created review via Tauri mapper");
    let review = review.expect("created review exists");

    assert_eq!(review.date, "2026-03-15");
    assert_eq!(review.summary, "Great day of progress");
    assert_eq!(review.mood, Some(4));
    assert_eq!(review.energy_level, Some(3));
    assert_eq!(review.wins.as_deref(), Some("Shipped feature X"));
    assert!(review.blockers.is_none());
    assert_eq!(
        review.learnings.as_deref(),
        Some("Learned about async Rust")
    );
    assert!(review.ai_synthesis.is_none());
    assert_eq!(review.timezone.as_deref(), Some("America/New_York"));
    assert!(!review.created_at.is_empty());
    assert_eq!(review.created_at, review.updated_at);
}

#[test]
fn upsert_daily_review_updates_existing_review() {
    let conn = setup_sync_test_conn();

    // Create initial review.
    lorvex_store::daily_review_ops::upsert_daily_review(
        &conn,
        &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
            date: "2026-03-15",
            summary: "Morning check-in",
            mood: Some(3),
            energy_level: Some(2),
            wins: None,
            blockers: Some("CI was flaky"),
            learnings: None,
            ai_synthesis: None,
            timezone: "America/New_York",
            version: "ver-1",
            now: "2026-03-15T08:00:00Z",
        },
    )
    .expect("initial upsert");

    // Update the same date — summary overwrites, mood=None preserves via COALESCE.
    lorvex_store::daily_review_ops::upsert_daily_review(
        &conn,
        &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
            date: "2026-03-15",
            summary: "Evening reflection",
            mood: None,
            energy_level: None,
            wins: Some("Fixed the CI"),
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            timezone: "Asia/Tokyo",
            version: "ver-2",
            now: "2026-03-15T20:00:00Z",
        },
    )
    .expect("update upsert");

    let review = lorvex_store::daily_review_ops::get_daily_review_row(&conn, "2026-03-15")
        .expect("reload updated review");
    let review = review.expect("updated review exists");

    assert_eq!(review.summary, "Evening reflection");
    // COALESCE preserves existing mood/energy_level when update passes None.
    assert_eq!(review.mood, Some(3));
    assert_eq!(review.energy_level, Some(2));
    // Wins is overwritten (non-None in update).
    assert_eq!(review.wins.as_deref(), Some("Fixed the CI"));
    // Blockers preserved from first write via COALESCE.
    assert_eq!(review.blockers.as_deref(), Some("CI was flaky"));
    // Timezone is immutable — stays as original.
    assert_eq!(review.timezone.as_deref(), Some("America/New_York"));
    assert_eq!(review.updated_at, "2026-03-15T20:00:00Z");
}

#[test]
fn upsert_daily_review_rejects_stale_lww_parent_before_outbox_or_seq_bump() {
    let conn = setup_sync_test_conn();
    insert_test_daily_review_with_version(
        &conn,
        "2026-03-15",
        "newer peer state",
        Some(5),
        Some(4),
        "9999999999999_9999_ffffffffffffffff",
    );

    let err = upsert_daily_review_with_conn_for_test(
        &conn,
        UpsertDailyReviewInput {
            summary: "stale local attempt".to_string(),
            mood: Some(1),
            energy_level: Some(1),
            wins: None,
            blockers: None,
            learnings: None,
            expected_date: "2026-03-15".to_string(),
        },
        "2026-03-15",
    )
    .expect_err("stale daily review upsert must reject before side effects");

    match err {
        crate::error::AppError::Store(boxed) => match *boxed {
            lorvex_store::StoreError::StaleVersion { entity, id } => {
                assert_eq!(entity, lorvex_domain::naming::ENTITY_DAILY_REVIEW);
                assert_eq!(id, "2026-03-15");
            }
            other => panic!("expected daily-review StaleVersion, got {other:?}"),
        },
        other => panic!("expected daily-review StaleVersion, got {other:?}"),
    }

    let (summary, mood, version): (String, Option<i64>, String) = conn
        .query_row(
            "SELECT summary, mood, version FROM daily_reviews WHERE date = '2026-03-15'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load unchanged review");
    assert_eq!(summary, "newer peer state");
    assert_eq!(mood, Some(5));
    assert_eq!(version, "9999999999999_9999_ffffffffffffffff");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'daily_review'",
            [],
            |row| row.get(0),
        )
        .expect("count daily review outbox");
    assert_eq!(outbox_count, 0);

    let local_change_seq = lorvex_runtime::read_local_change_seq(&conn)
        .expect("read local change seq after stale rejection");
    assert_eq!(local_change_seq, 0);
}

// ---------------------------------------------------------------------------
// get_daily_review_by_date (via store-owned DailyReviewRow projection)
// ---------------------------------------------------------------------------

#[test]
fn get_daily_review_by_date_returns_correct_review() {
    let conn = setup_sync_test_conn();

    insert_test_daily_review(&conn, "2026-03-10", "Monday review", Some(4), Some(5));
    insert_test_daily_review(&conn, "2026-03-11", "Tuesday review", Some(2), Some(3));

    let review = lorvex_store::daily_review_ops::get_daily_review_row(&conn, "2026-03-11")
        .expect("fetch review by date");
    let review = review.expect("review exists");

    assert_eq!(review.date, "2026-03-11");
    assert_eq!(review.summary, "Tuesday review");
    assert_eq!(review.mood, Some(2));
    assert_eq!(review.energy_level, Some(3));
}

#[test]
fn get_daily_review_by_date_returns_none_for_missing_date() {
    let conn = setup_sync_test_conn();

    let result = lorvex_store::daily_review_ops::get_daily_review_row(&conn, "2099-12-31")
        .expect("query should not error");

    assert!(result.is_none(), "missing date should return None");
}

// ---------------------------------------------------------------------------
// get_daily_reviews (multiple reviews ordered by date DESC)
// ---------------------------------------------------------------------------

#[test]
fn get_daily_reviews_returns_multiple_ordered_by_date_desc() {
    let conn = setup_sync_test_conn();

    insert_test_daily_review(&conn, "2026-03-10", "Monday", Some(3), None);
    insert_test_daily_review(&conn, "2026-03-12", "Wednesday", Some(5), None);
    insert_test_daily_review(&conn, "2026-03-11", "Tuesday", Some(4), None);

    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        &conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since: None,
            limit: 30,
            offset: 0,
        },
    )
    .expect("fetch reviews");
    let reviews = page.rows;

    assert_eq!(reviews.len(), 3);
    // Most recent first.
    assert_eq!(reviews[0].date, "2026-03-12");
    assert_eq!(reviews[0].summary, "Wednesday");
    assert_eq!(reviews[1].date, "2026-03-11");
    assert_eq!(reviews[1].summary, "Tuesday");
    assert_eq!(reviews[2].date, "2026-03-10");
    assert_eq!(reviews[2].summary, "Monday");
}

#[test]
fn get_daily_reviews_respects_limit() {
    let conn = setup_sync_test_conn();

    insert_test_daily_review(&conn, "2026-03-10", "Day 1", None, None);
    insert_test_daily_review(&conn, "2026-03-11", "Day 2", None, None);
    insert_test_daily_review(&conn, "2026-03-12", "Day 3", None, None);

    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        &conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since: None,
            limit: 2,
            offset: 0,
        },
    )
    .expect("fetch reviews with limit");
    let reviews = page.rows;

    assert_eq!(reviews.len(), 2);
    assert_eq!(reviews[0].date, "2026-03-12");
    assert_eq!(reviews[1].date, "2026-03-11");
}

#[test]
fn get_daily_reviews_empty_database() {
    let conn = setup_sync_test_conn();

    let page = lorvex_store::daily_review_ops::list_daily_review_rows(
        &conn,
        lorvex_store::daily_review_ops::DailyReviewHistoryQuery {
            since: None,
            limit: 30,
            offset: 0,
        },
    )
    .expect("fetch reviews on empty db");
    let reviews = page.rows;

    assert!(reviews.is_empty());
}

// ---------------------------------------------------------------------------
// expected_date — issue #2353 midnight-crossing attribution
// ---------------------------------------------------------------------------

#[test]
fn resolve_review_date_uses_expected_date_when_within_window() {
    // Panel was opened on the 16th; user hit Save just after midnight so
    // `today_ymd_for_conn` now reports the 17th. The review must be
    // attributed to the 16th, not silently misfiled under the 17th.
    let resolved = resolve_review_date("2026-04-16", "2026-04-17").expect("resolve within window");
    assert_eq!(resolved, "2026-04-16");
}

#[test]
fn upsert_daily_review_input_rejects_missing_expected_date() {
    let payload = json!({
        "summary": "Missing pinned date",
        "mood": null,
        "energy_level": null,
        "wins": null,
        "blockers": null,
        "learnings": null
    });
    let err = serde_json::from_value::<UpsertDailyReviewInput>(payload)
        .expect_err("missing expected_date should fail deserialization");
    assert!(
        err.to_string().contains("expected_date"),
        "unexpected error: {err}"
    );
}

#[test]
fn resolve_review_date_rejects_stale_expected_date() {
    // A draft revived from ten days ago is almost certainly stale (or a
    // manipulation attempt) — reject the write.
    let err = resolve_review_date("2026-04-07", "2026-04-17")
        .expect_err("stale expected_date should be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("2026-04-07") && msg.contains("days before today"),
        "unexpected error message: {msg}"
    );
}

#[test]
fn resolve_review_date_rejects_malformed_expected_date() {
    let err = resolve_review_date("not-a-date", "2026-04-17")
        .expect_err("malformed expected_date should be rejected");
    assert!(
        err.to_string().contains("not a valid"),
        "unexpected error: {err}"
    );
}

#[test]
fn resolve_review_date_rejects_far_future_expected_date() {
    // Slack of one day is tolerated (timezone-preference drift); two
    // days in the future is not.
    let err = resolve_review_date("2026-04-20", "2026-04-17")
        .expect_err("far-future expected_date should be rejected");
    assert!(
        err.to_string().contains("future"),
        "unexpected error: {err}"
    );
}

#[test]
fn resolve_review_date_tolerates_one_day_future_drift() {
    // One-day slack covers the case where the client and server disagree
    // on the calendar day due to timezone-preference drift.
    let resolved =
        resolve_review_date("2026-04-18", "2026-04-17").expect("one-day future tolerated");
    assert_eq!(resolved, "2026-04-18");
}

#[test]
fn upsert_daily_review_honors_expected_date_over_today() {
    // End-to-end: when the handler sees expected_date = yesterday but
    // today_ymd_for_conn reports today, the row MUST land on yesterday.
    let conn = setup_sync_test_conn();

    let review = upsert_daily_review_with_conn_for_test(
        &conn,
        UpsertDailyReviewInput {
            summary: "Evening reflection on the 16th".to_string(),
            mood: Some(4),
            energy_level: Some(3),
            wins: Some("Shipped fix".to_string()),
            blockers: None,
            learnings: None,
            expected_date: "2026-04-16".to_string(),
        },
        "2026-04-17",
    )
    .expect("upsert should succeed for valid expected_date");

    assert_eq!(review.date, "2026-04-16");
    assert_eq!(review.summary, "Evening reflection on the 16th");

    // Confirm the row is on the 16th, not silently misfiled on the 17th.
    let count_16: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_reviews WHERE date = ?",
            params!["2026-04-16"],
            |row| row.get(0),
        )
        .expect("count 16th");
    let count_17: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_reviews WHERE date = ?",
            params!["2026-04-17"],
            |row| row.get(0),
        )
        .expect("count 17th");
    assert_eq!(count_16, 1, "review must be filed on the 16th");
    assert_eq!(count_17, 0, "review must NOT be filed on the 17th");
}

#[test]
fn upsert_daily_review_rejects_stale_expected_date() {
    let conn = setup_sync_test_conn();

    let err = upsert_daily_review_with_conn_for_test(
        &conn,
        UpsertDailyReviewInput {
            summary: "Zombie draft from ten days ago".to_string(),
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            expected_date: "2026-04-07".to_string(),
        },
        "2026-04-17",
    )
    .expect_err("stale expected_date should be rejected");
    assert!(
        err.to_string().contains("stale daily review")
            || err.to_string().contains("days before today"),
        "unexpected error: {err}"
    );

    // Nothing should have been written.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM daily_reviews", [], |row| row.get(0))
        .expect("count reviews");
    assert_eq!(count, 0, "no review should be written on rejection");
}

#[test]
fn get_weekly_review_surfaces_estimate_coverage_metrics() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-review-estimates', 'Review', ?1, '2026-03-15T08:00:00Z', '2026-03-15T08:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert list");

    // Stays raw: TaskBuilder doesn't expose `estimated_minutes`,
    // load-bearing for the weekly review estimate-coverage
    // aggregation. The dynamic `datetime('now', '-N day')` timestamps
    // also have no static equivalent on the builder.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, estimated_minutes, completed_at, version, created_at, updated_at)
         VALUES
         ('done-est-1', 'Estimated', 'completed', 'list-review-estimates', 30, datetime('now', '-1 day'), ?1, datetime('now', '-2 days'), datetime('now', '-1 day')),
         ('done-est-2', 'Estimated again', 'completed', 'list-review-estimates', 60, datetime('now', '-2 days'), ?1, datetime('now', '-3 days'), datetime('now', '-2 days')),
         ('done-no-est', 'No estimate', 'completed', 'list-review-estimates', NULL, datetime('now', '-3 days'), ?1, datetime('now', '-4 days'), datetime('now', '-3 days'))",
        params![TEST_VERSION],
    )
    .expect("insert completed tasks");

    let review = crate::commands::reviews::get_weekly_review_with_conn(&conn)
        .expect("weekly review should succeed");

    assert_eq!(review.completed_this_week.len(), 3);
    assert_eq!(review.completed_with_estimate_count, 2);
    assert!(
        review
            .estimate_coverage_ratio
            .is_some_and(|rate| (rate - (2.0 / 3.0)).abs() < 0.0001),
        "unexpected coverage rate: {:?}",
        review.estimate_coverage_ratio
    );
}
