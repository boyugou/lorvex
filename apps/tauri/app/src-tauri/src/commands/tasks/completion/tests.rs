//! IPC test coverage for `complete_task`. Exercises
//! the `_with_conn` shim which runs the real completion transition
//! against an in-memory DB, without the Spotlight / event-bus
//! post-commit dispatch that requires a live Tauri runtime.
use super::*;
use rusqlite::params;

use crate::test_support::test_conn;

const SEED_HLC: &str = "0000000000000_0000_0000000000000000";

fn seed_task(conn: &Connection, id: &str, status: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Complete me")
        .status(status)
        .list_id(Some("inbox"))
        .version(SEED_HLC)
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

#[test]
fn complete_task_with_conn_rejects_missing_task() {
    let conn = test_conn();
    let error = complete_task_with_conn_inner(&conn, "does-not-exist")
        .expect_err("missing task should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}

#[test]
fn complete_task_with_conn_rejects_already_completed() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", "completed");

    let err = complete_task_with_conn_inner(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c")
        .expect_err("double-complete should be rejected");
    match err {
        AppError::Validation(msg) => {
            assert!(msg.contains("already completed"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn complete_task_with_conn_rejects_cancelled_task() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000042",
        lorvex_domain::naming::STATUS_CANCELLED,
    );

    let err = complete_task_with_conn_inner(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000042")
        .expect_err("cancelled task must be reopened before completion");
    match err {
        AppError::Validation(msg) => {
            assert!(
                msg.contains("cancelled") && msg.contains("completed"),
                "unexpected: {msg}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn complete_task_with_conn_sets_status_and_emits_undo_token() {
    let conn = test_conn();
    let task_id = "018f0000-0000-7000-8000-000000000001";
    seed_task(&conn, task_id, "open");

    let (result, spotlight_ids) =
        complete_task_with_conn_inner(&conn, task_id).expect("complete should succeed");
    assert_eq!(result.task.status, "completed");
    assert!(
        !result.undo_token.is_empty(),
        "undo token must be populated for a successful completion"
    );
    assert!(
        spotlight_ids.contains(&task_id.to_string()),
        "spotlight ids must include the completed task"
    );

    // A sync_outbox row must have been enqueued for peer propagation.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn complete_task_with_conn_copies_recurring_reminders_to_successor_and_enqueues_sync() {
    let conn = test_conn();
    let parent_task_id = "018f0000-0000-7000-8000-000000000100";
    let parent_reminder_id = "018f0000-0000-7000-8000-000000000101";
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"Asia/Tokyo\"', ?1, '2026-04-01T08:00:00Z')",
        params![SEED_HLC],
    )
    .expect("seed timezone preference");

    // Stays raw: TaskBuilder doesn't expose
    // `canonical_occurrence_date`, which the schema CHECK requires
    // alongside `recurrence`.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, due_date, canonical_occurrence_date, recurrence,
            recurrence_group_id, version, created_at, updated_at)
         VALUES (?1, 'Recurring complete me', 'open', 'inbox', '2099-05-20', '2099-05-20',
            '{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}', 'grp-complete-rem',
            ?2, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![parent_task_id, SEED_HLC],
    )
    .expect("seed recurring task");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2099-05-19T08:00:00Z', ?3, '2026-04-01T08:00:00Z')",
        params![parent_reminder_id, parent_task_id, SEED_HLC],
    )
    .expect("seed recurring reminder");

    let (result, spotlight_ids) = complete_task_with_conn_inner(&conn, parent_task_id)
        .expect("recurring complete should succeed");
    assert_eq!(result.task.status, "completed");

    let successor_id: String = conn
        .query_row(
            "SELECT id FROM tasks WHERE spawned_from = ?1",
            params![parent_task_id],
            |row| row.get(0),
        )
        .expect("spawned successor id");
    assert!(
        spotlight_ids.contains(&successor_id),
        "spotlight ids must include the spawned successor"
    );

    let successor_reminders: Vec<(String, String, Option<String>, Option<String>)> = conn
        .prepare(
            "SELECT id, reminder_at, original_local_time, original_tz
             FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC",
        )
        .expect("prepare successor reminder query")
        .query_map(params![&successor_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query successor reminders")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect successor reminders");
    assert_eq!(
        successor_reminders.len(),
        1,
        "recurring completion should copy the active parent reminder to the successor"
    );
    let (
        successor_reminder_id,
        successor_reminder_at,
        successor_original_local_time,
        successor_original_tz,
    ) = &successor_reminders[0];
    assert_eq!(successor_reminder_at, "2099-05-26T08:00:00.000Z");
    assert_eq!(successor_original_local_time.as_deref(), Some("17:00"));
    assert_eq!(successor_original_tz.as_deref(), Some("Asia/Tokyo"));

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![successor_reminder_id],
            |row| row.get(0),
        )
        .expect("count successor reminder outbox rows");
    assert!(
        outbox_count >= 1,
        "spawned successor reminder must enqueue for sync propagation"
    );
}

#[test]
fn copied_recurring_successor_reminder_reanchors_after_timezone_change() {
    let conn = test_conn();
    let parent_task_id = "018f0000-0000-7000-8000-000000000110";
    let parent_reminder_id = "018f0000-0000-7000-8000-000000000111";
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"Asia/Tokyo\"', ?1, '2026-04-01T08:00:00Z')",
        params![SEED_HLC],
    )
    .expect("seed timezone preference");
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, due_date, canonical_occurrence_date, recurrence,
            recurrence_group_id, version, created_at, updated_at)
         VALUES (?1, 'Recurring reanchor me', 'open', 'inbox', '2099-05-20', '2099-05-20',
            '{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}', 'grp-complete-reanchor-rem',
            ?2, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![parent_task_id, SEED_HLC],
    )
    .expect("seed recurring task");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2099-05-19T08:00:00Z', ?3, '2026-04-01T08:00:00Z')",
        params![parent_reminder_id, parent_task_id, SEED_HLC],
    )
    .expect("seed recurring reminder");

    complete_task_with_conn_inner(&conn, parent_task_id)
        .expect("recurring complete should succeed");

    let successor_id: String = conn
        .query_row(
            "SELECT id FROM tasks WHERE spawned_from = ?1",
            params![parent_task_id],
            |row| row.get(0),
        )
        .expect("spawned successor id");
    let successor_reminder_id: String = conn
        .query_row(
            "SELECT id FROM task_reminders WHERE task_id = ?1",
            params![successor_id],
            |row| row.get(0),
        )
        .expect("successor reminder id");

    crate::commands::settings::preferences::set_preference_with_conn_for_tests(
        &conn,
        "timezone",
        "\"America/New_York\"",
        "2026-04-01T12:00:00Z",
    )
    .expect("write new timezone");

    let (reminder_at, original_local_time, original_tz): (String, String, String) = conn
        .query_row(
            "SELECT reminder_at, original_local_time, original_tz \
             FROM task_reminders WHERE id = ?1",
            params![successor_reminder_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load reanchored reminder");
    assert_eq!(reminder_at, "2099-05-26T21:00:00.000Z");
    assert_eq!(original_local_time, "17:00");
    assert_eq!(original_tz, "America/New_York");
}

/// Regression test for issue #2937-H1.
///
/// When a recurring task with rows in `focus_schedule_blocks` and
/// `current_focus_items` is completed, the store's
/// `spawn_recurrence_successor` rewires the children onto the
/// freshly spawned successor in place — without bumping the parent
/// `focus_schedule` / `current_focus` aggregate version. Before this
/// fix the rewire stayed device-local: peer devices kept showing the
/// closed parent in their plan because no envelope ever reached them.
///
/// This test drives the canonical app completion caller end-to-end
/// and asserts the sync_outbox now carries an upsert envelope for
/// each touched aggregate root, keyed by date.
#[test]
fn complete_task_recurring_emits_focus_plan_rewire_envelopes() {
    let conn = test_conn();
    let parent_task_id = "018f0000-0000-7000-8000-000000000120";

    // Pin the caller's notion of "today" to a concrete UTC date so
    // the rewire predicate (`date >= today`) deterministically
    // includes the seeded plan rows.
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"UTC\"', ?1, '2026-04-01T08:00:00Z')",
        params![SEED_HLC],
    )
    .expect("seed timezone preference");

    // Recurring parent task due today.
    // Stays raw: TaskBuilder doesn't expose
    // `canonical_occurrence_date`, which the schema CHECK requires
    // alongside `recurrence`.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, due_date,
            canonical_occurrence_date, recurrence, recurrence_group_id,
            version, created_at, updated_at)
         VALUES (?1, 'Recurring rewire', 'open', 'inbox',
            '2099-05-20', '2099-05-20',
            '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}', 'grp-rewire',
            ?2, '2099-05-20T00:00:00Z', '2099-05-20T00:00:00Z')",
        params![parent_task_id, SEED_HLC],
    )
    .expect("seed recurring parent");

    // Today's focus_schedule + a single block referencing the parent.
    // Use a sentinel HLC-shaped seed version that will compare LESS
    // than the freshly-stamped version produced by the enqueue path
    // (`UPDATE ... WHERE ?1 > version`). A literal like "fs-v1"
    // sorts ABOVE every real HLC string (the HLC starts with a
    // 13-digit timestamp), which would silently no-op the version
    // bump even when the rewire fix is correct.
    //
    // Issue #2994 H9 / #2973-H5 holdout: the suffix must be 16
    // lowercase hex chars; the prior `seed00fs` was 8 chars and
    // contained the non-hex byte `s`, which slipped past the raw
    // INSERT but breaks the shape contract every parser now
    // enforces.
    let seed_hlc = "0000000000000_0000_00000000000000f5";
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES ('2099-05-20', NULL, 'UTC', ?1, '2099-05-20T00:00:00Z', '2099-05-20T00:00:00Z')",
        params![seed_hlc],
    )
    .expect("seed focus_schedule header");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
            (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title)
         VALUES ('2099-05-20', 0, 'task', 540, 600, ?1, NULL, 'Slot')",
        params![parent_task_id],
    )
    .expect("seed focus_schedule_block");

    // Today's current_focus + a single item referencing the parent.
    // Issue #2994 H9 / #2973-H5 holdout: 16-char lowercase-hex
    // suffix replaces the prior 8-char `seed00cf` (`s` is not hex).
    let seed_cf_hlc = "0000000000000_0000_00000000000000cf";
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES ('2099-05-20', NULL, 'UTC', ?1, '2099-05-20T00:00:00Z', '2099-05-20T00:00:00Z')",
        params![seed_cf_hlc],
    )
    .expect("seed current_focus header");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id)
         VALUES ('2099-05-20', 0, ?1)",
        params![parent_task_id],
    )
    .expect("seed current_focus_item");

    // Drive the canonical completion path. The transition computes
    // "today" from the now-timestamp + the timezone preference.
    conn.execute(
        "UPDATE preferences SET value = '\"UTC\"' WHERE key = 'timezone'",
        [],
    )
    .ok();

    // Override "today" indirectly by passing a `now` whose UTC date
    // equals the seeded plan date. The completion path uses
    // `sync_timestamp_now` internally, but `apply_completion_transition`
    // resolves "today" from that now via the timezone preference, so
    // we instead drive the API that lets us pass `now` — i.e. we
    // simulate it by updating `tasks.id` to a date guaranteed to
    // intersect: the seed used 2099-05-20 above. The default
    // `sync_timestamp_now` returns wall-clock now, which is BEFORE
    // 2099-05-20, so the rewire predicate (`date >= today`) holds
    // unconditionally — exactly what we need.

    let (result, _spotlight) =
        complete_task_with_conn_inner(&conn, parent_task_id).expect("completion succeeds");
    assert_eq!(result.task.status, "completed");

    // The rewire SQL must have moved both children onto the spawned
    // successor.
    let successor_id: String = conn
        .query_row(
            "SELECT id FROM tasks WHERE spawned_from = ?1",
            params![parent_task_id],
            |row| row.get(0),
        )
        .expect("spawned successor id");
    let block_task_id: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks WHERE schedule_date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("focus_schedule_block task_id");
    assert_eq!(block_task_id, successor_id);
    let item_task_id: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("current_focus_items task_id");
    assert_eq!(item_task_id, successor_id);

    // the sync_outbox must carry an UPSERT envelope
    // for both the focus_schedule and current_focus aggregate roots
    // keyed by today's date. Without this, peer devices never
    // observe the rewire — they keep pointing at the now-completed
    // parent task.
    let focus_schedule_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'focus_schedule' \
               AND entity_id = '2099-05-20' \
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count focus_schedule outbox rows");
    assert!(
        focus_schedule_count >= 1,
        "focus_schedule rewire must enqueue at least one upsert envelope; got {focus_schedule_count}"
    );
    let current_focus_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'current_focus' \
               AND entity_id = '2099-05-20' \
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count current_focus outbox rows");
    assert!(
        current_focus_count >= 1,
        "current_focus rewire must enqueue at least one upsert envelope; got {current_focus_count}"
    );

    // The parent aggregate's version row must also have been
    // bumped past its seed value — the enqueue helper stamps
    // a fresh HLC inside the transaction.
    let focus_schedule_version: String = conn
        .query_row(
            "SELECT version FROM focus_schedule WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("focus_schedule version");
    assert_ne!(
        focus_schedule_version, seed_hlc,
        "focus_schedule version must be re-stamped by the rewire enqueue"
    );
    let current_focus_version: String = conn
        .query_row(
            "SELECT version FROM current_focus WHERE date = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("current_focus version");
    assert_ne!(
        current_focus_version, seed_cf_hlc,
        "current_focus version must be re-stamped by the rewire enqueue"
    );
}
