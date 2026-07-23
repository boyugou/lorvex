use std::collections::HashSet;

use rusqlite::params;

use super::super::*;
use super::support::*;

#[test]
fn batch_complete_tasks_with_conn_rejects_empty_input() {
    let conn = test_conn();
    let error = batch_complete_tasks_with_conn_inner(&conn, vec![])
        .expect_err("empty task_ids should be rejected");
    assert!(matches!(error, AppError::Validation(_)));
}

#[test]
fn batch_complete_tasks_with_conn_completes_open_and_skips_terminal() {
    let conn = test_conn();
    let task_open = uid();
    let task_done = uid();
    let task_killed = uid();
    let task_missing = uid();
    seed_task(&conn, &task_open, "Open", "inbox", "open");
    seed_task(&conn, &task_done, "Done", "inbox", "completed");
    seed_task(&conn, &task_killed, "Killed", "inbox", "cancelled");

    let (result, _spotlight_ids) = batch_complete_tasks_with_conn_inner(
        &conn,
        vec![
            task_open.clone(),
            task_done.clone(),
            task_killed.clone(),
            task_missing.clone(),
        ],
    )
    .expect("batch_complete_tasks should succeed");

    assert_eq!(result.completed_count, 1);
    assert_eq!(result.completed[0].id, task_open);
    assert_eq!(result.completed[0].status, "completed");

    assert_eq!(
        result.undo_tokens.len(),
        1,
        "one undo token per completed task"
    );

    assert!(result.skipped.contains(&task_done));
    assert!(result.skipped.contains(&task_killed));
    assert!(result.skipped.contains(&task_missing));

    // A sync_outbox row must have been enqueued for the completed task.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![task_open],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn batch_complete_tasks_with_conn_deduplicates_input_ids() {
    let conn = test_conn();
    let task_open = uid();
    seed_task(&conn, &task_open, "Open", "inbox", "open");

    let (result, _spotlight_ids) = batch_complete_tasks_with_conn_inner(
        &conn,
        vec![task_open.clone(), task_open.clone(), task_open.clone()],
    )
    .expect("batch_complete_tasks should succeed");

    assert_eq!(result.completed_count, 1);
    assert_eq!(
        result.undo_tokens.len(),
        1,
        "duplicate input ids must not mint duplicate undo tokens"
    );
    assert!(
        result.skipped.is_empty(),
        "duplicates are normalized before command execution, not reported as missing skips"
    );

    let outbox_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?1",
            params![task_open],
            |row| row.get(0),
        )
        .expect("count completion outbox rows");
    assert_eq!(
        outbox_rows, 1,
        "duplicate input ids must not mint duplicate task sync rows"
    );
}

#[test]
fn batch_complete_returns_distinct_tokens_and_enqueues_plain_task_rows() {
    let conn = test_conn();
    let task_a = uid();
    let task_b = uid();
    seed_task(&conn, &task_a, "A", "inbox", "open");
    seed_task(&conn, &task_b, "B", "inbox", "open");

    let (result, _spotlight_ids) =
        batch_complete_tasks_with_conn_inner(&conn, vec![task_a.clone(), task_b.clone()])
            .expect("batch_complete_tasks should succeed");

    // Each completed task gets its own undo token keyed by task id.
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
        "every completed task needs its own row-level undo token"
    );
    assert!(token_task_ids.contains(&task_a));
    assert!(token_task_ids.contains(&task_b));

    // Each simple completion enqueues one plain, immediately-dispatchable
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
        "each simple completion should enqueue one plain task row"
    );
}

