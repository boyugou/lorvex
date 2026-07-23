use std::collections::HashSet;

use rusqlite::params;

use super::super::*;
use super::support::*;

#[test]
fn batch_cancel_returns_undo_token_per_cancelled_task() {
    let conn = test_conn();
    let task_a = uid();
    let task_b = uid();
    seed_task(&conn, &task_a, "A", "inbox", "open");
    seed_task(&conn, &task_b, "B", "inbox", "open");

    let result = batch_cancel_tasks_with_conn(&conn, vec![task_a, task_b], false)
        .expect("batch_cancel_tasks should succeed");

    assert_eq!(result.cancelled_count, 2);
    assert_eq!(
        result.undo_tokens.len(),
        2,
        "one undo token per cancelled task"
    );
    assert!(result.skipped.is_empty());

    // Each token must deserialize into a valid UndoToken that
    // references the originating task and the "cancel" action.
    let cancelled_ids: HashSet<&str> = result.cancelled.iter().map(|t| t.id.as_str()).collect();
    for token_str in &result.undo_tokens {
        let parsed: UndoToken = serde_json::from_str(token_str).expect("undo token should parse");
        assert_eq!(parsed.action, LifecycleAction::Cancel);
        assert_eq!(parsed.pre_status, TaskStatus::Open);
        assert!(
            cancelled_ids.contains(parsed.task_id.as_str()),
            "token task_id {} not in cancelled set",
            parsed.task_id
        );
    }
}

#[test]
fn batch_cancel_returns_distinct_tokens_and_enqueues_plain_task_rows() {
    let conn = test_conn();
    let task_a = uid();
    let task_b = uid();
    seed_task(&conn, &task_a, "A", "inbox", "open");
    seed_task(&conn, &task_b, "B", "inbox", "open");

    let result = batch_cancel_tasks_with_conn(&conn, vec![task_a.clone(), task_b.clone()], false)
        .expect("batch_cancel_tasks should succeed");

    // Each cancelled task gets its own undo token keyed by task id.
    let token_task_ids: HashSet<String> = result
        .undo_tokens
        .iter()
        .map(|token| {
            serde_json::from_str::<UndoToken>(token)
                .expect("undo token should parse")
                .task_id
        })
        .collect();
    assert_eq!(
        token_task_ids.len(),
        2,
        "every cancelled task needs its own row-level undo token"
    );
    assert!(token_task_ids.contains(&task_a));
    assert!(token_task_ids.contains(&task_b));

    // Each simple cancel enqueues one plain, immediately-dispatchable
    // task upsert row.
    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id IN (?1, ?2) AND synced_at IS NULL",
            params![task_a, task_b],
            |row| row.get(0),
        )
        .expect("query task outbox rows");
    assert_eq!(
        row_count, 2,
        "each simple cancel should enqueue one plain task row"
    );
}

#[test]
fn batch_cancel_row_level_undo_leaves_sibling_cancelled() {
    let conn = test_conn();
    let task_a = uid();
    let task_b = uid();
    seed_task(&conn, &task_a, "A", "inbox", "open");
    seed_task(&conn, &task_b, "B", "inbox", "open");

    let result = batch_cancel_tasks_with_conn(&conn, vec![task_a.clone(), task_b.clone()], false)
        .expect("batch_cancel_tasks should succeed");

    let undo_a = result
        .undo_tokens
        .iter()
        .map(|token| serde_json::from_str::<UndoToken>(token).expect("parse undo token"))
        .find(|token| token.task_id == task_a)
        .expect("task A undo token");

    // Undoing one row reverses only that task; the sibling stays
    // cancelled and its forward upsert row is untouched.
    crate::commands::with_immediate_transaction(&conn, |conn| {
        apply_single_undo_for_tests(conn, &undo_a, "2026-04-20T12:00:00.000000Z")
    })
    .expect("undo first cancelled task");

    let task_a_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            params![task_a],
            |row| row.get(0),
        )
        .expect("load undone task status");
    assert_eq!(task_a_status, "open", "row-level undo must restore task A");

    let task_b_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            params![task_b],
            |row| row.get(0),
        )
        .expect("load sibling status");
    assert_eq!(task_b_status, STATUS_CANCELLED);

    let sibling_rows = plain_outbox_count(&conn, ENTITY_TASK, Some(&task_b));
    assert!(
        sibling_rows > 0,
        "undoing one batch row must not disturb the sibling's outbox row"
    );
}

