use tempfile::tempdir;

use super::open_db_at_path;

#[test]
fn open_cli_db_runs_shared_preferences_integrity_once_for_path() {
    let dir = tempdir().expect("create tempdir");
    let db_path = dir.path().join("db.sqlite");
    {
        let conn = lorvex_store::open_db_at_path(&db_path).expect("initialize db");
        conn.execute(
            "INSERT INTO preferences (key, value, version, updated_at) \
             VALUES ('cli.corrupt', 'not-json', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-18T09:00:00Z')",
            [],
        )
        .expect("seed corrupt preference");
    }

    let conn = open_db_at_path(&db_path).expect("open cli db");
    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'preferences.corruption'",
            [],
            |row| row.get(0),
        )
        .expect("count preference corruption logs");
    assert_eq!(log_count, 1);

    drop(conn);
    let conn = open_db_at_path(&db_path).expect("reopen cli db");
    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'preferences.corruption'",
            [],
            |row| row.get(0),
        )
        .expect("count preference corruption logs after second open");
    assert_eq!(log_count, 1);
}

#[test]
fn open_cli_db_runs_shared_trash_purge_once_for_path() {
    let _guard = crate::hlc_guard::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex poisoned");
    crate::hlc_guard::reset_hlc_state_for_tests();

    let dir = tempdir().expect("create tempdir");
    let db_path = dir.path().join("db.sqlite");
    let task_id = "01949c00-0000-7000-8000-000000000043";
    {
        let conn = lorvex_store::open_db_at_path(&db_path).expect("initialize db");
        lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
            .archived_at(Some("2026-03-01T00:00:00.000Z"))
            .insert(&conn);
    }

    let conn = open_db_at_path(&db_path).expect("open cli db");
    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count purged task");
    let delete_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task'
               AND entity_id = ?1
               AND operation = 'delete'",
            [task_id],
            |row| row.get(0),
        )
        .expect("count delete outbox");
    assert_eq!(task_count, 0);
    assert_eq!(delete_count, 1);
    let audit_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE mcp_tool = 'startup_trash_purge'",
            [],
            |row| row.get(0),
        )
        .expect("count startup trash audit rows");
    assert_eq!(
        audit_count, 0,
        "startup trash purge is system maintenance and must not write ai_changelog rows"
    );
    let diagnostic_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'cli.startup.trash_purge_deleted'
               AND level = 'info'
               AND details = 'deleted=1'",
            [],
            |row| row.get(0),
        )
        .expect("count startup trash purge diagnostics");
    assert_eq!(
        diagnostic_count, 1,
        "CLI startup trash purge maintenance notices should persist structurally"
    );

    drop(conn);
    let conn = open_db_at_path(&db_path).expect("reopen cli db");
    let delete_count_after_reopen: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task'
               AND entity_id = ?1
               AND operation = 'delete'",
            [task_id],
            |row| row.get(0),
        )
        .expect("count delete outbox after reopen");
    assert_eq!(
        delete_count_after_reopen, 1,
        "successful startup purge should mark the DB maintained for this CLI process"
    );
    let audit_count_after_reopen: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE mcp_tool = 'startup_trash_purge'",
            [],
            |row| row.get(0),
        )
        .expect("count startup trash audit after reopen");
    assert_eq!(audit_count_after_reopen, 0);

    crate::hlc_guard::reset_hlc_state_for_tests();
}