#[test]
fn batch_complete_enqueues_spawned_successor_children_and_spotlight_ids() {
    let conn = test_conn();
    let task_rec = uid();
    seed_recurring_task(&conn, &task_rec, "Daily", "inbox", "2026-04-10");
    seed_successor_copied_children(&conn, &task_rec);

    let (result, spotlight_ids) =
        batch_complete_tasks_with_conn_inner(&conn, vec![task_rec.clone()])
            .expect("batch_complete_tasks should succeed");
    let token: UndoToken =
        serde_json::from_str(&result.undo_tokens[0]).expect("parse complete undo token");
    let successor_id = token
        .spawned_successor_id
        .as_deref()
        .expect("recurring complete should spawn successor");
    let successor_checklist_item_id = sole_successor_checklist_item_id(&conn, successor_id);
    let successor_reminder_id = sole_successor_reminder_id(&conn, successor_id);

    assert!(spotlight_ids.contains(&task_rec));
    assert!(
        spotlight_ids.iter().any(|id| id == successor_id),
        "spawned successor must be scheduled for Spotlight reindex"
    );
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
fn batch_complete_enqueues_focus_rewire_aggregates() {
    let conn = test_conn();
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"UTC\"', ?1, '2026-04-01T08:00:00Z')",
        params![SEED_VERSION],
    )
    .expect("seed timezone preference");

    let task_rec = uid();
    seed_recurring_task(&conn, &task_rec, "Daily", "inbox", "2099-05-20");

    let seed_focus_version = "0000000000000_0000_00000000000000f5";
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES ('2099-05-20', NULL, 'UTC', ?1, '2099-05-20T00:00:00Z', '2099-05-20T00:00:00Z')",
        params![seed_focus_version],
    )
    .expect("seed focus schedule");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
            (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title)
         VALUES ('2099-05-20', 0, 'task', 540, 600, ?1, NULL, 'Slot')",
        params![task_rec],
    )
    .expect("seed focus schedule block");

    let seed_current_focus_version = "0000000000000_0000_00000000000000cf";
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES ('2099-05-20', NULL, 'UTC', ?1, '2099-05-20T00:00:00Z', '2099-05-20T00:00:00Z')",
        params![seed_current_focus_version],
    )
    .expect("seed current focus");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id)
         VALUES ('2099-05-20', 0, ?1)",
        params![task_rec],
    )
    .expect("seed current focus item");

    let (result, _spotlight_ids) = batch_complete_tasks_with_conn_inner(&conn, vec![task_rec])
        .expect("batch_complete_tasks should succeed");
    let token: UndoToken =
        serde_json::from_str(&result.undo_tokens[0]).expect("parse complete undo token");
    let successor_id = token
        .spawned_successor_id
        .as_deref()
        .expect("recurring complete should spawn successor");

    let focus_block_task: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks WHERE schedule_date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("load rewired focus schedule block");
    assert_eq!(focus_block_task, successor_id);

    let current_focus_task: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("load rewired current focus item");
    assert_eq!(current_focus_task, successor_id);

    assert_eq!(
        plain_outbox_count(&conn, ENTITY_FOCUS_SCHEDULE, Some("2099-05-20")),
        1,
        "batch completion must enqueue the focus_schedule aggregate rewire"
    );
    assert_eq!(
        plain_outbox_count(&conn, ENTITY_CURRENT_FOCUS, Some("2099-05-20")),
        1,
        "batch completion must enqueue the current_focus aggregate rewire"
    );

    let focus_version: String = conn
        .query_row(
            "SELECT version FROM focus_schedule WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("load focus schedule version");
    assert_ne!(focus_version, seed_focus_version);

    let current_focus_version: String = conn
        .query_row(
            "SELECT version FROM current_focus WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("load current focus version");
    assert_ne!(current_focus_version, seed_current_focus_version);
}

#[test]
fn batch_complete_partial_undo_restores_undone_task_and_keeps_sibling_successor() {
    let conn = test_conn();
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"UTC\"', ?1, '2026-04-01T08:00:00Z')",
        params![SEED_VERSION],
    )
    .expect("seed timezone preference");

    let task_a = uid();
    let task_b = uid();
    seed_recurring_task(&conn, &task_a, "Daily A", "inbox", "2099-05-21");
    seed_recurring_task(&conn, &task_b, "Daily B", "inbox", "2099-05-21");

    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES ('2099-05-21', NULL, 'UTC', ?1, '2099-05-21T00:00:00Z', '2099-05-21T00:00:00Z')",
        params![SEED_VERSION],
    )
    .expect("seed focus schedule");
    for (position, task_id) in [(0_i64, task_a.as_str()), (1_i64, task_b.as_str())] {
        conn.execute(
            "INSERT INTO focus_schedule_blocks
                (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title)
             VALUES ('2099-05-21', ?1, 'task', ?2, ?3, ?4, NULL, 'Slot')",
            params![position, 540 + position * 60, 600 + position * 60, task_id],
        )
        .expect("seed focus schedule block");
    }

    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES ('2099-05-21', NULL, 'UTC', ?1, '2099-05-21T00:00:00Z', '2099-05-21T00:00:00Z')",
        params![SEED_VERSION],
    )
    .expect("seed current focus");
    for (position, task_id) in [(0_i64, task_a.as_str()), (1_i64, task_b.as_str())] {
        conn.execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES ('2099-05-21', ?1, ?2)",
            params![position, task_id],
        )
        .expect("seed current focus item");
    }

    let (result, _spotlight_ids) =
        batch_complete_tasks_with_conn_inner(&conn, vec![task_a.clone(), task_b.clone()])
            .expect("batch_complete_tasks should succeed");
    let tokens: Vec<UndoToken> = result
        .undo_tokens
        .iter()
        .map(|token| serde_json::from_str(token).expect("parse complete undo token"))
        .collect();
    let undo_a = tokens
        .iter()
        .find(|token| token.task_id == task_a)
        .expect("find task A undo token");
    let undo_b = tokens
        .iter()
        .find(|token| token.task_id == task_b)
        .expect("find task B undo token");
    let successor_a = undo_a
        .spawned_successor_id
        .as_deref()
        .expect("task A should spawn successor");
    let successor_b = undo_b
        .spawned_successor_id
        .as_deref()
        .expect("task B should spawn successor");

    crate::commands::with_immediate_transaction(&conn, |conn| {
        apply_single_undo_for_tests(conn, undo_a, "2099-05-21T12:00:00.000000Z")
    })
    .expect("partial undo should succeed");

    let focus_task_ids: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT task_id FROM focus_schedule_blocks
                 WHERE schedule_date = '2099-05-21' ORDER BY position",
            )
            .expect("prepare focus schedule query");
        stmt.query_map([], |row| row.get::<_, String>(0))
            .expect("query focus schedule rows")
            .collect::<rusqlite::Result<_>>()
            .expect("collect focus schedule rows")
    };
    assert_eq!(
        focus_task_ids,
        vec![task_a.clone(), successor_b.to_string()],
        "partial undo must restore only the undone task while keeping the sibling successor"
    );

    let current_focus_task_ids: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT task_id FROM current_focus_items
                 WHERE date = '2099-05-21' ORDER BY position",
            )
            .expect("prepare current focus query");
        stmt.query_map([], |row| row.get::<_, String>(0))
            .expect("query current focus rows")
            .collect::<rusqlite::Result<_>>()
            .expect("collect current focus rows")
    };
    assert_eq!(
        current_focus_task_ids,
        vec![task_a.clone(), successor_b.to_string()],
        "current focus repair must match the schedule repair"
    );

    // Undoing task A re-enqueues the repaired focus_schedule /
    // current_focus aggregates for the shared date. The coalesced
    // aggregate payload reflects the repaired state — task A restored
    // and task B's spawned successor preserved — and no longer
    // references A's deleted successor.
    for entity_type in [ENTITY_FOCUS_SCHEDULE, ENTITY_CURRENT_FOCUS] {
        let payload: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = '2099-05-21'
                 ORDER BY id DESC LIMIT 1",
                params![entity_type],
                |row| row.get(0),
            )
            .expect("load repaired aggregate outbox row");

        assert!(
            payload.contains(&task_a) && payload.contains(successor_b),
            "{entity_type} payload must carry the repaired parent plus sibling successor: {payload}"
        );
        assert!(
            !payload.contains(successor_a),
            "{entity_type} payload must not reference the deleted successor: {payload}"
        );
    }
}

#[test]
fn batch_complete_tasks_with_conn_all_skipped_returns_empty_result() {
    let conn = test_conn();
    let task_done = uid();
    let task_killed = uid();
    seed_task(&conn, &task_done, "Done", "inbox", "completed");
    seed_task(&conn, &task_killed, "Killed", "inbox", "cancelled");

    let (result, _spotlight_ids) =
        batch_complete_tasks_with_conn_inner(&conn, vec![task_done, task_killed])
            .expect("no-op batch should succeed");

    assert_eq!(result.completed_count, 0);
    assert!(result.completed.is_empty());
    assert!(
        result.undo_tokens.is_empty(),
        "no-op batch must not fabricate undo tokens"
    );
    assert_eq!(result.skipped.len(), 2);
}
