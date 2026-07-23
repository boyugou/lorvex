use super::support::*;

// ===========================================================================
// 1. Idempotent apply
// ===========================================================================

#[test]
fn idempotent_apply_same_task_twice() {
    let conn = test_db();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000310d");

    let payload = r#"{
        "title": "Buy groceries",
        "body": "Milk, eggs, bread",
        "status": "open",
        "list_id": "01966a3f-7c8b-7d4e-8f3a-00000000310d",
        "defer_count": 0,
        "priority": 2,
        "due_date": "2026-03-25",
        "estimated_minutes": 30,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;

    let env = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003124",
        V2,
        payload,
    );

    // Apply once.
    let r1 = apply_envelope(&conn, &env).unwrap();
    assert_eq!(r1, ApplyResult::Applied);

    // Capture state after first apply.
    let title_1: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003124'",
            [],
            |r| r.get(0),
        )
        .unwrap();

    // Apply again (idempotent).
    let r2 = apply_envelope(&conn, &env).unwrap();
    // Second apply should be skipped because version is equal (local wins on tie).
    assert!(matches!(r2, ApplyResult::Skipped { .. }));

    // DB state unchanged.
    let title_2: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003124'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title_1, title_2);
    assert_eq!(
        count_rows(
            &conn,
            "tasks",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003124'"
        ),
        1
    );
}

#[test]
fn concurrent_apply_envelope_same_task_converges_under_wal_contention() {
    let dir = tempfile::tempdir().expect("create tempdir");
    let db_path = dir.path().join("concurrent-apply.sqlite");
    open_db_at_path(&db_path).expect("initialize file-backed db");

    const ITERATIONS: u64 = 8;
    const BASE_MS: u64 = 1_711_234_567_000;

    let make_version =
        |offset: u64, suffix: &str| -> String { format!("{:013}_0000_{suffix}", BASE_MS + offset) };
    let expected_version = make_version(ITERATIONS * 2 - 1, "bbbbbbbbbbbbbbbb");
    let barrier = Arc::new(Barrier::new(2));

    let path_a = db_path.clone();
    let barrier_a = Arc::clone(&barrier);
    let thread_a = thread::spawn(move || -> Result<(), String> {
        let conn = open_db_at_path(&path_a).map_err(|e| e.to_string())?;
        barrier_a.wait();
        for i in 0..ITERATIONS {
            let env = mk_task_envelope(
                "01966a3f-7c8b-7d4e-8f3a-00000000312f",
                &format!("A-{i}"),
                &format!("{:013}_0000_aaaaaaaaaaaaaaaa", BASE_MS + i * 2),
                "thread-a",
            );
            // `apply_envelope` debug_asserts an outer
            // transaction. Wrap each apply in BEGIN IMMEDIATE/COMMIT
            // so the test exercises the production transaction
            // boundary (matching `with_immediate_transaction`).
            conn.execute_batch("BEGIN IMMEDIATE")
                .map_err(|e| e.to_string())?;
            apply_envelope(&conn, &env).map_err(|e| e.to_string())?;
            conn.execute_batch("COMMIT").map_err(|e| e.to_string())?;
        }
        Ok(())
    });

    let path_b = db_path.clone();
    let barrier_b = Arc::clone(&barrier);
    let thread_b = thread::spawn(move || -> Result<(), String> {
        let conn = open_db_at_path(&path_b).map_err(|e| e.to_string())?;
        barrier_b.wait();
        for i in 0..ITERATIONS {
            let env = mk_task_envelope(
                "01966a3f-7c8b-7d4e-8f3a-00000000312f",
                &format!("B-{i}"),
                &format!("{:013}_0000_bbbbbbbbbbbbbbbb", BASE_MS + i * 2 + 1),
                "thread-b",
            );
            conn.execute_batch("BEGIN IMMEDIATE")
                .map_err(|e| e.to_string())?;
            apply_envelope(&conn, &env).map_err(|e| e.to_string())?;
            conn.execute_batch("COMMIT").map_err(|e| e.to_string())?;
        }
        Ok(())
    });

    thread_a
        .join()
        .expect("thread A join")
        .expect("thread A apply loop");
    thread_b
        .join()
        .expect("thread B join")
        .expect("thread B apply loop");

    let verify = open_db_at_path(&db_path).expect("reopen db for verification");
    let (title, version): (String, String) = verify
        .query_row(
            "SELECT title, version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000312f'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("task row should exist");
    assert_eq!(title, "B-7");
    assert_eq!(
        version, expected_version,
        "final task version must converge to the max HLC under concurrent apply"
    );

    let findings = lorvex_store::run_integrity_check(&verify).expect("integrity check");
    assert!(
        findings.is_empty(),
        "concurrent apply must not leave FK or page-level corruption: {findings:?}"
    );

    let task_rows = count_rows(
        &verify,
        "tasks",
        "id = '01966a3f-7c8b-7d4e-8f3a-00000000312f'",
    );
    assert_eq!(
        task_rows, 1,
        "concurrent apply must converge to one task row"
    );
}

// ===========================================================================
// 1b. list_id fallback: missing / empty → inbox, then oldest list
// ===========================================================================

#[test]
fn apply_task_upsert_with_missing_list_id_falls_back_to_inbox_or_oldest_list() {
    // Regression for the `list_id NOT NULL` invariant. Older devices may
    // serialize unset list references as missing-field OR empty-string;
    // apply must coerce both to None and fall back to the inbox list
    // (seeded by `open_db_in_memory`) rather than letting an FK violation
    // abort the whole sync batch.
    let conn = test_db();
    let inbox_id = lorvex_store::INBOX_LIST_ID;

    // Missing field
    let payload_missing = r#"{
        "title": "no list_id key",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_missing = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003137",
        V2,
        payload_missing,
    );
    let r = apply_envelope(&conn, &env_missing).unwrap();
    assert_eq!(r, ApplyResult::Applied);
    let stored: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003137'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, inbox_id,
        "missing list_id should fall back to the inbox list"
    );

    // Empty-string field
    let payload_empty = r#"{
        "title": "empty list_id",
        "status": "open",
        "list_id": "",
        "defer_count": 0,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_empty = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003135",
        V2,
        payload_empty,
    );
    let r = apply_envelope(&conn, &env_empty).unwrap();
    assert_eq!(r, ApplyResult::Applied);
    let stored: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003135'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, inbox_id,
        "empty-string list_id should fall back to the inbox list"
    );
}

