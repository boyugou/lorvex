use lorvex_domain::naming::{STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_store::open_db_in_memory;
use lorvex_store::test_support::{ListBuilder, TaskBuilder};
use lorvex_workflow::overview::{load_overview_snapshot, OverviewLimits};

const TEST_VERSION: &str = "0000000000000_0000_0000000000000000";
const STALE_TS: &str = "2026-03-01T00:00:00.000Z";

fn seed_overview_fixture(conn: &rusqlite::Connection) -> String {
    conn.execute("DELETE FROM lists WHERE id = 'inbox'", [])
        .expect("remove migration-seeded inbox list for deterministic list cap assertions");

    let today = lorvex_workflow::timezone::today_ymd_for_conn(conn).expect("today");
    let yesterday =
        lorvex_workflow::timezone::date_plus_days_ymd_for_conn(conn, -1).expect("yesterday");
    let tomorrow =
        lorvex_workflow::timezone::date_plus_days_ymd_for_conn(conn, 1).expect("tomorrow");

    ListBuilder::new("list-a")
        .name("Alpha")
        .color(Some("#111111"))
        .icon(Some("circle"))
        .description(Some("Primary work"))
        .ai_notes(Some("AI list note"))
        .version(TEST_VERSION)
        .created_at("2026-03-01T00:00:00.000Z")
        .insert(conn);
    ListBuilder::new("list-b")
        .name("Beta")
        .version(TEST_VERSION)
        .created_at("2026-03-02T00:00:00.000Z")
        .insert(conn);
    ListBuilder::new("list-c")
        .name("Gamma")
        .version(TEST_VERSION)
        .created_at("2026-03-03T00:00:00.000Z")
        .insert(conn);

    TaskBuilder::new("open-overdue")
        .title("Overdue")
        .status(STATUS_OPEN)
        .list_id(Some("list-a"))
        .due_date(Some(&yesterday))
        .priority(Some(1))
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("open-today")
        .title("Today")
        .status(STATUS_OPEN)
        .list_id(Some("list-a"))
        .due_date(Some(&today))
        .priority(Some(2))
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("open-upcoming")
        .title("Upcoming")
        .status(STATUS_OPEN)
        .list_id(Some("list-b"))
        .due_date(Some(&tomorrow))
        .priority(Some(3))
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("completed-today")
        .title("Completed Today")
        .status(STATUS_COMPLETED)
        .list_id(Some("list-b"))
        .completed_at(Some(&lorvex_domain::sync_timestamp_now()))
        .version(TEST_VERSION)
        .insert(conn);
    TaskBuilder::new("someday")
        .title("Someday")
        .status(STATUS_SOMEDAY)
        .list_id(Some("list-c"))
        .version(TEST_VERSION)
        .insert(conn);

    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES (?1, 'Focus on the launch', 'America/Los_Angeles', ?2, ?3, ?3)",
        (&today, TEST_VERSION, STALE_TS),
    )
    .expect("seed current focus");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, 'open-overdue')",
        [&today],
    )
    .expect("seed current focus item");
    conn.execute(
        "INSERT INTO habits (id, name, target_count, archived, version, created_at, updated_at)
         VALUES
         ('habit-1', 'Meditate', 1, 0, ?1, ?2, ?2),
         ('habit-2', 'Archived', 1, 1, ?1, ?2, ?2)",
        (TEST_VERSION, STALE_TS),
    )
    .expect("seed habits");
    conn.execute(
        "INSERT INTO habit_completions
         (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES ('habit-1', ?1, 1, ?2, ?3, ?3)",
        (&today, TEST_VERSION, STALE_TS),
    )
    .expect("seed habit completion");

    today
}

#[test]
fn shared_overview_snapshot_covers_stats_caps_focus_and_habits() {
    let conn = open_db_in_memory().expect("open in-memory db");
    let today = seed_overview_fixture(&conn);

    let snapshot = load_overview_snapshot(
        &conn,
        OverviewLimits {
            lists: Some(2),
            top_tasks: 10,
            recently_completed: 5,
        },
    )
    .expect("load overview snapshot");

    assert_eq!(snapshot.date, today);
    assert_eq!(snapshot.stats.open_count, 3);
    assert_eq!(snapshot.stats.overdue_count, 1);
    assert_eq!(snapshot.stats.today_pool_count, 1);
    assert_eq!(snapshot.stats.attention_count, 2);
    assert_eq!(snapshot.stats.upcoming_week_count, 1);
    assert_eq!(snapshot.stats.completed_today, 1);
    assert_eq!(snapshot.stats.completed_this_week, 1);
    assert_eq!(snapshot.stats.someday_count, 1);

    assert_eq!(snapshot.lists.len(), 2);
    assert_eq!(snapshot.lists_total, 3);
    assert!(snapshot.lists_truncated);
    assert_eq!(snapshot.lists[0].id, "list-a");
    assert_eq!(snapshot.lists[0].open_count, 2);
    assert_eq!(snapshot.lists[1].id, "list-b");
    assert_eq!(snapshot.lists[1].open_count, 1);

    let top_ids: Vec<&str> = snapshot
        .top_by_priority
        .iter()
        .map(|task| task.core().id())
        .collect();
    assert_eq!(top_ids, ["open-overdue", "open-today", "open-upcoming"]);
    assert_eq!(
        snapshot.recently_completed[0].core().id(),
        "completed-today"
    );

    let focus = snapshot.current_focus.expect("current focus");
    assert_eq!(focus.task_count, 1);
    assert_eq!(focus.briefing.as_deref(), Some("Focus on the launch"));
    assert_eq!(focus.timezone.as_deref(), Some("America/Los_Angeles"));

    assert_eq!(snapshot.habits.count, 1);
    assert_eq!(snapshot.habits.completed_today, 1);
}
