use super::*;
use lorvex_domain::naming::{STATUS_COMPLETED, STATUS_SOMEDAY};
use lorvex_store::open_db_in_memory;
use lorvex_store::test_support::{ListBuilder, TaskBuilder};
use rusqlite::Connection;

const TEST_VERSION: &str = "0000000000000_0000_0000000000000000";
const STALE_TS: &str = "2026-03-01T00:00:00Z";

fn seed_review_fixture(conn: &Connection) {
    ListBuilder::new("list-a")
        .name("Alpha")
        .icon(Some("circle"))
        .color(Some("#111111"))
        .version(TEST_VERSION)
        .created_at(STALE_TS)
        .insert(conn);
    ListBuilder::new("list-b")
        .name("Beta")
        .version(TEST_VERSION)
        .created_at(STALE_TS)
        .insert(conn);

    let yesterday = crate::timezone::date_plus_days_ymd_for_conn(conn, -1).expect("yesterday");
    let today = crate::timezone::today_ymd_for_conn(conn).expect("today");
    let tomorrow = crate::timezone::date_plus_days_ymd_for_conn(conn, 1).expect("tomorrow");

    TaskBuilder::new("completed-a")
        .title("Completed A")
        .status(STATUS_COMPLETED)
        .list_id(Some("list-a"))
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("completed-b")
        .title("Completed B")
        .status(STATUS_COMPLETED)
        .list_id(Some("list-a"))
        .version(TEST_VERSION)
        .insert(conn);
    conn.execute(
        "UPDATE tasks SET completed_at = datetime('now', '-1 day') WHERE id = 'completed-a'",
        [],
    )
    .expect("set completed-a timestamp");
    conn.execute(
        "UPDATE tasks SET completed_at = datetime('now', '-2 days') WHERE id = 'completed-b'",
        [],
    )
    .expect("set completed-b timestamp");
    TaskBuilder::new("deferred-high")
        .title("Deferred high")
        .list_id(Some("list-a"))
        .due_date(Some(&tomorrow))
        .defer_count(8)
        .updated_at(STALE_TS)
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("deferred-low")
        .title("Deferred low")
        .list_id(Some("list-a"))
        .due_date(Some(&tomorrow))
        .defer_count(3)
        .updated_at(STALE_TS)
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("overdue")
        .title("Overdue")
        .list_id(Some("list-b"))
        .due_date(Some(&yesterday))
        .updated_at(STALE_TS)
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("today-not-overdue")
        .title("Today")
        .list_id(Some("list-b"))
        .due_date(Some(&today))
        .updated_at(STALE_TS)
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("someday")
        .title("Someday")
        .status(STATUS_SOMEDAY)
        .list_id(Some("list-b"))
        .version(TEST_VERSION)
        .insert(conn);
}

#[test]
fn shared_weekly_review_models_pin_counts_sections_and_ordering() {
    let conn = open_db_in_memory().expect("open in-memory db");
    seed_review_fixture(&conn);

    let read = load_weekly_review(
        &conn,
        WeeklyReviewLimits {
            completed_this_week: 10,
            stalled_lists: 10,
            frequently_deferred: 10,
            overdue_tasks: 10,
            someday_items: 10,
        },
    )
    .expect("load app model");
    let snapshot = load_weekly_review_snapshot(
        &conn,
        WeeklyReviewSnapshotLimits {
            top_completed: 10,
            stalled_lists: 10,
            frequently_deferred: 10,
            someday_items: 10,
        },
    )
    .expect("load snapshot");
    let brief = load_weekly_review_brief(
        &conn,
        WeeklyReviewBriefLimits {
            completed_this_week: 10,
            stalled_lists: 10,
            frequently_deferred: 10,
            someday_items: 10,
        },
    )
    .expect("load brief");

    assert_eq!(read.counts.completed_this_week, 2);
    assert_eq!(
        snapshot.counts.completed_this_week,
        read.counts.completed_this_week
    );
    assert_eq!(
        brief.section_meta.completed_this_week.total_matching,
        read.counts.completed_this_week
    );
    assert_eq!(read.counts.overdue_open, 1);
    assert_eq!(brief.overdue_count, 1);

    let completed_ids: Vec<&str> = read
        .completed_this_week
        .iter()
        .map(|task| task.id.as_str())
        .collect();
    assert_eq!(completed_ids, ["completed-a", "completed-b"]);
    assert_eq!(snapshot.top_completed, read.completed_this_week);
    assert_eq!(brief.completed_this_week, read.completed_this_week);

    let deferred_ids: Vec<&str> = read
        .frequently_deferred
        .iter()
        .map(|task| task.id.as_str())
        .collect();
    assert_eq!(deferred_ids, ["deferred-high", "deferred-low"]);
    assert_eq!(snapshot.frequently_deferred, read.frequently_deferred);
    assert_eq!(brief.frequently_deferred, read.frequently_deferred);

    let stalled_ids: Vec<&str> = read
        .stalled_lists
        .iter()
        .map(|list| list.id.as_str())
        .collect();
    assert_eq!(stalled_ids, ["list-a", "list-b"]);
    assert_eq!(snapshot.stalled_lists, read.stalled_lists);
    assert_eq!(brief.stalled_lists, read.stalled_lists);
}
