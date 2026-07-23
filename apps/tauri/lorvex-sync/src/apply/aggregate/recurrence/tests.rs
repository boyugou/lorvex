//! Recurrence-instance-key dedup tests. Extracted from
//! `recurrence.rs` so the production file stays focused on the
//! merge orchestration (~720 lines).

use rusqlite::params;

use super::*;
use crate::test_db;

fn insert_minimal_task(conn: &Connection, id: &str, version: &str, recurrence_instance_key: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, recurrence_instance_key, version,
                            created_at, updated_at, defer_count)
         VALUES (?1, 'T', 'open', ?2, ?3,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)",
        params![id, recurrence_instance_key, version],
    )
    .expect("seed task");
}

/// Drop the unique index on `recurrence_instance_key` so the
/// test can stage two pre-merge tasks sharing the same key.
/// Production never has both rows alive at the same moment —
/// the merge collapses them — but the test needs to construct
/// the pre-merge state directly.
fn drop_recurrence_unique_index(conn: &Connection) {
    conn.execute_batch("DROP INDEX IF EXISTS idx_tasks_recurrence_instance_key")
        .expect("drop unique index");
}

fn insert_reminder(conn: &Connection, reminder_id: &str, task_id: &str, version: &str) {
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-04-01T09:00:00.000Z', ?3, '2026-04-01T00:00:00.000Z')",
        params![reminder_id, task_id, version],
    )
    .expect("seed reminder");
}

fn read_reminder_version(conn: &Connection, reminder_id: &str) -> String {
    conn.query_row(
        "SELECT version FROM task_reminders WHERE id = ?1",
        [reminder_id],
        |row| row.get::<_, String>(0),
    )
    .expect("read reminder version")
}

fn read_reminder_task_id(conn: &Connection, reminder_id: &str) -> String {
    conn.query_row(
        "SELECT task_id FROM task_reminders WHERE id = ?1",
        [reminder_id],
        |row| row.get::<_, String>(0),
    )
    .expect("read reminder task_id")
}

/// a re-pointed `task_reminders` row
/// must carry the merge HLC, not the loser's pre-merge HLC. The
/// merge HLC is guaranteed strictly greater than every
/// participant's version, so subsequent local edits emit
/// envelopes whose `version` dominates any peer's pre-merge view
/// of the row.
#[test]
fn merge_repoints_reminder_with_merge_version() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-001";
    // UUIDv7-shaped ids: lexicographic order picks the "winner".
    let winner_id = "00000000-0000-7000-8000-000000000001";
    let loser_id = "00000000-0000-7000-8000-000000000002";
    let winner_version = "1711234567000_0000_dec0000100000001";
    let loser_version = "1711234567000_0000_dec0000200000002";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    let reminder_id = "rem-001";
    // Reminder originally pinned to the loser at the loser's
    // pre-merge HLC.
    let original_reminder_version = "1711234566000_0000_dec0000200000002";
    insert_reminder(&conn, reminder_id, loser_id, original_reminder_version);

    merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
        .expect("recurrence merge should succeed");

    // Reminder is now re-pointed to the winner.
    assert_eq!(
        read_reminder_task_id(&conn, reminder_id),
        winner_id,
        "task_id should be re-pointed to winner"
    );

    // The reminder's version must equal the merge_version that
    // was stamped on the loser's tombstone (NOT the original
    // pre-merge version).
    let post_merge_version = read_reminder_version(&conn, reminder_id);
    assert_ne!(
        post_merge_version, original_reminder_version,
        "re-pointed reminder must NOT keep its pre-merge version"
    );

    // The merge_version is the loser's tombstone version. Read
    // it back and compare.
    let tombstone_version: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![lorvex_domain::naming::ENTITY_TASK, loser_id],
            |row| row.get(0),
        )
        .expect("loser tombstone should exist");
    assert_eq!(
        post_merge_version, tombstone_version,
        "reminder must be stamped with the merge_version (== loser tombstone version)"
    );

    // Sanity: the merge_version is strictly greater than both
    // participants' pre-merge versions.
    let merge_hlc = lorvex_domain::hlc::Hlc::parse(&post_merge_version).expect("merge hlc parses");
    let winner_hlc = lorvex_domain::hlc::Hlc::parse(winner_version).expect("winner hlc");
    let loser_hlc = lorvex_domain::hlc::Hlc::parse(loser_version).expect("loser hlc");
    assert!(merge_hlc > winner_hlc);
    assert!(merge_hlc > loser_hlc);
}

