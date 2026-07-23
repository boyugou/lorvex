use super::*;
use crate::open_db_in_memory;

const TASK_A: &str = "01900000-0000-7000-8000-00000000da01";
const TASK_B: &str = "01900000-0000-7000-8000-00000000da02";
const LIST_A: &str = "list-daily-read";

fn make_params<'a>(
    date: &'a str,
    summary: &'a str,
    timezone: &'a str,
    version: &'a str,
    now: &'a str,
) -> UpsertDailyReviewParams<'a> {
    UpsertDailyReviewParams {
        date,
        summary,
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone,
        version,
        now,
    }
}

fn seed_daily_review_row(conn: &Connection, date: &str, summary: &str) {
    let params = UpsertDailyReviewParams {
        date,
        summary,
        mood: Some(4),
        energy_level: Some(3),
        wins: Some("Shipped"),
        blockers: Some("None"),
        learnings: Some("Use shared projections"),
        ai_synthesis: Some("Steady progress"),
        timezone: "UTC",
        version: "0000000000001_0000_0000000000000000",
        now: "2026-04-01T00:00:00Z",
    };
    assert!(upsert_daily_review(conn, &params).expect("seed review"));
}

fn seed_daily_review_links(conn: &Connection, date: &str) {
    crate::test_support::fixtures::ListBuilder::new(LIST_A)
        .name("Daily Review")
        .insert(conn);
    crate::test_support::fixtures::TaskBuilder::new(TASK_A)
        .title("Read model task A")
        .list_id(Some(LIST_A))
        .insert(conn);
    crate::test_support::fixtures::TaskBuilder::new(TASK_B)
        .title("Read model task B")
        .list_id(Some(LIST_A))
        .insert(conn);
    materialize_review_task_links(conn, date, &[TASK_A.to_string(), TASK_B.to_string()])
        .expect("task links");
    materialize_review_list_links(conn, date, &[LIST_A.to_string()]).expect("list links");
}

#[test]
fn get_daily_review_row_maps_explicit_projection_and_embeds_links() {
    let conn = open_db_in_memory().unwrap();
    seed_daily_review_row(&conn, "2026-04-01", "Shared row");
    seed_daily_review_links(&conn, "2026-04-01");

    let row = get_daily_review_row(&conn, "2026-04-01")
        .expect("read review")
        .expect("review exists");

    assert_eq!(row.date, "2026-04-01");
    assert_eq!(row.summary, "Shared row");
    assert_eq!(row.mood, Some(4));
    assert_eq!(row.energy_level, Some(3));
    assert_eq!(row.wins.as_deref(), Some("Shipped"));
    assert_eq!(row.blockers.as_deref(), Some("None"));
    assert_eq!(row.learnings.as_deref(), Some("Use shared projections"));
    assert_eq!(row.ai_synthesis.as_deref(), Some("Steady progress"));
    assert_eq!(row.timezone.as_deref(), Some("UTC"));
    assert_eq!(row.version, "0000000000001_0000_0000000000000000");
    assert_eq!(row.created_at, "2026-04-01T00:00:00Z");
    assert_eq!(row.updated_at, "2026-04-01T00:00:00Z");
    assert_eq!(row.linked_task_ids, vec![TASK_A, TASK_B]);
    assert_eq!(row.linked_list_ids, vec![LIST_A]);
}

#[test]
fn list_daily_review_rows_pages_history_with_total_count() {
    let conn = open_db_in_memory().unwrap();
    seed_daily_review_row(&conn, "2026-04-01", "Older");
    seed_daily_review_row(&conn, "2026-04-02", "Middle");
    seed_daily_review_row(&conn, "2026-04-03", "Newest");
    seed_daily_review_links(&conn, "2026-04-03");

    let page = list_daily_review_rows(
        &conn,
        DailyReviewHistoryQuery {
            since: Some("2026-04-02"),
            limit: 1,
            offset: 0,
        },
    )
    .expect("history page");

    assert_eq!(page.total_matching, 2);
    assert_eq!(page.rows.len(), 1);
    assert_eq!(page.rows[0].date, "2026-04-03");
    assert_eq!(page.rows[0].linked_task_ids, vec![TASK_A, TASK_B]);
}

