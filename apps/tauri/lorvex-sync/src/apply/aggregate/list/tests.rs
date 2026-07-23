use super::*;
use crate::test_db;
use lorvex_domain::ids::ListId;
use rusqlite::params;

fn seed_list(conn: &Connection, id: &ListId, version: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, 'list-name', ?2,
                 '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')",
        params![id, version],
    )
    .unwrap();
}

fn seed_task(conn: &Connection, id: &str, list_id: &ListId) {
    // delegate to the shared TaskBuilder. Local
    // overrides match the prior literal byte-for-byte so the
    // recurrence-dedup and fk_stalled assertions stay stable.
    lorvex_store::test_support::TaskBuilder::new(id)
        .title("task")
        .list_id(Some(list_id.as_str()))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-19T08:00:00Z")
        .insert(conn);
}

fn seed_archived_task(conn: &Connection, id: &str, list_id: &ListId) {
    lorvex_store::test_support::TaskBuilder::new(id)
        .title("trashed task")
        .list_id(Some(list_id.as_str()))
        .archived_at(Some("2026-04-19T07:30:00Z"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-19T08:00:00Z")
        .insert(conn);
}

fn count_conflicts(conn: &Connection, entity_id: &ListId, resolution: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_conflict_log
         WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
        params![naming::ENTITY_LIST, entity_id, resolution],
        |r| r.get(0),
    )
    .unwrap()
}

#[test]
fn apply_list_upsert_persists_archived_at_and_position() {
    let conn = test_db();
    let list_id = ListId::from_trusted("l-sync-fields".to_string());
    let payload = r#"{
        "name": "Synced",
        "archived_at": "2026-04-19T07:30:00.000Z",
        "position": 7,
        "created_at": "2026-04-19T08:00:00.000Z",
        "updated_at": "2026-04-19T08:01:00.000Z"
    }"#;

    apply_list_upsert(
        &conn,
        list_id.as_str(),
        payload,
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        LwwTieBreak::RejectEqual,
        "2026-04-19T08:01:00.000Z",
    )
    .unwrap();

    let (archived_at, position): (Option<String>, i64) = conn
        .query_row(
            "SELECT archived_at, position FROM lists WHERE id = ?1",
            params![&list_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(archived_at.as_deref(), Some("2026-04-19T07:30:00.000Z"));
    assert_eq!(position, 7);
}

#[test]
fn apply_list_upsert_absent_position_preserves_existing_value() {
    let conn = test_db();
    let list_id = ListId::from_trusted("l-keep-position".to_string());
    seed_list(&conn, &list_id, "1711234560000_0000_aaaaaaaaaaaaaaaa");
    conn.execute(
        "UPDATE lists SET position = 9 WHERE id = ?1",
        params![&list_id],
    )
    .unwrap();
    let payload = r#"{
        "name": "Renamed",
        "created_at": "2026-04-19T08:00:00.000Z",
        "updated_at": "2026-04-19T08:02:00.000Z"
    }"#;

    apply_list_upsert(
        &conn,
        list_id.as_str(),
        payload,
        "1711234569999_0000_bbbbbbbbbbbbbbbb",
        LwwTieBreak::RejectEqual,
        "2026-04-19T08:02:00.000Z",
    )
    .unwrap();

    let position: i64 = conn
        .query_row(
            "SELECT position FROM lists WHERE id = ?1",
            params![&list_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(position, 9);
}

/// Issue #3313: deleting a non-inbox list with surviving active
/// tasks must apply — the schema's `trg_lists_before_delete` trigger
/// re-homes the rows to `inbox` BEFORE the DELETE, so the FK never
/// fires and peers converge. Pre-fix this returned
/// `SkippedByInvariant{tasks_reference_list}` and quarantined after
/// 50 retries, leaving peers permanently disagreeing about the list.
#[test]
fn apply_list_delete_proceeds_when_active_tasks_reference_non_inbox_list() {
    let conn = test_db();
    let target = ListId::from_trusted("l-target".to_string());
    seed_list(&conn, &target, "1711234560000_0000_aaaaaaaaaaaaaaaa");
    seed_task(&conn, "t-1", &target);

    let result = apply_list_delete(
        &conn,
        target.as_str(),
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        "2026-04-19T08:05:00.000Z",
    )
    .expect("delete must succeed via re-home trigger");
    assert!(
        matches!(result, ListDeleteOutcome::Applied),
        "delete must report applied (trigger re-homes tasks to inbox), got {result:?}"
    );

    let gone: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = 'l-target'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(gone, 0, "list row must be deleted");

    let rehomed: String = conn
        .query_row("SELECT list_id FROM tasks WHERE id = 't-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(rehomed, "inbox", "task must be re-homed to inbox");

    assert_eq!(
        count_conflicts(&conn, &target, naming::RESOLUTION_FK_STALLED),
        0,
        "non-inbox delete must not log fk_stalled"
    );
}

/// Issue #3313 reproduction: when the only references are archived
/// (Trash) tasks, the delete still applies and re-homes them via the
/// trigger. Without this, peer A (no tasks) deletes the list, peer B
/// (only Trash rows) defers + quarantines, never converging.
#[test]
fn apply_list_delete_proceeds_when_only_archived_tasks_reference_list() {
    let conn = test_db();
    let target = ListId::from_trusted("l-trash".to_string());
    seed_list(&conn, &target, "1711234560000_0000_aaaaaaaaaaaaaaaa");
    seed_archived_task(&conn, "t-trashed", &target);

    let result = apply_list_delete(
        &conn,
        target.as_str(),
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        "2026-04-19T08:05:00.000Z",
    )
    .expect("delete with archived-only refs must apply");
    assert!(
        matches!(result, ListDeleteOutcome::Applied),
        "delete must apply, got {result:?}"
    );

    let gone: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists WHERE id = 'l-trash'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(gone, 0);

    let rehomed: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = 't-trashed'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(rehomed, "inbox", "archived task must be re-homed to inbox");
}

/// Issue #3313: peer asks us to delete `inbox` while local tasks
/// still depend on it. The schema trigger raises ABORT in that case,
/// so the handler must pre-empt with a `tasks_reference_list` skip
/// rather than letting the SQL ABORT poison the apply batch.
#[test]
fn apply_list_delete_skips_when_inbox_has_referencing_tasks() {
    let conn = test_db();
    let inbox = ListId::from_trusted("inbox".to_string());
    let other = ListId::from_trusted("l-other".to_string());
    seed_list(&conn, &other, "1711234560000_0000_bbbbbbbbbbbbbbbb");
    seed_task(&conn, "t-on-inbox", &inbox);

    let result = apply_list_delete(
        &conn,
        inbox.as_str(),
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        "2026-04-19T08:05:00.000Z",
    )
    .expect("must skip cleanly, not propagate the trigger ABORT");
    assert!(
        matches!(
            result,
            ListDeleteOutcome::SkippedByInvariant {
                invariant: INVARIANT_TASKS_REFERENCE_LIST
            }
        ),
        "inbox-with-tasks delete must report skipped, got {result:?}"
    );

    let still_there: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists WHERE id = 'inbox'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(still_there, 1, "inbox row must remain");

    assert_eq!(
        count_conflicts(&conn, &inbox, naming::RESOLUTION_FK_STALLED),
        1,
        "fk_stalled conflict row must be present"
    );
}

/// Empty list with no references applies cleanly — same path
/// pre- and post-#3313.
#[test]
fn apply_list_delete_proceeds_when_no_tasks_reference_the_list() {
    let conn = test_db();
    let empty = ListId::from_trusted("l-empty".to_string());
    seed_list(&conn, &empty, "1711234560000_0000_aaaaaaaaaaaaaaaa");

    let result = apply_list_delete(
        &conn,
        empty.as_str(),
        "1711234569999_0000_aaaaaaaaaaaaaaaa",
        "2026-04-19T08:05:00.000Z",
    )
    .expect("delete must succeed");
    assert!(
        matches!(result, ListDeleteOutcome::Applied),
        "delete must report applied, got {result:?}"
    );

    let gone: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists WHERE id = 'l-empty'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(gone, 0, "list row must be removed");

    assert_eq!(
        count_conflicts(&conn, &empty, naming::RESOLUTION_FK_STALLED),
        0,
        "no fk_stalled conflict for clean delete"
    );
}
