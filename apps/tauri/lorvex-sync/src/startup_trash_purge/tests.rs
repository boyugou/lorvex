use super::*;
use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, OP_DELETE, OP_UPSERT};
use rusqlite::{params, OptionalExtension};

const VERSION_1: &str = "1000000000000_0000_aaaaaaaaaaaaaaaa";
const VERSION_2: &str = "1000000000001_0000_aaaaaaaaaaaaaaaa";

fn minting() -> impl FnMut(&Connection) -> StartupTrashPurgeResult<String> {
    let mut counter = 0u64;
    move |_conn| {
        counter += 1;
        Ok(format!("8000000000000_{counter:04}_aaaaaaaaaaaaaaaa"))
    }
}

fn seed_task(conn: &Connection, id: &str, archived_at: Option<&str>) {
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(id)
        .version(VERSION_1)
        .created_at("2026-04-01T00:00:00.000Z")
        .archived_at(archived_at)
        .insert(conn);
}

fn outbox_count(conn: &Connection, entity_type: &str, entity_id: &str, op: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
        params![entity_type, entity_id, op],
        |row| row.get(0),
    )
    .expect("count outbox")
}

fn tombstone_count(conn: &Connection, entity_type: &str, entity_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = ?2",
        params![entity_type, entity_id],
        |row| row.get(0),
    )
    .expect("count tombstones")
}

fn outbox_count_for_type(conn: &Connection, entity_type: &str, op: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = ?2",
        params![entity_type, op],
        |row| row.get(0),
    )
    .expect("count outbox rows for type")
}

fn outbox_count_for_entity_type(conn: &Connection, entity_type: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
        params![entity_type],
        |row| row.get(0),
    )
    .expect("count outbox rows for entity type")
}

fn changelog_count(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog")
}

fn local_change_seq(conn: &Connection) -> i64 {
    conn.query_row(
        "SELECT value FROM local_counters WHERE name = 'local_change_seq'",
        [],
        |row| row.get(0),
    )
    .optional()
    .expect("read local seq")
    .unwrap_or(0)
}

#[test]
fn purge_removes_expired_archived_tasks_and_leaves_recent_trash() {
    let conn = lorvex_store::test_support::test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002140",
        Some("2026-03-01T00:00:00.000Z"),
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002148",
        Some("2026-04-20T00:00:00.000Z"),
    );

    let report = purge_archived_tasks_older_than(&conn, "2026-04-01T00:00:00.000Z", &mut minting())
        .expect("purge");

    assert_eq!(
        report.deleted_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000002140".to_string()]
    );
    assert_eq!(report.remaining, 1);
    assert_eq!(
        outbox_count(
            &conn,
            ENTITY_TASK,
            "01966a3f-7c8b-7d4e-8f3a-000000002140",
            OP_DELETE
        ),
        1
    );
    assert_eq!(
        tombstone_count(&conn, ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-000000002140"),
        1
    );
    assert_eq!(changelog_count(&conn), 0);
    assert_eq!(
        outbox_count_for_type(&conn, ENTITY_AI_CHANGELOG, OP_UPSERT),
        0
    );
    assert_eq!(local_change_seq(&conn), 1);
    let recent_exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002148'",
            [],
            |row| row.get(0),
        )
        .expect("count recent");
    assert_eq!(recent_exists, 1);
}

#[test]
fn startup_purge_does_not_write_sync_admin_changelog() {
    let conn = lorvex_store::test_support::test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002140",
        Some("2026-03-01T00:00:00.000Z"),
    );

    let report = run_startup_trash_purge(&conn, 0, &mut minting()).expect("purge");

    assert_eq!(
        report.deleted_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000002140".to_string()]
    );
    assert_eq!(changelog_count(&conn), 0);
    assert_eq!(
        outbox_count_for_entity_type(&conn, ENTITY_AI_CHANGELOG),
        0,
        "startup trash purge is Tauri/system maintenance and must not enqueue syncable ai_changelog rows"
    );
    assert_eq!(
        outbox_count(
            &conn,
            ENTITY_TASK,
            "01966a3f-7c8b-7d4e-8f3a-000000002140",
            OP_DELETE
        ),
        1,
        "purged task itself must still emit a delete envelope"
    );
}

#[test]
fn purge_noop_does_not_bump_local_change_seq() {
    let conn = lorvex_store::test_support::test_conn();
    let report = purge_archived_tasks_older_than(&conn, "2026-04-01T00:00:00.000Z", &mut minting())
        .expect("purge");
    assert_eq!(report.deleted, 0);
    assert_eq!(changelog_count(&conn), 0);
    assert_eq!(
        outbox_count_for_type(&conn, ENTITY_AI_CHANGELOG, OP_UPSERT),
        0
    );
    assert_eq!(local_change_seq(&conn), 0);
}