fn read_task_version(conn: &Connection, task_id: &str) -> String {
    conn.query_row(
        "SELECT version FROM tasks WHERE id = ?1",
        [task_id],
        |row| row.get::<_, String>(0),
    )
    .expect("read task version")
}

/// after a recurrence merge, the
/// winner aggregate row's `version` column must be stamped at
/// `merge_version`. Previously the loop only re-stamped children
/// (task_tags, task_reminders, etc.) and left
/// `tasks.version == triggering_version` for the winner —
/// i.e. winner.version < children.version, an aggregate-root
/// inversion that opens a subtle LWW-loss path on follow-up
/// edits.
#[test]
fn merge_stamps_winner_task_version_at_merge_version() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-h5";
    let winner_id = "00000000-0000-7000-8000-000000000010";
    let loser_id = "00000000-0000-7000-8000-000000000011";
    let winner_version = "1711234567000_0000_dec0000100000001";
    // Loser's pre-merge HLC strictly greater than winner's so the
    // merge_version (> max(winner,loser)) cannot accidentally
    // equal `triggering_version` — this exposes the H5 bug:
    // before the fix, the winner row would stay at
    // winner_version while children jumped to merge_version.
    let loser_version = "1711234568000_0000_dec0000200000002";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
        .expect("recurrence merge should succeed");

    let post_winner_version = read_task_version(&conn, winner_id);

    // The winner's version must equal `merge_version` (which is
    // the loser tombstone's version, by construction).
    let tombstone_version: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![lorvex_domain::naming::ENTITY_TASK, loser_id],
            |row| row.get(0),
        )
        .expect("loser tombstone should exist");
    assert_eq!(
        post_winner_version, tombstone_version,
        "winner.version must equal merge_version (== loser tombstone version)"
    );

    // Strictly greater than both pre-merge participants' versions
    // and the triggering envelope's version.
    let post_winner_hlc = lorvex_domain::hlc::Hlc::parse(&post_winner_version).unwrap();
    let triggering_hlc = lorvex_domain::hlc::Hlc::parse(winner_version).unwrap();
    let loser_hlc = lorvex_domain::hlc::Hlc::parse(loser_version).unwrap();
    assert!(
        post_winner_hlc > triggering_hlc,
        "winner version after merge ({post_winner_version}) must exceed triggering version ({winner_version})"
    );
    assert!(
        post_winner_hlc > loser_hlc,
        "winner version after merge ({post_winner_version}) must exceed loser version ({loser_version})"
    );
}

/// after a recurrence merge, the
/// registered local-event observer fires with the merge HLC. A
/// test HlcState that consumes the observation via
/// `update_on_receive` then generates a strictly-greater HLC.
#[test]
fn merge_observes_local_event_with_merge_version() {
    use lorvex_domain::hlc_state::HlcState;
    use std::sync::{Arc, Mutex};

    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-m1";
    let winner_id = "00000000-0000-7000-8000-000000000020";
    let loser_id = "00000000-0000-7000-8000-000000000021";
    let winner_version = "1711234567000_0000_dec0000100000001";
    let loser_version = "1711234568000_0000_dec0000200000002";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    let observed = Arc::new(Mutex::new(Vec::<lorvex_domain::hlc::Hlc>::new()));
    let observed_for_closure = Arc::clone(&observed);
    let test_state = Arc::new(Mutex::new(HlcState::new("c0ffee0011223344").unwrap()));
    let state_for_closure = Arc::clone(&test_state);

    let post_winner_version = crate::hlc::with_temporary_observer(
        move |hlc| {
            observed_for_closure
                .lock()
                .expect("observed lock")
                .push(hlc.clone());
            state_for_closure
                .lock()
                .expect("state lock")
                .update_on_receive(hlc, hlc.physical_ms());
        },
        || {
            merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
                .expect("merge should succeed");
            read_task_version(&conn, winner_id)
        },
    );

    let observed = observed.lock().expect("observed lock");
    let merge_hlc = lorvex_domain::hlc::Hlc::parse(&post_winner_version).unwrap();
    assert!(
        observed.iter().any(|h| h == &merge_hlc),
        "observer must have received merge_version {post_winner_version}; got {observed:?}"
    );

    // The next generated HLC must strictly exceed merge_version —
    // the bug this guards is precisely "the in-process clock has
    // no record of the merge_version, so the next generate emits
    // an HLC that lex-orders BELOW merge_version".
    let next = test_state
        .lock()
        .expect("state lock")
        .generate_with_physical(merge_hlc.physical_ms());
    assert!(
        next > merge_hlc,
        "next generated HLC ({next}) must strictly exceed merge_version ({post_winner_version})"
    );
}

