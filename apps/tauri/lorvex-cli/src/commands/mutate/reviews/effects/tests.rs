use super::validation::normalize_review_link_ids;
use super::{
    add_daily_review_with_conn, amend_daily_review_with_conn, get_daily_review_history_with_conn,
    get_daily_review_with_conn, get_weekly_review_brief_with_conn,
    get_weekly_review_snapshot_with_conn, DailyReviewAddFields, DailyReviewAmendFields,
};
use crate::commands::shared::test_support::seed_task;
use chrono::Utc;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;

fn seed_daily_review_with_version(
    conn: &rusqlite::Connection,
    date: &str,
    summary: &str,
    version: &str,
) {
    conn.execute(
        "INSERT INTO daily_reviews \
         (date, summary, timezone, version, created_at, updated_at) \
         VALUES (?1, ?2, 'UTC', ?3, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
        rusqlite::params![date, summary, version],
    )
    .expect("seed daily review");
}

fn count_rows(conn: &rusqlite::Connection, sql: &str) -> i64 {
    conn.query_row(sql, [], |row| row.get(0))
        .expect("count rows")
}

fn count_rows_for_review_date(conn: &rusqlite::Connection, sql: &str, review_date: &str) -> i64 {
    conn.query_row(sql, [review_date], |row| row.get(0))
        .expect("count rows")
}

#[test]
fn daily_review_add_amend_history_with_conn_syncs_links_and_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "01900000-0000-7000-8000-00000000aa01",
        "Review task A",
        "open",
    );
    seed_task(
        &conn,
        "01900000-0000-7000-8000-00000000aa02",
        "Review task B",
        "open",
    );
    let review_date = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("today");

    let added = add_daily_review_with_conn(
        &mut conn,
        DailyReviewAddFields {
            date: Some(&review_date),
            summary: "Shipped dated focus support",
            mood: Some(4),
            energy_level: Some(3),
            wins: Some("CLI parity improved"),
            blockers: None,
            learnings: Some("Keep changes scriptable"),
            ai_synthesis: Some("Momentum remains high"),
            linked_task_ids: &["01900000-0000-7000-8000-00000000aa01".to_string()],
            linked_list_ids: &["inbox".to_string()],
        },
    )
    .expect("add review");
    assert_eq!(added.date, review_date);
    assert_eq!(
        added.linked_task_ids,
        vec!["01900000-0000-7000-8000-00000000aa01"]
    );
    assert_eq!(added.linked_list_ids, vec!["inbox"]);

    let amended = amend_daily_review_with_conn(
        &mut conn,
        DailyReviewAmendFields {
            date: &review_date,
            summary: Some("Updated summary"),
            mood: None,
            energy_level: Some(5),
            wins: None,
            blockers: Some("No blockers"),
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: Some(&["01900000-0000-7000-8000-00000000aa02".to_string()]),
            linked_list_ids: Some(&["inbox".to_string()]),
        },
    )
    .expect("amend review");
    assert_eq!(amended.summary, "Updated summary");
    assert_eq!(amended.energy_level, Some(5));
    assert_eq!(
        amended.linked_task_ids,
        vec!["01900000-0000-7000-8000-00000000aa02"]
    );

    let loaded = get_daily_review_with_conn(&conn, Some(&review_date))
        .expect("get review")
        .expect("review exists");
    assert_eq!(loaded.blockers.as_deref(), Some("No blockers"));

    let history =
        get_daily_review_history_with_conn(&conn, Some(&review_date), 10).expect("history");
    assert_eq!(history.len(), 1);

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_DAILY_REVIEW, review_date.as_str()],
            |row| row.get(0),
        )
        .expect("count review outbox");
    assert_eq!(outbox_count, 1);

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_DAILY_REVIEW, review_date.as_str()],
            |row| row.get(0),
        )
        .expect("count review changelog");
    assert_eq!(changelog_count, 2);
}

#[test]
fn daily_review_add_rejects_stale_lww_parent_before_links_sync_or_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "01900000-0000-7000-8000-00000000aa01",
        "Review task A",
        "open",
    );
    crate::hlc_guard::next_hlc_version(&conn).expect("initialize CLI HLC before stale seed");
    let review_date = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("today");
    seed_daily_review_with_version(
        &conn,
        &review_date,
        "newer peer state",
        "9999999999999_9999_ffffffffffffffff",
    );

    let err = add_daily_review_with_conn(
        &mut conn,
        DailyReviewAddFields {
            date: Some(&review_date),
            summary: "stale local attempt",
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: &["01900000-0000-7000-8000-00000000aa01".to_string()],
            linked_list_ids: &["inbox".to_string()],
        },
    )
    .expect_err("stale daily review add must reject before side effects");

    match err {
        crate::error::CliError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, ENTITY_DAILY_REVIEW);
            assert_eq!(id, review_date);
        }
        other => panic!("expected daily-review StaleVersion, got {other:?}"),
    }

    let (summary, version): (String, String) = conn
        .query_row(
            "SELECT summary, version FROM daily_reviews WHERE date = ?1",
            [&review_date],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load unchanged review");
    assert_eq!(summary, "newer peer state");
    assert_eq!(version, "9999999999999_9999_ffffffffffffffff");
    assert_eq!(
        count_rows_for_review_date(
            &conn,
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            &review_date,
        ),
        0,
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'daily_review'",
        ),
        0,
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'daily_review'",
        ),
        0,
    );
}

