use chrono::Duration;
use lorvex_domain::query::{OverduePredicate, Pagination, TodayPredicate, UpcomingPredicate};
use lorvex_store::repositories::ai_changelog_query::{self, AiChangelogQuery};
use lorvex_store::repositories::task::dependencies::graph;
use lorvex_store::repositories::task::read;
use lorvex_store::repositories::task::reminders;

use crate::commands::shared::today_ymd_for_conn;

fn today_naive(conn: &rusqlite::Connection) -> chrono::NaiveDate {
    let ymd = today_ymd_for_conn(conn).expect("resolve today");
    chrono::NaiveDate::parse_from_str(&ymd, "%Y-%m-%d").expect("parse today")
}

#[test]
fn query_commands_surface_seeded_rows() {
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let today_date = today_naive(&conn);
    let today = today_date.format("%Y-%m-%d").to_string();
    let tomorrow = (today_date + Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    // every fixture version is a digit-prefixed HLC so it
    // sorts strictly below every realistic runtime HLC. Per-row suffixes
    // (`test0000`..`test0007`) preserve the original stable-tiebreak
    // ordering between tasks/reminders/deps that downstream assertions
    // implicitly rely on (HLC ordering is `(physical_ms, counter,
    // device_suffix)` lex; here only the suffix differs).
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-1', 'Test', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed list");
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new("task-today")
        .title("Today task")
        .version("0000000000000_0000_test0001")
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("list-1"))
        .due_date(Some(&today))
        .insert(&conn);
    TaskBuilder::new("task-overdue")
        .title("Overdue task")
        .version("0000000000000_0000_test0002")
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("list-1"))
        .due_date(Some("2020-01-01"))
        .insert(&conn);
    TaskBuilder::new("task-upcoming")
        .title("Upcoming task")
        .version("0000000000000_0000_test0003")
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("list-1"))
        .planned_date(Some(&tomorrow))
        .insert(&conn);
    TaskBuilder::new("task-deferred")
        .title("Deferred task")
        .version("0000000000000_0000_test0004")
        .created_at("2026-03-30T00:00:00Z")
        .updated_at("2026-03-31T00:00:00Z")
        .list_id(Some("list-1"))
        .planned_date(Some(&tomorrow))
        .defer_count(2)
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, created_at, version)
         VALUES
         ('reminder-due', 'task-today', '2026-03-23T08:00:00.000000Z', '2026-03-23T07:00:00.000000Z', '0000000000000_0000_test0005'),
         ('reminder-upcoming', 'task-upcoming', '2026-03-23T10:00:00.000000Z', '2026-03-23T07:00:00.000000Z', '0000000000000_0000_test0006')",
        [],
    )
    .expect("seed reminders");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('task-deferred', 'task-upcoming', '0000000000000_0000_test0007', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed dependency");
    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
         VALUES ('change-task', '2026-03-31T00:00:00.000000Z', 'update', 'task', 'task-today', 'Updated task', 'ai', 'cli_test')",
        [],
    )
    .expect("seed changelog");

    let today_rows = read::get_today_tasks(
        &conn,
        &TodayPredicate {
            date: today_naive(&conn),
        },
        Pagination {
            limit: 10,
            offset: 0,
        },
    )
    .expect("load today rows");
    assert!(today_rows.iter().any(|row| row.core().id() == "task-today"));

    let overdue_rows = read::get_overdue_tasks(
        &conn,
        &OverduePredicate {
            as_of_date: today_naive(&conn),
        },
        Pagination {
            limit: 10,
            offset: 0,
        },
    )
    .expect("load overdue rows");
    assert!(overdue_rows
        .iter()
        .any(|row| row.core().id() == "task-overdue"));

    let upcoming_rows = read::get_upcoming_tasks(
        &conn,
        &UpcomingPredicate {
            from_date: today_naive(&conn),
            days: 7,
        },
        Pagination {
            limit: 10,
            offset: 0,
        },
    )
    .expect("load upcoming rows");
    assert!(upcoming_rows
        .iter()
        .any(|row| row.core().id() == "task-upcoming"));

    let deferred_rows = read::get_deferred_tasks(
        &conn,
        Some("list-1"),
        Pagination {
            limit: 10,
            offset: 0,
        },
    )
    .expect("load deferred rows");
    assert_eq!(deferred_rows.len(), 1);
    assert_eq!(deferred_rows[0].core().id(), "task-deferred");

    let snapshot = super::tasks::get_deferred_tasks_snapshot_with_conn(&conn, Some("list-1"), 10)
        .expect("load deferred snapshot");
    assert_eq!(snapshot.total_matching, 1);
    assert_eq!(snapshot.tasks[0].defer_count, 2);

    let listed = read::list_tasks(
        &conn,
        &read::ListTasksQuery {
            list_id: Some("list-1".to_string()),
            status: read::TaskStatusListFilter::Open,
            limit: 2,
            ..read::ListTasksQuery::default()
        },
    )
    .expect("load filtered task list");
    assert_eq!(listed.total_matching, 4);
    assert_eq!(listed.rows.len(), 2);

    let graph = graph::get_dependency_graph(
        &conn,
        &graph::DependencyGraphParams {
            list_id: Some("list-1".to_string()),
            limit_nodes: 10,
            limit_edges: 10,
            ..graph::DependencyGraphParams::default()
        },
    )
    .expect("load dependency graph");
    assert_eq!(graph.nodes.len(), 2);
    assert_eq!(graph.edges.len(), 1);
    assert_eq!(graph.edges[0].task_id, "task-deferred");
    assert_eq!(graph.edges[0].depends_on_task_id, "task-upcoming");

    let due = reminders::get_due_task_reminders(&conn, "2026-03-23T09:00:00.000000Z", 10)
        .expect("load due reminders");
    let due_snapshot = super::reminders::task_reminder_snapshot(None, 10, due);
    assert_eq!(due_snapshot.total_matching, 1);
    assert_eq!(due_snapshot.reminders[0].id, "reminder-due");

    let upcoming = reminders::get_upcoming_task_reminders_until(
        &conn,
        "2026-03-23T09:00:00.000000Z",
        "2026-03-23T11:00:00.000000Z",
        10,
    )
    .expect("load upcoming reminders");
    let upcoming_snapshot = super::reminders::task_reminder_snapshot(Some(2), 10, upcoming);
    assert_eq!(upcoming_snapshot.hours_window, Some(2));
    assert_eq!(upcoming_snapshot.reminders[0].id, "reminder-upcoming");

    let changelog = ai_changelog_query::list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(std::num::NonZeroU32::new(10).unwrap()).with_entity_id("task-today"),
    )
    .expect("load changelog");
    assert_eq!(changelog.len(), 1);
    assert_eq!(changelog[0].id, "change-task");
}