// ===========================================================================
// 2. LWW: older version after newer -> no change
// ===========================================================================

#[test]
fn lww_older_version_after_newer_is_skipped() {
    let conn = test_db();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000310d");

    let newer_payload = r#"{
        "title": "New title",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T12:00:00.000Z"
    }"#;
    let older_payload = r#"{
        "title": "Old title",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T09:00:00.000Z"
    }"#;

    // Apply newer version first.
    let env_new = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003125",
        V3,
        newer_payload,
    );
    let r1 = apply_envelope(&conn, &env_new).unwrap();
    assert_eq!(r1, ApplyResult::Applied);

    // Now apply older version.
    let env_old = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003125",
        V1,
        older_payload,
    );
    let r2 = apply_envelope(&conn, &env_old).unwrap();
    assert!(matches!(r2, ApplyResult::Skipped { .. }));

    // Task still has the newer title.
    let title: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003125'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title, "New title");
}

// ===========================================================================
// 3. Tombstone + upsert ordering: tombstone blocks lower-version upsert
// ===========================================================================

#[test]
fn tombstone_blocks_lower_version_upsert() {
    let conn = test_db();

    // Create a tombstone with V2.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003126",
        V2,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Apply upsert with V1 (lower than tombstone V2).
    let payload = r#"{
        "title": "Should not appear",
        "status": "open",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003126",
        V1,
        payload,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));

    // Task should not exist.
    assert_eq!(
        count_rows(
            &conn,
            "tasks",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003126'"
        ),
        0
    );

    // Tombstone should still exist.
    let ts = get_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003126",
    )
    .unwrap();
    assert!(ts.is_some());
}

// ===========================================================================
// 4. Concurrent update wins over delete: upsert with HIGHER version restores
// ===========================================================================

#[test]
fn concurrent_update_wins_over_delete() {
    let conn = test_db();

    // Create tombstone with V1.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003127",
        V1,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Apply upsert with V3 (strictly newer than tombstone V1).
    let payload = r#"{
        "title": "Restored task",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-23T14:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003127",
        V3,
        payload,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Task should be restored.
    let title: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003127'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title, "Restored task");

    // Tombstone should be removed.
    let ts = get_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000003127",
    )
    .unwrap();
    assert!(ts.is_none());
}

// ===========================================================================
// 5. Tombstone redirect: delayed upsert for tombstoned entity is remapped
// ===========================================================================

#[test]
fn tombstone_redirect_remaps_entity() {
    let conn = test_db();
    seed_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000003123",
        "work",
        "work",
    );

    // Create a tombstone for 01966a3f-7c8b-7d4e-8f3a-000000003121 with redirect to 01966a3f-7c8b-7d4e-8f3a-000000003123.
    // This simulates a tag merge where 01966a3f-7c8b-7d4e-8f3a-000000003121 was absorbed into 01966a3f-7c8b-7d4e-8f3a-000000003123.
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003121",
        V2,
        "2026-03-23T12:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000003123"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // A delayed tag upsert arrives from another device for the now-tombstoned tag.
    let payload = r#"{
        "name": "work",
        "display_name": "Work",
        "lookup_key": "work",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T11:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003121",
        V1,
        payload,
    );

    let result = apply_envelope(&conn, &env).unwrap();

    // Should be remapped (redirect tombstone is authoritative regardless of version).
    match result {
        ApplyResult::Remapped {
            from_entity_id,
            to_entity_id,
        } => {
            assert_eq!(from_entity_id, "01966a3f-7c8b-7d4e-8f3a-000000003121");
            assert_eq!(to_entity_id, "01966a3f-7c8b-7d4e-8f3a-000000003123");
        }
        other => panic!("expected Remapped, got {other:?}"),
    }

    // 01966a3f-7c8b-7d4e-8f3a-000000003121 should NOT be created in the tags table.
    assert_eq!(
        count_rows(&conn, "tags", "id = '01966a3f-7c8b-7d4e-8f3a-000000003121'"),
        0
    );

    // The tombstone should still exist.
    let ts = get_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003121",
    )
    .unwrap();
    assert!(ts.is_some());
}