#[test]
fn batch_cancel_with_series_returns_tokens_for_all_tombstones() {
    // Recurring task cancelled with cancel_series=false spawns a
    // successor occurrence. The undo token must capture the
    // `spawned_successor_id` so undo retracts both the parent
    // cancel AND the spawned child in one step. Previously the
    // batch command returned no tokens at all, so the successor
    // would be stranded on disk and on peers after a user undo.
    let conn = test_conn();
    let task_rec = uid();
    let task_plain = uid();
    seed_recurring_task(&conn, &task_rec, "Daily", "inbox", "2026-04-10");
    seed_task(&conn, &task_plain, "Plain", "inbox", "open");

    let result = batch_cancel_tasks_with_conn(
        &conn,
        vec![task_rec.clone(), task_plain.clone()],
        false, // cancel_series=false → spawn successor for task_rec
    )
    .expect("batch_cancel_tasks should succeed");

    assert_eq!(result.cancelled_count, 2);
    assert_eq!(result.undo_tokens.len(), 2);

    // Locate the recurring-task token and confirm it threaded the
    // spawned successor id through.
    let rec_token = result
        .undo_tokens
        .iter()
        .map(|t| serde_json::from_str::<UndoToken>(t).expect("parse undo token"))
        .find(|t| t.task_id == task_rec)
        .expect("recurring-task token missing");
    assert_eq!(rec_token.action, LifecycleAction::Cancel);
    assert!(!rec_token.cancel_series);
    assert!(
        rec_token.spawned_successor_id.is_some(),
        "cancel_series=false on a recurring task must thread the \
         spawned successor id into the undo token so the UI can \
         retract both the parent cancel and the spawned occurrence"
    );

    // The plain task's token carries no successor.
    let plain_token = result
        .undo_tokens
        .iter()
        .map(|t| serde_json::from_str::<UndoToken>(t).expect("parse undo token"))
        .find(|t| t.task_id == task_plain)
        .expect("plain-task token missing");
    assert_eq!(plain_token.spawned_successor_id, None);
}

#[test]
fn batch_cancel_enqueues_spawned_successor_children() {
    let conn = test_conn();
    let task_rec = uid();
    seed_recurring_task(&conn, &task_rec, "Daily", "inbox", "2026-04-10");
    seed_successor_copied_children(&conn, &task_rec);

    let result = batch_cancel_tasks_with_conn(&conn, vec![task_rec], false)
        .expect("batch_cancel_tasks should succeed");
    let token: UndoToken =
        serde_json::from_str(&result.undo_tokens[0]).expect("parse cancel undo token");
    let successor_id = token
        .spawned_successor_id
        .as_deref()
        .expect("recurring cancel should spawn successor");
    let successor_checklist_item_id = sole_successor_checklist_item_id(&conn, successor_id);
    let successor_reminder_id = sole_successor_reminder_id(&conn, successor_id);

    assert_eq!(
        plain_outbox_count(&conn, ENTITY_TASK, Some(successor_id)),
        1,
        "spawned successor task upsert must be enqueued"
    );
    assert_eq!(
        plain_outbox_count(
            &conn,
            EDGE_TASK_TAG,
            Some(&format!(
                "{successor_id}:01966a3f-7c8b-7d4e-8f3a-000000000027"
            )),
        ),
        1,
        "copied successor tag edge must be enqueued"
    );
    assert_eq!(
        plain_outbox_count(
            &conn,
            ENTITY_TASK_CHECKLIST_ITEM,
            Some(&successor_checklist_item_id),
        ),
        1,
        "copied successor checklist item must be enqueued"
    );
    assert_eq!(
        plain_outbox_count(&conn, ENTITY_TASK_REMINDER, Some(&successor_reminder_id)),
        1,
        "copied successor reminder must be enqueued"
    );
}

#[test]
fn batch_cancel_empty_selection_returns_no_tokens() {
    // If every id is either missing or already in a terminal state,
    // the result must still be well-formed: empty `cancelled`,
    // empty `undo_tokens`, and every input id surfaced in
    // `skipped` so the caller can clear the selection deterministically.
    let conn = test_conn();
    let task_done = uid();
    let task_killed = uid();
    let task_missing = uid();
    seed_task(&conn, &task_done, "Done", "inbox", "completed");
    seed_task(&conn, &task_killed, "Killed", "inbox", "cancelled");

    let result = batch_cancel_tasks_with_conn(
        &conn,
        vec![task_done.clone(), task_killed.clone(), task_missing.clone()],
        false,
    )
    .expect("batch_cancel_tasks should succeed even when everything skips");

    assert_eq!(result.cancelled_count, 0);
    assert!(result.cancelled.is_empty());
    assert!(
        result.undo_tokens.is_empty(),
        "no-op batch must not fabricate undo tokens"
    );
    assert_eq!(result.skipped.len(), 3);
    assert!(result.skipped.contains(&task_done));
    assert!(result.skipped.contains(&task_killed));
    assert!(result.skipped.contains(&task_missing));
}