#[test]
fn daily_review_amend_rejects_stale_lww_parent_before_links_sync_or_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "01900000-0000-7000-8000-00000000aa01",
        "Review task A",
        "open",
    );
    crate::hlc_guard::next_hlc_version(&conn).expect("initialize CLI HLC before stale seed");
    let review_date = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("today");
    seed_daily_review_with_version(
        &conn,
        &review_date,
        "newer peer state",
        "9999999999999_9999_ffffffffffffffff",
    );

    let err = amend_daily_review_with_conn(
        &mut conn,
        DailyReviewAmendFields {
            date: &review_date,
            summary: Some("stale amend"),
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: Some(&["01900000-0000-7000-8000-00000000aa01".to_string()]),
            linked_list_ids: Some(&["inbox".to_string()]),
        },
    )
    .expect_err("stale daily review amend must reject before side effects");

    match err {
        crate::error::CliError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, ENTITY_DAILY_REVIEW);
            assert_eq!(id, review_date);
        }
        other => panic!("expected daily-review StaleVersion, got {other:?}"),
    }

    let (summary, version): (String, String) = conn
        .query_row(
            "SELECT summary, version FROM daily_reviews WHERE date = ?1",
            [&review_date],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load unchanged review");
    assert_eq!(summary, "newer peer state");
    assert_eq!(version, "9999999999999_9999_ffffffffffffffff");
    assert_eq!(
        count_rows_for_review_date(
            &conn,
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            &review_date,
        ),
        0,
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'daily_review'",
        ),
        0,
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'daily_review'",
        ),
        0,
    );
}

#[test]
fn weekly_review_snapshot_with_conn_summarizes_trailing_window() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    conn.execute(
            "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
             VALUES ('timezone', '\"UTC\"', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z')",
            [],
        )
        .expect("seed timezone preference");
    conn.execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('list-stalled', 'Stalled Work', '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
            [],
        )
        .expect("seed stalled list");

    let now = lorvex_domain::sync_timestamp_now();
    let yesterday =
        lorvex_domain::date_plus_days_ymd_for_timezone_name(Utc::now(), Some("UTC"), -1);
    seed_task(
        &conn,
        "task-week-completed",
        "Completed this week",
        "completed",
    );
    conn.execute(
        "UPDATE tasks
             SET completed_at = ?1, created_at = ?1, updated_at = ?1,
                 estimated_minutes = 30
             WHERE id = 'task-week-completed'",
        [&now],
    )
    .expect("mark completed task");
    seed_task(&conn, "task-week-overdue", "Overdue work", "open");
    conn.execute(
        "UPDATE tasks SET due_date = ?1, created_at = ?2, updated_at = ?2
             WHERE id = 'task-week-overdue'",
        rusqlite::params![yesterday, now],
    )
    .expect("mark overdue task");
    seed_task(&conn, "task-week-deferred", "Deferred work", "open");
    conn.execute(
        "UPDATE tasks
             SET defer_count = 3, created_at = ?1, updated_at = ?1
             WHERE id = 'task-week-deferred'",
        [&now],
    )
    .expect("mark deferred task");
    seed_task(&conn, "task-week-someday", "Someday work", "someday");
    conn.execute(
        "UPDATE tasks SET created_at = ?1, updated_at = ?1 WHERE id = 'task-week-someday'",
        [&now],
    )
    .expect("mark someday task recent");
    seed_task(&conn, "task-week-stalled", "Stalled task", "open");
    conn.execute(
        "UPDATE tasks
             SET list_id = 'list-stalled', updated_at = '2000-01-01T00:00:00Z'
             WHERE id = 'task-week-stalled'",
        [],
    )
    .expect("mark stalled task");

    let snapshot =
        get_weekly_review_snapshot_with_conn(&conn, 3, 3, 3, 3).expect("weekly snapshot");

    assert_eq!(snapshot.window.days, 7);
    assert_eq!(snapshot.counts.completed_this_week, 1);
    assert_eq!(snapshot.counts.overdue_open, 1);
    assert_eq!(snapshot.counts.deferred_open, 1);
    assert_eq!(snapshot.counts.someday, 1);
    assert_eq!(snapshot.estimate_summary.completed_total, 1);
    assert_eq!(snapshot.estimate_summary.estimate_coverage_ratio, Some(1.0));
    assert_eq!(
        snapshot
            .top_completed
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        vec!["task-week-completed"]
    );
    assert_eq!(snapshot.stalled_lists[0].id, "list-stalled");
    assert_eq!(snapshot.frequently_deferred[0].id, "task-week-deferred");
    assert_eq!(snapshot.someday_items[0].id, "task-week-someday");
}

