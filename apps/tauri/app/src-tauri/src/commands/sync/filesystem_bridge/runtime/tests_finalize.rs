use super::tests_support::*;
use super::*;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

#[test]
fn phase_apply_and_finalize_fails_when_outbox_gc_delete_fails() {
    let conn = setup_runtime_test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Delete {
            table_name: "sync_outbox",
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-outbox-gc-failure-{}",
        uuid::Uuid::now_v7()
    ));
    let db_path = temp.join("lorvex.sqlite");
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let empty_collected = super::super::collection::CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files: 0,
        pull_parse_errors: 0,
        cursor_blocking_parse_errors: 0,
        lookback_known_id_skipped: 0,
        pull_limit_hit: false,
        diagnostics: Vec::new(),
        remote_events: Vec::new(),
    };

    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        let error = phase_apply_and_finalize(
            &conn,
            &sync_dir,
            "test-device",
            empty_collected.clone(),
            0,
            "2026-03-29T15:00:00Z",
        )
        .expect_err("outbox gc failure should fail finalize");
        assert!(
            error.to_string().contains("sync_outbox")
                || error.to_string().contains("not authorized"),
            "unexpected error: {error}"
        );
    });
}

#[test]
fn phase_apply_and_finalize_reaps_stale_pending_queues() {
    let conn = setup_runtime_test_conn();
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-pending-queue-retention-{}",
        uuid::Uuid::now_v7()
    ));
    let db_path = temp.join("lorvex.sqlite");
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let fresh_ts = lorvex_domain::sync_timestamp_now();
    let old_envelope = "{\"entity_type\":\"task\",\"entity_id\":\"task-old\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}";
    let fresh_envelope = "{\"entity_type\":\"task\",\"entity_id\":\"task-fresh\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a1\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}";
    conn.execute(
        "INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
         VALUES
            (?1, 'fk_unresolved', 'list', 'old-list',
             'task', 'task-old', '0000000000000_0000_a0a0a0a0a0a0a0a0',
             '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z', 1),
            (?2, 'fk_unresolved', 'list', 'fresh-list',
             'task', 'task-fresh', '0000000000000_0000_a0a0a0a0a0a0a0a1',
             ?3, ?3, 1)",
        params![old_envelope, fresh_envelope, fresh_ts],
    )
    .expect("seed pending inbox rows");

    let empty_collected = super::super::collection::CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files: 0,
        pull_parse_errors: 0,
        cursor_blocking_parse_errors: 0,
        lookback_known_id_skipped: 0,
        pull_limit_hit: false,
        diagnostics: Vec::new(),
        remote_events: Vec::new(),
    };

    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        phase_apply_and_finalize(
            &conn,
            &sync_dir,
            "test-device",
            empty_collected,
            0,
            &fresh_ts,
        )
        .expect("filesystem finalize should run pending queue retention");
    });

    let remaining_inbox: String = conn
        .query_row(
            "SELECT missing_entity_id FROM sync_pending_inbox",
            [],
            |row| row.get(0),
        )
        .expect("load remaining pending inbox");
    assert_eq!(remaining_inbox, "fresh-list");
    let reseed_required: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'",
            [],
            |row| row.get(0),
        )
        .expect("reseed checkpoint should be set before stale inbox deletion");
    assert_eq!(reseed_required, "true");
}

#[test]
fn phase_apply_and_finalize_rolls_back_success_checkpoint_when_pending_reseed_mark_fails() {
    let conn = setup_runtime_test_conn();
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-pending-reseed-failure-{}",
        uuid::Uuid::now_v7()
    ));
    let db_path = temp.join("lorvex.sqlite");
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let old_envelope = "{\"entity_type\":\"task\",\"entity_id\":\"task-old\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}";
    conn.execute(
        "INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
         VALUES
            (?1, 'fk_unresolved', 'list', 'old-list',
             'task', 'task-old', '0000000000000_0000_a0a0a0a0a0a0a0a0',
             '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z', 1)",
        params![old_envelope],
    )
    .expect("seed expired pending inbox row");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Insert {
            table_name: "sync_conflict_log",
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let empty_collected = super::super::collection::CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files: 0,
        pull_parse_errors: 0,
        cursor_blocking_parse_errors: 0,
        lookback_known_id_skipped: 0,
        pull_limit_hit: false,
        diagnostics: Vec::new(),
        remote_events: Vec::new(),
    };

    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        let error = phase_apply_and_finalize(
            &conn,
            &sync_dir,
            "test-device",
            empty_collected,
            0,
            "2026-03-29T15:00:00Z",
        )
        .expect_err("pending reseed marker failure should fail finalize");
        assert!(
            error.to_string().contains("sync_conflict_log")
                || error.to_string().contains("not authorized"),
            "unexpected error: {error}"
        );
    });

    let success_checkpoint_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_checkpoints WHERE key = ?1",
            params![lorvex_runtime::KEY_LAST_SUCCESS_AT],
            |row| row.get(0),
        )
        .expect("count success checkpoint rows");
    assert_eq!(
        success_checkpoint_count, 0,
        "success checkpoint must roll back when pending reseed evidence fails"
    );
}

#[test]
fn phase_apply_and_finalize_persists_collected_pull_diagnostics() {
    let conn = setup_runtime_test_conn();
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-collected-diagnostics-{}",
        uuid::Uuid::now_v7()
    ));
    let db_path = temp.join("lorvex.sqlite");
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let collected = super::super::collection::CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files: 0,
        pull_parse_errors: 1,
        cursor_blocking_parse_errors: 0,
        lookback_known_id_skipped: 0,
        pull_limit_hit: false,
        diagnostics: vec![super::super::diagnostics::FilesystemBridgeDiagnostic::warn(
            "sync.filesystem_bridge.pull.parse_error",
            "Filesystem bridge pull failed to parse envelope",
            "path=/tmp/bad.json, error=bad json",
        )],
        remote_events: Vec::new(),
    };

    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        phase_apply_and_finalize(
            &conn,
            &sync_dir,
            "test-device",
            collected,
            0,
            "2026-03-29T15:00:00Z",
        )
        .expect("filesystem finalize should persist collected diagnostics");
    });

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'sync.filesystem_bridge.pull.parse_error'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read persisted collected diagnostic");

    assert_eq!(row.0, "sync.filesystem_bridge.pull.parse_error");
    assert_eq!(row.1, "warn");
    assert_eq!(row.2, "Filesystem bridge pull failed to parse envelope");
    assert!(row.3.contains("bad.json"));
}