#[test]
fn merge_reports_clear_error_when_no_canonical_hlc_successor_exists() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-ceiling";
    let winner_id = "00000000-0000-7000-8000-000000000030";
    let loser_id = "00000000-0000-7000-8000-000000000031";
    let ceiling = lorvex_domain::hlc::MAX_HLC_PHYSICAL_MS;
    let max_counter = lorvex_domain::hlc_state::MAX_COUNTER;
    let winner_version = format!("{ceiling}_{:04}_dec0000100000001", max_counter - 1);
    let loser_version = format!("{ceiling}_{max_counter:04}_dec0000200000002");
    insert_minimal_task(&conn, winner_id, &winner_version, KEY);
    insert_minimal_task(&conn, loser_id, &loser_version, KEY);

    let err = merge_duplicate_recurrence_instances(&conn, winner_id, KEY, &winner_version, "")
        .expect_err("ceiling merge must fail with a typed version error");

    match err {
        ApplyError::InvalidVersion(message) => {
            assert!(
                message.contains("recurrence merge")
                    && message.contains("no canonical HLC successor")
                    && message.contains(&loser_version),
                "unexpected ceiling error message: {message}"
            );
        }
        other => panic!("expected InvalidVersion, got {other:?}"),
    }
}

/// Recurrence merge must re-point both
/// `current_focus_items` and `focus_schedule_blocks` from loser to
/// winner. Pre-fix the merge re-pointed task_tags / task_dependencies
/// / task_calendar_event_links / task_reminders / task_checklist_items
/// but skipped the focus-plan tables. Since both hold task_id as an
/// unversioned soft reference (no FK), the loser's `DELETE FROM tasks`
/// did not cascade — so the user's focus-plan intent survived as an
/// orphan row pointing to a now-deleted task ID. This test pins the
/// new behaviour: after merge the focus-plan rows resolve to the
/// surviving winner, with no rows left referencing the loser.
#[test]
fn merge_repoints_focus_plan_children_to_winner() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-focus";
    let winner_id = "00000000-0000-7000-8000-0000000000a1";
    let loser_id = "00000000-0000-7000-8000-0000000000a2";
    let winner_version = "1711234567000_0000_dec0000100000001";
    let loser_version = "1711234567000_0000_dec0000200000002";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    // Seed today's focus plan with the loser pinned at position 0.
    let date = "2026-04-01";
    let plan_version = "1711234566000_0000_dec0000200000002";
    conn.execute(
        "INSERT INTO current_focus (date, briefing, version, created_at, updated_at) \
         VALUES (?1, NULL, ?2, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![date, plan_version],
    )
    .expect("seed current_focus");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, ?2)",
        params![date, loser_id],
    )
    .expect("seed current_focus_items");

    // Seed today's focus schedule with a 30-minute task block for
    // the loser at 09:00. focus_schedule_blocks has no version
    // column; the parent's version is what gets compared on apply.
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, version, created_at, updated_at) \
         VALUES (?1, NULL, ?2, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![date, plan_version],
    )
    .expect("seed focus_schedule");
    conn.execute(
        "INSERT INTO focus_schedule_blocks (\
            schedule_date, position, block_type, start_time, end_time, task_id\
         ) VALUES (?1, 0, 'task', 540, 570, ?2)",
        params![date, loser_id],
    )
    .expect("seed focus_schedule_blocks");

    merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
        .expect("recurrence merge should succeed");

    // The loser task row was deleted by the merge.
    let loser_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [loser_id],
            |row| row.get(0),
        )
        .expect("count loser task rows");
    assert_eq!(loser_count, 0, "loser task row must be deleted");

    // current_focus_items now points at the winner with the same
    // (date, position) preserved.
    let focus_task_id: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = ?1 AND position = 0",
            [date],
            |row| row.get(0),
        )
        .expect("current_focus_items row should still exist for the date");
    assert_eq!(
        focus_task_id, winner_id,
        "current_focus_items must be re-pointed to the merge winner"
    );

    // No leftover current_focus_items row references the loser.
    let leftover_focus_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?1",
            [loser_id],
            |row| row.get(0),
        )
        .expect("count leftover current_focus_items rows");
    assert_eq!(
        leftover_focus_items, 0,
        "no current_focus_items row may still point at the loser"
    );

    // focus_schedule_blocks now references the winner.
    let scheduled_task_id: Option<String> = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = ?1 AND position = 0",
            [date],
            |row| row.get(0),
        )
        .expect("focus_schedule_blocks row should still exist for the date");
    assert_eq!(
        scheduled_task_id.as_deref(),
        Some(winner_id),
        "focus_schedule_blocks must be re-pointed to the merge winner"
    );

    let leftover_schedule_blocks: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?1",
            [loser_id],
            |row| row.get(0),
        )
        .expect("count leftover focus_schedule_blocks rows");
    assert_eq!(
        leftover_schedule_blocks, 0,
        "no focus_schedule_blocks row may still point at the loser"
    );
}