#[test]
fn purge_rolls_back_when_enqueue_version_mint_fails() {
    let conn = lorvex_store::test_support::test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002140",
        Some("2026-03-01T00:00:00.000Z"),
    );

    let error = purge_archived_tasks_older_than(&conn, "2026-04-01T00:00:00.000Z", &mut |_conn| {
        Err(SyncError::Envelope(
            "test HLC mint failure during trash purge".to_string(),
        ))
    })
    .expect_err("purge should fail");

    assert!(
        error
            .to_string()
            .contains("test HLC mint failure during trash purge"),
        "unexpected error: {error}"
    );
    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002140'",
            [],
            |row| row.get(0),
        )
        .expect("count rolled-back task");
    let outbox_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox rows");
    let tombstone_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_tombstones", [], |row| row.get(0))
        .expect("count tombstone rows");
    assert_eq!(task_count, 1);
    assert_eq!(outbox_count, 0);
    assert_eq!(tombstone_count, 0);
    assert_eq!(changelog_count(&conn), 0);
    assert_eq!(local_change_seq(&conn), 0);
}

#[test]
fn purge_emits_child_edge_and_dependency_tombstones_with_full_payloads() {
    let conn = lorvex_store::test_support::test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002140",
        Some("2026-03-01T00:00:00.000Z"),
    );
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002113", None);
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002112", None);
    conn.execute(
            "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002159', 'Tag', 'tag', ?1, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
            params![VERSION_1],
        )
        .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002140', '01966a3f-7c8b-7d4e-8f3a-000000002159', '2026-04-01T00:00:00.000Z', ?1)",
        params![VERSION_1],
    )
    .expect("seed tag edge");
    conn.execute(
            "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000210e', '01966a3f-7c8b-7d4e-8f3a-000000002140', 0, 'Check', ?1, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
            params![VERSION_1],
        )
        .expect("seed checklist");
    conn.execute(
            "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000214c', '01966a3f-7c8b-7d4e-8f3a-000000002140', '2026-04-02T00:00:00.000Z', ?1, '2026-04-01T00:00:00.000Z')",
            params![VERSION_1],
        )
        .expect("seed reminder");
    conn.execute(
            "INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002115', 'Event', '2026-04-02', 1, ?1, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
            params![VERSION_1],
        )
        .expect("seed event");
    conn.execute(
            "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, created_at, updated_at, version)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002140', '01966a3f-7c8b-7d4e-8f3a-000000002115', '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', ?1)",
            params![VERSION_1],
        )
        .expect("seed event link");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002113', '01966a3f-7c8b-7d4e-8f3a-000000002140', '2026-04-01T00:00:00.000Z', ?1),
                    ('01966a3f-7c8b-7d4e-8f3a-000000002140', '01966a3f-7c8b-7d4e-8f3a-000000002112', '2026-04-01T00:00:00.000Z', ?2)",
        params![VERSION_1, VERSION_2],
    )
    .expect("seed dependencies");

    purge_archived_tasks_older_than(&conn, "2026-04-01T00:00:00.000Z", &mut minting())
        .expect("purge");

    for (entity_type, entity_id) in [
        (
            EDGE_TASK_TAG,
            "01966a3f-7c8b-7d4e-8f3a-000000002140:01966a3f-7c8b-7d4e-8f3a-000000002159",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            "01966a3f-7c8b-7d4e-8f3a-00000000210e",
        ),
        (ENTITY_TASK_REMINDER, "01966a3f-7c8b-7d4e-8f3a-00000000214c"),
        (
            EDGE_TASK_CALENDAR_EVENT_LINK,
            "01966a3f-7c8b-7d4e-8f3a-000000002140:01966a3f-7c8b-7d4e-8f3a-000000002115",
        ),
        (
            EDGE_TASK_DEPENDENCY,
            "01966a3f-7c8b-7d4e-8f3a-000000002113:01966a3f-7c8b-7d4e-8f3a-000000002140",
        ),
        (
            EDGE_TASK_DEPENDENCY,
            "01966a3f-7c8b-7d4e-8f3a-000000002140:01966a3f-7c8b-7d4e-8f3a-000000002112",
        ),
    ] {
        assert_eq!(outbox_count(&conn, entity_type, entity_id, OP_DELETE), 1);
        assert_eq!(tombstone_count(&conn, entity_type, entity_id), 1);
    }
    assert_eq!(
        outbox_count(
            &conn,
            ENTITY_TASK,
            "01966a3f-7c8b-7d4e-8f3a-000000002113",
            OP_UPSERT
        ),
        1
    );

    let tag_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002140:01966a3f-7c8b-7d4e-8f3a-000000002159'",
            [EDGE_TASK_TAG],
            |row| row.get(0),
        )
        .expect("read tag payload");
    let tag_payload: Value = serde_json::from_str(&tag_payload).expect("parse tag payload");
    assert_eq!(tag_payload["created_at"], "2026-04-01T00:00:00.000Z");
    lorvex_domain::hlc::Hlc::parse(tag_payload["version"].as_str().unwrap())
        .expect("delete envelope version must be canonical HLC");
}
