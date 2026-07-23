use super::support::{
    apply_undo_in_txn, seed_cancel_undo_fixture, seed_recurrence_undo_fixture, NOW_TS, TEST_VER,
};
use super::*;
use crate::test_support::test_conn;

// ──────────────────────────────────────────────────────────────────
// Reverse-write undo apply behavior. Undo restores local state and
// enqueues fresh sync envelopes so peers converge via ordinary LWW:
// a newer-HLC upsert for the restored parent, an explicit delete for
// a spawned recurrence successor, and re-published reminder/dependency
// rows for a cancel undo. There is no emit-hold and no outbox
// retraction, so undo works whether or not the forward mutation's
// envelopes have already been pushed.
// ──────────────────────────────────────────────────────────────────

const PARENT_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000022";
const SUCCESSOR_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000023";

#[test]
fn undo_recurrence_completion_publishes_parent_upsert_and_successor_delete() {
    let conn = test_conn();
    let undo = seed_recurrence_undo_fixture(&conn);

    apply_undo_in_txn(&conn, &undo);

    // The parent is restored to its pre-completion state.
    let parent_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            params![PARENT_ID],
            |row| row.get(0),
        )
        .expect("load parent status");
    assert_eq!(parent_status, "open", "undo must restore the parent task");

    // The spawned successor is hard-deleted locally.
    let successor_exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            params![SUCCESSOR_ID],
            |row| row.get(0),
        )
        .expect("count successor rows");
    assert_eq!(successor_exists, 0, "undo must hard-delete the successor");

    // sync_outbox carries a fresh upsert for the restored parent.
    let parent_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = ?1 AND operation = 'upsert' \
             AND synced_at IS NULL",
            params![PARENT_ID],
            |row| row.get(0),
        )
        .expect("count parent upserts");
    assert!(
        parent_upserts >= 1,
        "undo must enqueue a task upsert for the restored parent"
    );

    // sync_outbox carries an explicit delete envelope for the successor.
    let successor_deletes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = ?1 AND operation = 'delete' \
             AND synced_at IS NULL",
            params![SUCCESSOR_ID],
            |row| row.get(0),
        )
        .expect("count successor deletes");
    assert_eq!(
        successor_deletes, 1,
        "undo must publish a delete envelope for the spawned successor"
    );

    // The successor's task tombstone is written for peer-side delete.
    let tombstones: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![ENTITY_TASK, SUCCESSOR_ID],
            |row| row.get(0),
        )
        .expect("count successor tombstones");
    assert_eq!(tombstones, 1, "successor task tombstone must be created");
}

#[test]
fn undo_recurrence_completion_restores_focus_plan_rewires() {
    let conn = test_conn();
    let undo = seed_recurrence_undo_fixture(&conn);

    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES ('2026-04-20', NULL, 'UTC', ?1, ?2, ?2)",
        params![TEST_VER, NOW_TS],
    )
    .expect("seed focus schedule");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
            (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title)
         VALUES ('2026-04-20', 0, 'task', 540, 600, ?1, NULL, 'Slot')",
        params![SUCCESSOR_ID],
    )
    .expect("seed rewired focus schedule block");
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES ('2026-04-20', NULL, 'UTC', ?1, ?2, ?2)",
        params![TEST_VER, NOW_TS],
    )
    .expect("seed current focus");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id)
         VALUES ('2026-04-20', 0, ?1)",
        params![SUCCESSOR_ID],
    )
    .expect("seed rewired current focus item");

    apply_undo_in_txn(&conn, &undo);

    let focus_task_id: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks WHERE schedule_date = '2026-04-20'",
            [],
            |row| row.get(0),
        )
        .expect("load focus schedule block");
    assert_eq!(
        focus_task_id, PARENT_ID,
        "completion undo must restore focus_schedule_blocks to the parent task"
    );
    let current_focus_task_id: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2026-04-20'",
            [],
            |row| row.get(0),
        )
        .expect("load current focus item");
    assert_eq!(
        current_focus_task_id, PARENT_ID,
        "completion undo must restore current_focus_items to the parent task"
    );

    for (entity_type, message) in [
        (
            ENTITY_FOCUS_SCHEDULE,
            "focus_schedule aggregate repair must be enqueued for the rewired date",
        ),
        (
            ENTITY_CURRENT_FOCUS,
            "current_focus aggregate repair must be enqueued for the rewired date",
        ),
    ] {
        let repaired_rows: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox \
                 WHERE entity_type = ?1 AND entity_id = '2026-04-20' \
                   AND operation = 'upsert' AND synced_at IS NULL",
                params![entity_type],
                |row| row.get(0),
            )
            .expect("count repaired aggregate rows");
        assert!(repaired_rows >= 1, "{message}");
    }
}

