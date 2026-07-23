use super::*;
fn make_concurrent_envelope(entity_type: &str, entity_id: &str, version: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: make_payload_for_entity_type(entity_type),
        device_id: "remote-device".to_string(),
    }
}

fn make_concurrent_delete_envelope(
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: "{}".to_string(),
        device_id: "remote-device".to_string(),
    }
}

#[test]
fn concurrent_delete_then_upsert_at_equal_version_task() {
    let conn = test_db();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176",
        MATRIX_V_A,
        "2026-04-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_concurrent_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176",
        MATRIX_V_A,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "equal-version upsert must lose to existing tombstone, got {result:?}"
    );
    // Tombstone still present.
    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176"
    )
    .unwrap());
    // Row never materialized.
    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002176'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
}

#[test]
fn concurrent_upsert_then_delete_at_equal_version_task() {
    let conn = test_db();
    // Apply the upsert first.
    let up = make_concurrent_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176",
        MATRIX_V_A,
    );
    assert_eq!(apply_envelope(&conn, &up).unwrap(), ApplyResult::Applied);

    // Delete envelope at the same version arrives after.
    let del = make_concurrent_delete_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176",
        MATRIX_V_A,
    );
    let result = apply_envelope(&conn, &del).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "equal-version delete must lose to existing row, got {result:?}"
    );

    // Row must remain at the original version.
    let version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002176'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(version, MATRIX_V_A);
    // No tombstone was planted.
    assert!(!crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002176"
    )
    .unwrap());
}

#[test]
fn lww_delayed_remote_delete_with_original_old_version_loses_to_newer_local_task() {
    let conn = test_db();

    let local_upsert = make_concurrent_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000217c",
        LWW_V_NEW,
    );
    assert_eq!(
        apply_envelope(&conn, &local_upsert).unwrap(),
        ApplyResult::Applied
    );

    let delayed_delete = make_concurrent_delete_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000217c",
        LWW_V_OLD,
    );
    let result = apply_envelope(&conn, &delayed_delete).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "delayed delete carrying its original older HLC must lose to the newer local row, got {result:?}"
    );

    let version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000217c'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(version, LWW_V_NEW);
    assert!(
        !crate::tombstone::is_tombstoned(
            &conn,
            naming::ENTITY_TASK,
            "01966a3f-7c8b-7d4e-8f3a-00000000217c"
        )
        .unwrap(),
        "stale delayed delete must not tombstone the newer local row"
    );
}

#[test]
fn concurrent_delete_then_upsert_at_equal_version_tag() {
    let conn = test_db();
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215c",
        MATRIX_V_A,
        "2026-04-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();
    let env = make_concurrent_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215c",
        MATRIX_V_A,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));
    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215c"
    )
    .unwrap());
}

#[test]
fn concurrent_upsert_then_delete_at_equal_version_tag() {
    let conn = test_db();
    let up = make_concurrent_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215c",
        MATRIX_V_A,
    );
    assert_eq!(apply_envelope(&conn, &up).unwrap(), ApplyResult::Applied);
    let del = make_concurrent_delete_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215c",
        MATRIX_V_A,
    );
    let result = apply_envelope(&conn, &del).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tags WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000215c'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1, "tag row must survive equal-version delete");
}

#[test]
fn concurrent_upsert_then_delete_at_equal_version_current_focus() {
    let conn = test_db();
    let up = make_concurrent_envelope(naming::ENTITY_CURRENT_FOCUS, "2026-04-05", MATRIX_V_A);
    assert_eq!(apply_envelope(&conn, &up).unwrap(), ApplyResult::Applied);

    let del =
        make_concurrent_delete_envelope(naming::ENTITY_CURRENT_FOCUS, "2026-04-05", MATRIX_V_A);
    let result = apply_envelope(&conn, &del).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus WHERE date = '2026-04-05'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn concurrent_delete_then_upsert_at_equal_version_task_tag_edge() {
    let conn = test_db();
    // Seed FKs so the upsert *would* otherwise apply.
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000217d', 'T', 'open', '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [],
    ).unwrap();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000215d', 'T', 't', '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [],
    ).unwrap();

    create_tombstone(
        &conn,
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000217d:01966a3f-7c8b-7d4e-8f3a-00000000215d",
        MATRIX_V_A,
        "2026-04-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let mut env = make_concurrent_envelope(
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000217d:01966a3f-7c8b-7d4e-8f3a-00000000215d",
        MATRIX_V_A,
    );
    env.payload =
        r#"{"task_id":"01966a3f-7c8b-7d4e-8f3a-00000000217d","tag_id":"01966a3f-7c8b-7d4e-8f3a-00000000215d","created_at":"2026-04-01T00:00:00.000Z"}"#
            .to_string();
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "equal-version edge upsert must lose to tombstone, got {result:?}"
    );
    // task_tags row must NOT exist.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-00000000217d' AND tag_id = '01966a3f-7c8b-7d4e-8f3a-00000000215d'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
}