#[test]
fn sets_timezone_on_create() {
    let conn = open_db_in_memory().unwrap();

    let params = UpsertDailyReviewParams {
        timezone: "America/New_York",
        mood: Some(4),
        ..make_params(
            "2026-03-27",
            "Good day",
            "America/New_York",
            "v1",
            "2026-03-27T20:00:00Z",
        )
    };
    upsert_daily_review(&conn, &params).unwrap();

    let (tz, mood): (Option<String>, Option<i64>) = conn
        .query_row(
            "SELECT timezone, mood FROM daily_reviews WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(tz.as_deref(), Some("America/New_York"));
    assert_eq!(mood, Some(4));
}

#[test]
fn preserves_timezone_on_update() {
    let conn = open_db_in_memory().unwrap();

    // Create with America/New_York
    let params1 = make_params(
        "2026-03-27",
        "Morning review",
        "America/New_York",
        "v1",
        "2026-03-27T08:00:00Z",
    );
    upsert_daily_review(&conn, &params1).unwrap();

    // Update with Asia/Tokyo — timezone should be preserved as America/New_York
    let params2 = UpsertDailyReviewParams {
        date: "2026-03-27",
        summary: "Evening update",
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone: "Asia/Tokyo",
        version: "v2",
        now: "2026-03-27T20:00:00Z",
    };
    upsert_daily_review(&conn, &params2).unwrap();

    let (tz, summary, version): (Option<String>, String, String) = conn
        .query_row(
            "SELECT timezone, summary, version FROM daily_reviews WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(tz.as_deref(), Some("America/New_York"));
    assert_eq!(summary, "Evening update");
    assert_eq!(version, "v2");
}

#[test]
fn coalesce_preserves_existing_values_when_none() {
    let conn = open_db_in_memory().unwrap();

    // Create with mood and wins
    let params1 = UpsertDailyReviewParams {
        date: "2026-03-27",
        summary: "First entry",
        mood: Some(4),
        energy_level: Some(3),
        wins: Some("Shipped feature"),
        blockers: Some("CI flaky"),
        learnings: None,
        ai_synthesis: None,
        timezone: "UTC",
        version: "v1",
        now: "2026-03-27T08:00:00Z",
    };
    upsert_daily_review(&conn, &params1).unwrap();

    // Update with None mood and None wins — existing values should be preserved
    let params2 = UpsertDailyReviewParams {
        date: "2026-03-27",
        summary: "Updated summary",
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: Some("Learned testing"),
        ai_synthesis: None,
        timezone: "UTC",
        version: "v2",
        now: "2026-03-27T12:00:00Z",
    };
    upsert_daily_review(&conn, &params2).unwrap();

    let row = conn
        .query_row(
            "SELECT summary, mood, energy_level, wins, blockers, learnings \
             FROM daily_reviews WHERE date = '2026-03-27'",
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<i64>>(1)?,
                    row.get::<_, Option<i64>>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                ))
            },
        )
        .unwrap();

    assert_eq!(row.0, "Updated summary"); // summary always overwrites
    assert_eq!(row.1, Some(4)); // mood preserved (was None in update)
    assert_eq!(row.2, Some(3)); // energy_level preserved
    assert_eq!(row.3.as_deref(), Some("Shipped feature")); // wins preserved
    assert_eq!(row.4.as_deref(), Some("CI flaky")); // blockers preserved
    assert_eq!(row.5.as_deref(), Some("Learned testing")); // learnings set from update
}

#[test]
fn amend_daily_review_updates_specified_fields_only() {
    let conn = open_db_in_memory().unwrap();

    // Create a review first
    let create_params = UpsertDailyReviewParams {
        date: "2026-03-28",
        summary: "Initial review",
        mood: Some(3),
        energy_level: Some(4),
        wins: Some("Shipped CLI"),
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone: "America/Los_Angeles",
        version: "v1",
        now: "2026-03-28T08:00:00Z",
    };
    upsert_daily_review(&conn, &create_params).unwrap();

    // Amend only ai_synthesis — other fields should remain unchanged
    let amend_params = AmendDailyReviewParams {
        date: "2026-03-28",
        summary: None,
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: Some("AI summary of the day"),
        timezone_backfill: None,
        version: "v2",
        now: "2026-03-28T20:00:00Z",
    };
    let amended = amend_daily_review(&conn, &amend_params).unwrap();
    assert!(amended);

    let (summary, mood, ai_synthesis, version): (String, Option<i64>, Option<String>, String) =
        conn.query_row(
            "SELECT summary, mood, ai_synthesis, version FROM daily_reviews WHERE date = '2026-03-28'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();

    assert_eq!(summary, "Initial review"); // unchanged
    assert_eq!(mood, Some(3)); // unchanged
    assert_eq!(ai_synthesis.as_deref(), Some("AI summary of the day")); // amended
    assert_eq!(version, "v2"); // updated
}

/// a local-write `upsert_daily_review`
/// with a version that doesn't strictly exceed the row's current
/// version MUST be a no-op. Pre-fix the upsert blindly overwrote
/// the row, regressing version + summary in the process.
#[test]
fn upsert_daily_review_lww_gate_rejects_stale_version() {
    let conn = open_db_in_memory().unwrap();

    // Seed at v2.
    let p1 = UpsertDailyReviewParams {
        date: "2026-04-26",
        summary: "winning version",
        mood: Some(5),
        energy_level: Some(4),
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone: "UTC",
        version: "0002000000000_0001_winnerwinnerwi",
        now: "2026-04-26T08:00:00Z",
    };
    let applied1 = upsert_daily_review(&conn, &p1).unwrap();
    assert!(applied1, "initial insert must apply");

    // Stale write at v1 must NOT regress version, summary, or mood.
    let p2 = UpsertDailyReviewParams {
        date: "2026-04-26",
        summary: "stale version",
        mood: Some(1),
        energy_level: Some(1),
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone: "UTC",
        version: "0001000000000_0001_loseroloseroloser",
        now: "2026-04-26T09:00:00Z",
    };
    let applied2 = upsert_daily_review(&conn, &p2).unwrap();
    assert!(!applied2, "stale stamp under LWW gate must be a no-op");

    let (summary, mood, version): (String, Option<i64>, String) = conn
        .query_row(
            "SELECT summary, mood, version FROM daily_reviews WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(summary, "winning version");
    assert_eq!(mood, Some(5));
    assert_eq!(version, "0002000000000_0001_winnerwinnerwi");
}

#[test]
fn amend_daily_review_returns_false_for_nonexistent_date() {
    let conn = open_db_in_memory().unwrap();

    let amend_params = AmendDailyReviewParams {
        date: "2099-12-31",
        summary: Some("Should not exist"),
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        timezone_backfill: None,
        version: "v1",
        now: "2099-12-31T00:00:00Z",
    };
    let amended = amend_daily_review(&conn, &amend_params).unwrap();
    assert!(!amended);
}
