use rusqlite::{params, Connection};

use super::{get_due_task_reminders, get_reminders_for_task, get_upcoming_task_reminders_until};
use crate::test_support::{test_conn, TaskBuilder};
use lorvex_domain::TaskId;

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

const NOW: &str = "2026-05-03T12:00:00.000Z";

fn insert_reminder(
    conn: &Connection,
    id: &str,
    task_id: &str,
    reminder_at: &str,
    dismissed_at: Option<&str>,
    cancelled_at: Option<&str>,
) {
    conn.execute(
        "INSERT INTO task_reminders \
         (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            id,
            task_id,
            reminder_at,
            dismissed_at,
            cancelled_at,
            "v1",
            "2026-05-01T00:00:00.000Z",
        ],
    )
    .expect("insert task_reminder");
}

fn set_delivery_state(conn: &Connection, reminder_id: &str, state: &str) {
    conn.execute(
        "INSERT INTO task_reminder_delivery_state \
         (reminder_id, delivery_state, updated_at) \
         VALUES (?1, ?2, ?3)",
        params![reminder_id, state, "2026-05-01T00:00:00.000Z"],
    )
    .expect("insert delivery_state");
}

fn archive_task(conn: &Connection, task_id: &str) {
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = ?2",
        params!["2026-05-02T00:00:00.000Z", task_id],
    )
    .expect("archive task");
}

#[test]
fn due_reminders_returns_pending_open_undismissed() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    insert_reminder(
        &conn,
        "rem-1",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );

    let result = get_due_task_reminders(&conn, NOW, 10).expect("query");
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].id, "rem-1");
    // TaskBuilder seeds `title = "Seed Task"` by default; the join
    // surface is what matters here, not the literal value.
    assert_eq!(result.rows[0].task_title, "Seed Task");
    // Default delivery state is 'pending' via COALESCE.
    assert_eq!(result.rows[0].delivery_state, "pending");
    assert_eq!(result.total_matching, 1);
}

#[test]
fn due_reminders_excludes_future_reminders() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    insert_reminder(
        &conn,
        "rem-future",
        "task-1",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );

    let result = get_due_task_reminders(&conn, NOW, 10).expect("query");
    assert!(result.rows.is_empty());
}

#[test]
fn due_reminders_excludes_dismissed_cancelled_delivered() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    // Three reminders, all due. Each is filtered out for a different reason.
    insert_reminder(
        &conn,
        "rem-dismissed",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        Some("2026-05-03T11:30:00.000Z"),
        None,
    );
    insert_reminder(
        &conn,
        "rem-cancelled",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        Some("2026-05-03T11:30:00.000Z"),
    );
    insert_reminder(
        &conn,
        "rem-delivered",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    set_delivery_state(&conn, "rem-delivered", "delivered");
    // Plus one that should fire.
    insert_reminder(
        &conn,
        "rem-pending",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );

    let result = get_due_task_reminders(&conn, NOW, 10).expect("query");
    let ids: Vec<&str> = result.rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["rem-pending"]);
}

#[test]
fn due_reminders_excludes_non_open_and_archived_tasks() {
    let conn = test_conn();
    TaskBuilder::new("task-completed")
        .status("completed")
        .insert(&conn);
    TaskBuilder::new("task-cancelled")
        .status("cancelled")
        .insert(&conn);
    TaskBuilder::new("task-open").insert(&conn);
    TaskBuilder::new("task-archived").insert(&conn);
    archive_task(&conn, "task-archived");

    insert_reminder(
        &conn,
        "r-c",
        "task-completed",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-x",
        "task-cancelled",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-o",
        "task-open",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-a",
        "task-archived",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );

    let result = get_due_task_reminders(&conn, NOW, 10).expect("query");
    let ids: Vec<&str> = result.rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["r-o"]);
}

#[test]
fn due_reminders_truncates_and_signals_via_negative_total() {
    // The LIMIT+1 trick lets the query detect "there is at least one
    // more matching row" without doing a separate COUNT(*) scan. When
    // the result is truncated the envelope reports `total_matching = -1`
    // so callers can distinguish "exactly N" from "at least N".
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    for i in 0..5 {
        insert_reminder(
            &conn,
            &format!("rem-{i}"),
            "task-1",
            "2026-05-03T11:00:00.000Z",
            None,
            None,
        );
    }

    // Limit 3 with 5 matches → truncation
    let result = get_due_task_reminders(&conn, NOW, 3).expect("query");
    assert_eq!(result.rows.len(), 3);
    assert_eq!(result.total_matching, -1);

    // Limit 5 with 5 matches → exact, total = 5
    let result = get_due_task_reminders(&conn, NOW, 5).expect("query");
    assert_eq!(result.rows.len(), 5);
    assert_eq!(result.total_matching, 5);

    // Limit 100 with 5 matches → exact, total = 5
    let result = get_due_task_reminders(&conn, NOW, 100).expect("query");
    assert_eq!(result.rows.len(), 5);
    assert_eq!(result.total_matching, 5);
}

