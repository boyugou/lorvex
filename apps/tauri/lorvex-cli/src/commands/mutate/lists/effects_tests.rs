use super::effects::*;
use crate::commands::shared::test_support::seed_task;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_runtime::read_local_change_seq;

#[test]
fn list_create_update_delete_and_move_with_conn_syncs_and_bumps_change_seq() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_move_a = "0196c771-2222-7222-8222-222222224401";
    let task_move_b = "0196c771-2222-7222-8222-222222224402";

    seed_task(&conn, task_move_a, "Move A", "open");
    seed_task(&conn, task_move_b, "Move B", "open");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-personal', 'Personal', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed destination list");

    let created = create_list_with_conn(
        &mut conn,
        "Deep Work",
        Some("#112233"),
        Some("brain"),
        Some("Protected time"),
    )
    .expect("create list");
    assert_eq!(created.name, "Deep Work");

    let updated = update_list_with_conn(
        &mut conn,
        &created.id,
        Some("Deep Work 2"),
        lorvex_domain::Patch::Set("#445566"),
        lorvex_domain::Patch::Unset,
        lorvex_domain::Patch::Set("Updated notes"),
        lorvex_domain::Patch::Unset,
    )
    .expect("update list");
    assert_eq!(updated.name, "Deep Work 2");

    let moved = move_tasks_to_list_with_conn(
        &mut conn,
        &created.id,
        &[task_move_a.to_string(), task_move_b.to_string()],
    )
    .expect("move tasks");
    assert_eq!(moved.len(), 2);
    assert!(moved.iter().all(|task| task.list_id == created.id));

    let error = delete_list_with_conn(&mut conn, &created.id)
        .expect_err("lists with assigned tasks should not delete");
    assert!(
        error
            .to_string()
            .contains("while 2 task(s) are still assigned"),
        "unexpected error: {error}"
    );

    let still_assigned_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id IN (?1, ?2) AND list_id = ?3",
            rusqlite::params![task_move_a, task_move_b, &created.id],
            |row| row.get(0),
        )
        .expect("count still-assigned tasks");
    assert_eq!(still_assigned_count, 2);

    let moved_back = move_tasks_to_list_with_conn(
        &mut conn,
        "list-personal",
        &[task_move_a.to_string(), task_move_b.to_string()],
    )
    .expect("move tasks away before delete");
    assert_eq!(moved_back.len(), 2);

    let deleted = delete_list_with_conn(&mut conn, &created.id).expect("delete empty list");
    assert_eq!(deleted.id, created.id);

    let list_delete_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'list' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("count list delete outbox entries");
    assert_eq!(list_delete_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq after list ops");
    assert_eq!(seq, 5);
}

#[test]
fn move_tasks_to_list_with_conn_rejects_missing_target_list() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-move", "Move me", "open");

    let error = move_tasks_to_list_with_conn(
        &mut conn,
        "list-that-does-not-exist",
        &["task-move".to_string()],
    )
    .expect_err("missing target list should be rejected");
    assert!(error.to_string().contains("not found"));
}

#[test]
fn move_tasks_to_list_with_conn_skips_tasks_already_in_target_list() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    // Task already lives in 'inbox' (the seeded list from the schema).
    seed_task(&conn, "task-stay", "Stay put", "open");

    let summaries = move_tasks_to_list_with_conn(&mut conn, "inbox", &["task-stay".to_string()])
        .expect("move should succeed even when target == source");

    assert_eq!(summaries.len(), 1);
    // No outbox row because the task wasn't actually moved.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, "task-stay"],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 0);
}

#[test]
fn move_tasks_to_list_with_conn_skips_cancelled_tasks_without_resurrecting_tombstones() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "0196c771-2222-7222-8222-222222224301";
    seed_task(&conn, task_id, "Cancelled move", "cancelled");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-target-cancelled', 'Target', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed destination list");

    let summaries =
        move_tasks_to_list_with_conn(&mut conn, "list-target-cancelled", &[task_id.to_string()])
            .expect("cancelled move should skip instead of mutating");

    assert!(
        summaries.is_empty(),
        "cancelled tasks should be skipped and omitted from moved summaries"
    );
    let (list_id, status): (String, String) = conn
        .query_row(
            "SELECT list_id, status FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read cancelled task after skipped move");
    assert_eq!(list_id, "inbox");
    assert_eq!(status, "cancelled");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 0);
}

/// the move surface must route through
/// `apply_task_update`, which gates the UPDATE on `new_version >
/// existing_version`. Seed a task carrying an HLC version far in
/// the future and assert the move surface refuses to clobber it —
/// the canonical write path's strict `version >` LWW guard keeps
/// the stored `list_id` intact. The previous raw `UPDATE tasks SET
/// list_id = ...` SQL had no such guard and would silently
/// overwrite the row, racing the freshly-applied remote write.
#[test]
fn move_tasks_to_list_with_conn_honors_lww_version_guard() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    // Lexicographically beats any HLC the test run will mint.
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-future")
        .title("Future")
        .version("9999999999999_9999_9999999999999999")
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("inbox"))
        .insert(&conn);

    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-target', 'Target', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed destination list");

    let error =
        move_tasks_to_list_with_conn(&mut conn, "list-target", &["task-future".to_string()]);
    // After #3389 the store layer raises `StoreError::StaleVersion`
    // directly via the `RETURNING 1` LWW gate. Both shapes carry the
    // same retryable-EX_TEMPFAIL semantics via `store_exit_code`.
    assert!(
        matches!(
            &error,
            Err(crate::error::CliError::Store(e))
                if matches!(**e, lorvex_store::StoreError::StaleVersion { .. })
        ),
        "move must fail with StaleVersion when stored version is newer; got {error:?}"
    );

    let list_id_after: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = 'task-future'",
            [],
            |row| row.get(0),
        )
        .expect("read list_id after attempted move");
    assert_eq!(
        list_id_after, "inbox",
        "LWW guard must reject overwrite when stored version is newer"
    );
}

#[test]
fn delete_list_with_conn_honors_lww_version_guard() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-stale-delete', 'Future Delete',
                 '9999999999999_9999_9999999999999999',
                 '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("seed future-version list");

    let error = delete_list_with_conn(&mut conn, "list-stale-delete");
    assert!(
        matches!(
            &error,
            Err(crate::error::CliError::Store(e))
                if matches!(**e, lorvex_store::StoreError::StaleVersion { .. })
        ),
        "delete must fail with StaleVersion when stored version is newer; got {error:?}"
    );

    let list_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = 'list-stale-delete'",
            [],
            |row| row.get(0),
        )
        .expect("count list after stale delete");
    assert_eq!(list_count, 1, "stale delete must leave the row intact");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'list' AND entity_id = 'list-stale-delete'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox after stale delete");
    assert_eq!(outbox_count, 0, "stale delete must not enqueue a tombstone");
}