#[test]
fn cli_summary_counts_exclude_archived_active_status_tasks() {
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-archive-counts', 'Archive Counts', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed list");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('tag-archive-counts', 'Archive Counts', 'archive-counts', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed tag");

    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new("task-live-open")
        .title("Live open")
        .status(lorvex_domain::naming::STATUS_OPEN)
        .list_id(Some("list-archive-counts"))
        .insert(&conn);
    TaskBuilder::new("task-archived-open")
        .title("Archived open")
        .status(lorvex_domain::naming::STATUS_OPEN)
        .list_id(Some("list-archive-counts"))
        .archived_at(Some("2026-04-01T00:00:00.000000Z"))
        .insert(&conn);
    TaskBuilder::new("task-archived-someday")
        .title("Archived someday")
        .status(lorvex_domain::naming::STATUS_SOMEDAY)
        .list_id(Some("list-archive-counts"))
        .archived_at(Some("2026-04-01T00:00:00.000000Z"))
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES
         ('task-live-open', 'tag-archive-counts', '0000000000000_0000_tag000000000001', '2026-03-30T00:00:00Z'),
         ('task-archived-open', 'tag-archive-counts', '0000000000000_0000_tag000000000002', '2026-03-30T00:00:00Z'),
         ('task-archived-someday', 'tag-archive-counts', '0000000000000_0000_tag000000000003', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed task tags");

    let today_hint_open = super::tasks::open_task_count_for_today_hint_with_conn(&conn)
        .expect("count open tasks for today hint");
    assert_eq!(today_hint_open, 1);

    let list_health =
        super::lists::get_list_health_snapshot_with_conn(&conn, 50).expect("load list health");
    let row = list_health
        .lists
        .iter()
        .find(|row| row.id == "list-archive-counts")
        .expect("seeded list health row");
    assert_eq!(row.open_count, 1);

    let tags = super::tags::get_tag_summaries_with_conn(&conn).expect("load tag summaries");
    let tag = tags
        .iter()
        .find(|tag| tag.id == "tag-archive-counts")
        .expect("seeded tag summary");
    assert_eq!(tag.task_count, 1);
}