#[test]
fn weekly_review_brief_with_conn_reports_section_meta_and_truncation() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    conn.execute(
            "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
             VALUES ('timezone', '\"UTC\"', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z')",
            [],
        )
        .expect("seed timezone preference");

    let now = lorvex_domain::sync_timestamp_now();

    // Three completed-this-week tasks; brief asks for two and must
    // report `total_matching = 3, truncated = true`.
    for index in 0..3 {
        let id = format!("brief-completed-{index}");
        seed_task(&conn, &id, &format!("Completed {index}"), "completed");
        conn.execute(
            "UPDATE tasks
                 SET completed_at = ?1, created_at = ?1, updated_at = ?1,
                     estimated_minutes = 20
                 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .expect("mark completed");
    }

    // Two someday rows; ask for one and confirm truncation.
    for index in 0..2 {
        let id = format!("brief-someday-{index}");
        seed_task(&conn, &id, &format!("Someday {index}"), "someday");
        conn.execute(
            "UPDATE tasks SET created_at = ?1, updated_at = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .expect("touch someday");
    }

    let brief = get_weekly_review_brief_with_conn(&conn, 2, 1, 1, 1).expect("weekly review brief");

    assert_eq!(brief.completed_this_week.len(), 2);
    assert_eq!(brief.section_meta.completed_this_week.limit, 2);
    assert_eq!(brief.section_meta.completed_this_week.total_matching, 3);
    assert_eq!(brief.section_meta.completed_this_week.returned, 2);
    assert!(brief.section_meta.completed_this_week.truncated);

    assert_eq!(brief.someday_items.len(), 1);
    assert_eq!(brief.section_meta.someday_items.total_matching, 2);
    assert!(brief.section_meta.someday_items.truncated);

    assert_eq!(brief.section_meta.frequently_deferred.total_matching, 0);
    assert!(!brief.section_meta.frequently_deferred.truncated);
    assert!(brief.frequently_deferred.is_empty());

    assert_eq!(brief.window.days, 7);
    assert_eq!(brief.created_this_week, 5);
    assert_eq!(brief.estimate_summary.completed_total, 3);
}

/// `normalize_review_link_ids` must reject
/// non-UUID-shaped ids at the trust boundary. Pre-fix this site
/// only checked emptiness post-trim, so callers that bypass the
/// clap parser (programmatic test callers, `run_review_add`
/// when consuming JSON) could land arbitrary strings into
/// `daily_review_task_links`. List links may carry the
/// schema-seeded `inbox` sentinel (the canonical default list);
/// task links must always be UUIDs.
#[test]
fn normalize_review_link_ids_rejects_non_uuid_input() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let bad_task_ids = vec!["not-a-uuid".to_string()];
    let err = normalize_review_link_ids("linked_task_ids", &bad_task_ids)
        .expect_err("non-uuid task id must be rejected");
    assert!(
        matches!(err, crate::error::CliError::Validation(_)),
        "expected Validation error; got {err:?}"
    );

    let bad_list_ids = vec!["arbitrary-string".to_string()];
    let err = normalize_review_link_ids("linked_list_ids", &bad_list_ids)
        .expect_err("non-uuid list id must be rejected");
    assert!(
        matches!(err, crate::error::CliError::Validation(_)),
        "expected Validation error; got {err:?}"
    );

    // Valid UUIDs pass through.
    let good_task_ids = vec!["01900000-0000-7000-8000-000000000001".to_string()];
    let normalized = normalize_review_link_ids("linked_task_ids", &good_task_ids)
        .expect("uuid-shaped id should pass");
    assert_eq!(normalized, good_task_ids);

    // The `inbox` sentinel is allowed only for the
    // `linked_list_ids` field (carry-through for the schema-seeded
    // sentinel list).
    let inbox_only = vec!["inbox".to_string()];
    normalize_review_link_ids("linked_list_ids", &inbox_only)
        .expect("inbox sentinel must pass for list links");
    normalize_review_link_ids("linked_task_ids", &inbox_only)
        .expect_err("inbox sentinel must NOT pass for task links");
}