/// When the winner already occupies the same focus plan date,
/// re-pointing the loser would conflict with the
/// `(date, task_id)` UNIQUE INDEX on current_focus_items. The
/// merge must use UPDATE OR IGNORE + cleanup DELETE so the
/// existing winner row survives and the leftover loser-pointed
/// row is dropped — never producing a foreign / dangling pointer
/// or violating the unique index.
#[test]
fn merge_drops_loser_focus_item_when_winner_already_in_focus_for_date() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-focus-conflict";
    let winner_id = "00000000-0000-7000-8000-0000000000b1";
    let loser_id = "00000000-0000-7000-8000-0000000000b2";
    let winner_version = "1711234567000_0000_dec0000100000001";
    let loser_version = "1711234567000_0000_dec0000200000002";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    let date = "2026-04-02";
    let plan_version = "1711234566000_0000_dec0000200000002";
    conn.execute(
        "INSERT INTO current_focus (date, briefing, version, created_at, updated_at) \
         VALUES (?1, NULL, ?2, '2026-04-02T00:00:00.000Z', '2026-04-02T00:00:00.000Z')",
        params![date, plan_version],
    )
    .expect("seed current_focus");
    // Winner is already in focus at position 0.
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, ?2)",
        params![date, winner_id],
    )
    .expect("seed winner focus item");
    // Loser is in focus at position 1 — different position, same
    // date. After re-point this would land both at (date,
    // winner_id), violating the UNIQUE INDEX without OR IGNORE.
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 1, ?2)",
        params![date, loser_id],
    )
    .expect("seed loser focus item");

    merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
        .expect("recurrence merge should succeed");

    // Winner survives at its original position.
    let winner_position: i64 = conn
        .query_row(
            "SELECT position FROM current_focus_items WHERE date = ?1 AND task_id = ?2",
            params![date, winner_id],
            |row| row.get(0),
        )
        .expect("winner row should still exist");
    assert_eq!(
        winner_position, 0,
        "winner's existing focus row must keep its original position"
    );

    // Exactly one row remains for that date — the loser's row was
    // dropped by the cleanup DELETE because the UNIQUE INDEX
    // already had `(date, winner_id)`.
    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            [date],
            |row| row.get(0),
        )
        .expect("count remaining focus items for date");
    assert_eq!(
        remaining, 1,
        "only the surviving winner row should remain for the date"
    );

    let leftover_loser: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?1",
            [loser_id],
            |row| row.get(0),
        )
        .expect("count leftover loser focus items");
    assert_eq!(
        leftover_loser, 0,
        "no current_focus_items row may still point at the loser"
    );
}