#[test]
fn undo_recurrence_completion_after_forward_rows_synced_publishes_reverse_writes() {
    // Undo is allowed after the forward complete's envelopes have
    // already been pushed: it simply issues the reverse writes rather
    // than rejecting. The synced forward rows stay as immutable send
    // history; undo adds fresh unsynced reverse-write envelopes.
    let conn = test_conn();
    let undo = seed_recurrence_undo_fixture(&conn);

    // Simulate a push cycle that drained the outbox before undo fired.
    conn.execute(
        "UPDATE sync_outbox SET synced_at = ?1 WHERE synced_at IS NULL",
        params![NOW_TS],
    )
    .expect("mark forward rows synced");

    apply_undo_in_txn(&conn, &undo);

    let parent_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            params![PARENT_ID],
            |row| row.get(0),
        )
        .expect("load parent status");
    assert_eq!(parent_status, "open", "undo after push must still restore");

    // The synced forward successor upsert remains as send history.
    let synced_forward_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_id = ?1 AND synced_at IS NOT NULL",
            params![SUCCESSOR_ID],
            |row| row.get(0),
        )
        .expect("count synced forward rows");
    assert!(
        synced_forward_rows >= 1,
        "synced forward rows must remain as immutable send history"
    );

    // A fresh unsynced delete for the successor is enqueued.
    let successor_delete: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = ?1 AND operation = 'delete' \
             AND synced_at IS NULL",
            params![SUCCESSOR_ID],
            |row| row.get(0),
        )
        .expect("count fresh successor delete");
    assert_eq!(
        successor_delete, 1,
        "undo after push must enqueue a fresh successor delete envelope"
    );

    // A fresh unsynced upsert for the restored parent is enqueued.
    let parent_upsert: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = ?1 AND operation = 'upsert' \
             AND synced_at IS NULL",
            params![PARENT_ID],
            |row| row.get(0),
        )
        .expect("count fresh parent upsert");
    assert!(
        parent_upsert >= 1,
        "undo after push must enqueue a fresh parent upsert envelope"
    );
}

#[test]
fn undo_cancel_restores_reminders_and_dependency_edges() {
    let conn = test_conn();
    let undo = seed_cancel_undo_fixture(&conn);

    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000042";
    let dep_id = "01966a3f-7c8b-7d4e-8f3a-000000000043";
    let reminder_id = "01966a3f-7c8b-7d4e-8f3a-000000000044";
    let edge_composite = format!("{task_id}:{dep_id}");

    apply_undo_in_txn(&conn, &undo);

    // The task is restored to open.
    let status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .expect("load task status");
    assert_eq!(status, "open", "cancel undo must restore the task");

    // The suspended reminder is un-cancelled.
    let cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
            params![reminder_id],
            |row| row.get(0),
        )
        .expect("load reminder cancelled_at");
    assert_eq!(
        cancelled_at, None,
        "cancel undo must clear cancelled_at on the restored reminder"
    );

    // The deleted dependency edge is re-inserted.
    let edge_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies \
             WHERE task_id = ?1 AND depends_on_task_id = ?2",
            params![task_id, dep_id],
            |row| row.get(0),
        )
        .expect("count dependency edges");
    assert_eq!(
        edge_rows, 1,
        "cancel undo must re-insert the dependency edge"
    );

    // The restored reminder is re-published as a task_reminder upsert.
    let reminder_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'upsert' \
             AND synced_at IS NULL",
            params![ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder upserts");
    assert!(
        reminder_upserts >= 1,
        "cancel undo must enqueue a task_reminder upsert for the restored reminder"
    );

    // The restored edge is re-published as a task_dependency upsert.
    let edge_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'upsert' \
             AND synced_at IS NULL",
            params![EDGE_TASK_DEPENDENCY, edge_composite],
            |row| row.get(0),
        )
        .expect("count dependency edge upserts");
    assert!(
        edge_upserts >= 1,
        "cancel undo must enqueue a task_dependency edge upsert for the restored edge"
    );
}