#[test]
fn due_reminders_orders_by_reminder_at_then_id() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    // Same time → id ASC tiebreaker.
    insert_reminder(
        &conn,
        "rem-zzz",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "rem-aaa",
        "task-1",
        "2026-05-03T11:00:00.000Z",
        None,
        None,
    );
    // Earlier time → comes first regardless of id.
    insert_reminder(
        &conn,
        "rem-mmm",
        "task-1",
        "2026-05-03T10:00:00.000Z",
        None,
        None,
    );

    let result = get_due_task_reminders(&conn, NOW, 10).expect("query");
    let ids: Vec<&str> = result.rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["rem-mmm", "rem-aaa", "rem-zzz"]);
}

#[test]
fn upcoming_reminders_returns_window_strictly_after_now() {
    // Window is `(now, horizon]` — `>` strict on the lower bound,
    // `<=` inclusive on the upper. Reminders at exactly `now` belong
    // to the due-query, not the upcoming-query.
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    insert_reminder(&conn, "rem-at-now", "task-1", NOW, None, None);
    insert_reminder(
        &conn,
        "rem-in-window",
        "task-1",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "rem-at-horizon",
        "task-1",
        "2026-05-03T14:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "rem-after-horizon",
        "task-1",
        "2026-05-03T14:00:00.001Z",
        None,
        None,
    );

    let horizon = "2026-05-03T14:00:00.000Z";
    let result = get_upcoming_task_reminders_until(&conn, NOW, horizon, 10).expect("query");
    let ids: Vec<&str> = result.rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["rem-in-window", "rem-at-horizon"]);
}

#[test]
fn upcoming_reminders_truncates_and_signals_via_negative_total() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    for i in 0..4 {
        insert_reminder(
            &conn,
            &format!("rem-{i}"),
            "task-1",
            "2026-05-03T13:00:00.000Z",
            None,
            None,
        );
    }
    let horizon = "2026-05-03T14:00:00.000Z";

    let result = get_upcoming_task_reminders_until(&conn, NOW, horizon, 2).expect("query");
    assert_eq!(result.rows.len(), 2);
    assert_eq!(result.total_matching, -1);
}

#[test]
fn reminders_for_task_excludes_archived_parent() {
    // Trashed-parent reminders MUST NOT surface in the per-task list
    // query — the rendering UI would otherwise show reminders for a
    // task that no longer exists in the user's lists.
    let conn = test_conn();
    TaskBuilder::new("task-live").insert(&conn);
    TaskBuilder::new("task-trashed").insert(&conn);
    archive_task(&conn, "task-trashed");

    insert_reminder(
        &conn,
        "r-live",
        "task-live",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-trash",
        "task-trashed",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );

    let live = get_reminders_for_task(&conn, &tid("task-live")).expect("query");
    assert_eq!(live.len(), 1);
    assert_eq!(live[0].id, "r-live");

    let trashed = get_reminders_for_task(&conn, &tid("task-trashed")).expect("query");
    assert!(trashed.is_empty());
}

#[test]
fn reminders_for_task_returns_dismissed_and_cancelled() {
    // Unlike the due-query, the per-task list returns ALL reminders
    // (dismissed + cancelled included) so the task-detail panel can
    // show the user a complete history. The display-side filters live
    // in the renderer, not here.
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    insert_reminder(
        &conn,
        "r-active",
        "task-1",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-dismissed",
        "task-1",
        "2026-05-03T14:00:00.000Z",
        Some("2026-05-03T13:30:00.000Z"),
        None,
    );
    insert_reminder(
        &conn,
        "r-cancelled",
        "task-1",
        "2026-05-03T15:00:00.000Z",
        None,
        Some("2026-05-03T13:30:00.000Z"),
    );

    let rows = get_reminders_for_task(&conn, &tid("task-1")).expect("query");
    assert_eq!(rows.len(), 3);
}

#[test]
fn reminders_for_task_orders_by_reminder_at_asc_then_id() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    insert_reminder(
        &conn,
        "r-zzz",
        "task-1",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-aaa",
        "task-1",
        "2026-05-03T13:00:00.000Z",
        None,
        None,
    );
    insert_reminder(
        &conn,
        "r-early",
        "task-1",
        "2026-05-03T10:00:00.000Z",
        None,
        None,
    );

    let rows = get_reminders_for_task(&conn, &tid("task-1")).expect("query");
    let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["r-early", "r-aaa", "r-zzz"]);
}