/// A tainted (legacy / hand-edited / migrated) version on any
/// participant task row must NOT abort the recurrence merge.
/// Pre-fix `Hlc::parse(task_version)?` propagated InvalidVersion
/// from the max-HLC loop, rolling back the savepoint and leaving
/// both duplicate rows alive. Because the tainted version was
/// persisted local data, every subsequent envelope apply for any
/// task sharing the same `recurrence_instance_key` re-fired and
/// re-failed the merge — a permanent stuck state. This test pins
/// the new tolerance: tainted versions are skipped (with a
/// best-effort error_log entry) and the merge converges using
/// whatever canonical versions parsed.
#[test]
fn merge_skips_tainted_task_version_and_converges() {
    let conn = test_db();
    drop_recurrence_unique_index(&conn);

    const KEY: &str = "rec-key-tainted-version";
    let winner_id = "00000000-0000-7000-8000-0000000000c1";
    let loser_id = "00000000-0000-7000-8000-0000000000c2";
    // Winner has a canonical HLC; loser carries a legacy literal
    // ("v1") that fails Hlc::parse. The triggering envelope's
    // version (the canonical winner version) is what drives the
    // merge_version computation now that the tainted loser is
    // skipped.
    let winner_version = "1711234567000_0000_dec0000100000001";
    let loser_version = "v1";
    insert_minimal_task(&conn, winner_id, winner_version, KEY);
    insert_minimal_task(&conn, loser_id, loser_version, KEY);

    // Make the winner and loser carry distinct body values so the
    // divergent-conflict-log path fires too — its tainted version
    // must not abort that codepath either. `divergent_loser_fields`
    // only emits a log entry when both sides hold a value AND
    // those values differ (or when an earlier loser already
    // donated to a winner-NULL field), so seed both rows.
    conn.execute(
        "UPDATE tasks SET body = 'winner-body' WHERE id = ?1",
        [winner_id],
    )
    .expect("seed winner body");
    conn.execute(
        "UPDATE tasks SET body = 'loser-body' WHERE id = ?1",
        [loser_id],
    )
    .expect("seed loser body");

    merge_duplicate_recurrence_instances(&conn, winner_id, KEY, winner_version, "")
        .expect("merge must converge when one participant has a tainted version");

    // Loser task row was deleted.
    let loser_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [loser_id],
            |row| row.get(0),
        )
        .expect("count loser task rows");
    assert_eq!(loser_count, 0, "loser task row must be deleted");

    // Loser tombstone exists with a canonical merge_version
    // strictly greater than the winner's pre-merge version.
    let tombstone_version: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![lorvex_domain::naming::ENTITY_TASK, loser_id],
            |row| row.get(0),
        )
        .expect("loser tombstone should exist");
    let merge_hlc =
        lorvex_domain::hlc::Hlc::parse(&tombstone_version).expect("merge_version must parse");
    let winner_hlc = lorvex_domain::hlc::Hlc::parse(winner_version).expect("winner hlc");
    assert!(
        merge_hlc > winner_hlc,
        "merge_version must dominate the canonical winner version"
    );

    // The conflict-log path also tolerated the tainted version:
    // the entry exists and records the raw tainted bytes in
    // loser_device_id (so diagnostics can see what the peer sent
    // even when the version cannot be parsed for a clean device
    // suffix).
    let conflict_loser_device: String = conn
        .query_row(
            "SELECT loser_device_id FROM sync_conflict_log \
             WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            params![
                lorvex_domain::naming::ENTITY_TASK,
                winner_id,
                lorvex_domain::naming::RESOLUTION_RECURRENCE_DEDUP,
            ],
            |row| row.get(0),
        )
        .expect("recurrence_dedup conflict log row must exist");
    assert_eq!(
        conflict_loser_device, loser_version,
        "tainted loser_version must be recorded as raw bytes in loser_device_id"
    );

    // The merge logged the tainted version to error_logs (best-
    // effort). Source matches the dedup namespace so operators can
    // grep for it in Diagnostics.
    let logged: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs \
             WHERE source = 'sync.apply.recurrence_merge_unparseable_version'",
            [],
            |row| row.get(0),
        )
        .expect("count error_logs entries");
    assert!(
        logged >= 1,
        "tainted task_version must produce at least one error_log entry"
    );
}
