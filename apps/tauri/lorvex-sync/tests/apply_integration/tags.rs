use super::support::*;

// ===========================================================================

#[test]
fn tag_convergence_min_id_wins() {
    let conn = test_db();

    // Insert 01966a3f-7c8b-7d4e-8f3a-000000003118 first (will be the winner because "01966a3f-7c8b-7d4e-8f3a-000000003118" < "01966a3f-7c8b-7d4e-8f3a-00000000311a").
    let payload_a = r#"{
        "name": "work",
        "display_name": "Work",
        "lookup_key": "work",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_a = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003118",
        V2,
        payload_a,
    );
    let r1 = apply_envelope(&conn, &env_a).unwrap();
    assert_eq!(r1, ApplyResult::Applied);

    // Insert 01966a3f-7c8b-7d4e-8f3a-00000000311a with the same lookup_key (will be the loser).
    let payload_b = r#"{
        "name": "Work",
        "display_name": "Work",
        "lookup_key": "work",
        "created_at": "2026-03-20T11:00:00.000Z",
        "updated_at": "2026-03-20T11:00:00.000Z"
    }"#;
    let env_b = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311a",
        V2,
        payload_b,
    );
    let r2 = apply_envelope(&conn, &env_b).unwrap();
    assert_eq!(r2, ApplyResult::Applied);

    // 01966a3f-7c8b-7d4e-8f3a-000000003118 (min ID) should survive.
    assert_eq!(
        count_rows(&conn, "tags", "id = '01966a3f-7c8b-7d4e-8f3a-000000003118'"),
        1
    );

    // 01966a3f-7c8b-7d4e-8f3a-00000000311a should be deleted.
    assert_eq!(
        count_rows(&conn, "tags", "id = '01966a3f-7c8b-7d4e-8f3a-00000000311a'"),
        0
    );

    // 01966a3f-7c8b-7d4e-8f3a-00000000311a should be tombstoned with redirect to 01966a3f-7c8b-7d4e-8f3a-000000003118.
    let ts = get_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311a",
    )
    .unwrap()
    .expect("01966a3f-7c8b-7d4e-8f3a-00000000311a should be tombstoned");
    assert_eq!(
        ts.redirect_entity_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-000000003118")
    );
    assert_eq!(ts.redirect_entity_type.as_deref(), Some(naming::ENTITY_TAG));
}

// ===========================================================================
// 7. Tag merge re-points task_tags from loser to winner
// ===========================================================================

#[test]
fn tag_merge_repoints_task_tags() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003128");

    // Insert 01966a3f-7c8b-7d4e-8f3a-000000003118.
    let payload_a = r#"{
        "name": "urgent",
        "display_name": "Urgent",
        "lookup_key": "urgent",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_a = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003118",
        V2,
        payload_a,
    );
    apply_envelope(&conn, &env_a).unwrap();

    // Create a task_tag linking 01966a3f-7c8b-7d4e-8f3a-000000003128 to 01966a3f-7c8b-7d4e-8f3a-000000003118.
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-000000003128', '01966a3f-7c8b-7d4e-8f3a-000000003118', '0000000000000_0000_0000000000000000', '2026-03-20T10:00:00.000Z')",
        [],
    )
    .unwrap();

    // Now insert 01966a3f-7c8b-7d4e-8f3a-00000000311a with the same lookup_key. It should be merged into 01966a3f-7c8b-7d4e-8f3a-000000003118.
    let payload_b = r#"{
        "name": "Urgent",
        "display_name": "Urgent",
        "lookup_key": "urgent",
        "created_at": "2026-03-20T11:00:00.000Z",
        "updated_at": "2026-03-20T11:00:00.000Z"
    }"#;
    let env_b = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311a",
        V2,
        payload_b,
    );
    apply_envelope(&conn, &env_b).unwrap();

    // 01966a3f-7c8b-7d4e-8f3a-00000000311a's task_tags should have been re-pointed to 01966a3f-7c8b-7d4e-8f3a-000000003118.
    // (In this case 01966a3f-7c8b-7d4e-8f3a-00000000311a had no task_tags of its own, but 01966a3f-7c8b-7d4e-8f3a-000000003118's should remain.)
    assert_eq!(
        count_rows(
            &conn,
            "task_tags",
            "tag_id = '01966a3f-7c8b-7d4e-8f3a-000000003118'"
        ),
        1,
        "winner should retain its task_tags"
    );
    assert_eq!(
        count_rows(
            &conn,
            "task_tags",
            "tag_id = '01966a3f-7c8b-7d4e-8f3a-00000000311a'"
        ),
        0,
        "loser's task_tags should be removed"
    );

    // Now test re-pointing: create a task_tag for the loser BEFORE merge.
    // Reset: delete everything and redo with loser having a task_tag.
    conn.execute("DELETE FROM task_tags", []).unwrap();
    conn.execute("DELETE FROM tags", []).unwrap();
    conn.execute("DELETE FROM sync_tombstones WHERE entity_type = 'tag'", [])
        .unwrap();

    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003129");

    // Insert 01966a3f-7c8b-7d4e-8f3a-00000000311c with display_name "Health" (lookup_key "health").
    // NB: `apply_tag_upsert` re-derives `lookup_key` from
    // `display_name` at the sync trust boundary — the payload-supplied
    // `lookup_key` field is ignored (see R16 fix in apply/tag.rs), so
    // this test must drive convergence via display_name changes only.
    let payload_c = r#"{
        "name": "health",
        "display_name": "Health",
        "lookup_key": "health",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_c = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311c",
        V2,
        payload_c,
    );
    apply_envelope(&conn, &env_c).unwrap();

    // Insert 01966a3f-7c8b-7d4e-8f3a-00000000311d with a distinct display_name so its derived
    // lookup_key ("wellness") differs from 01966a3f-7c8b-7d4e-8f3a-00000000311c's ("health") and
    // no merge happens yet.
    let payload_d = r#"{
        "name": "Wellness",
        "display_name": "Wellness",
        "lookup_key": "unused",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_d = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311d",
        V2,
        payload_d,
    );
    apply_envelope(&conn, &env_d).unwrap();

    // Assign 01966a3f-7c8b-7d4e-8f3a-000000003129 to 01966a3f-7c8b-7d4e-8f3a-00000000311d (the future loser).
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-000000003129', '01966a3f-7c8b-7d4e-8f3a-00000000311d', '0000000000000_0000_0000000000000000', '2026-03-20T10:00:00.000Z')",
        [],
    )
    .unwrap();

    // Now update 01966a3f-7c8b-7d4e-8f3a-00000000311d's display_name so its derived lookup_key
    // collides with 01966a3f-7c8b-7d4e-8f3a-00000000311c's, triggering convergence.
    let payload_d_updated = r#"{
        "name": "Health",
        "display_name": "Health",
        "lookup_key": "unused",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T12:00:00.000Z"
    }"#;
    let env_d2 = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311d",
        V3,
        payload_d_updated,
    );
    apply_envelope(&conn, &env_d2).unwrap();

    // 01966a3f-7c8b-7d4e-8f3a-00000000311c (min ID) should win.
    assert_eq!(
        count_rows(&conn, "tags", "id = '01966a3f-7c8b-7d4e-8f3a-00000000311c'"),
        1
    );
    assert_eq!(
        count_rows(&conn, "tags", "id = '01966a3f-7c8b-7d4e-8f3a-00000000311d'"),
        0
    );

    // 01966a3f-7c8b-7d4e-8f3a-000000003129 should now be tagged with 01966a3f-7c8b-7d4e-8f3a-00000000311c (re-pointed from 01966a3f-7c8b-7d4e-8f3a-00000000311d).
    let tag_id: String = conn
        .query_row(
            "SELECT tag_id FROM task_tags WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000003129'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        tag_id, "01966a3f-7c8b-7d4e-8f3a-00000000311c",
        "task_tag should be re-pointed to winner"
    );
}

#[test]
fn tag_convergence_rejects_malformed_existing_tag_versions() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000311e', 'Work', 'work', 'not-a-valid-hlc', '2026-03-20T10:00:00.000Z', '2026-03-20T10:00:00.000Z')",
        [],
    )
    .unwrap();

    let payload = r#"{
        "name": "Work",
        "display_name": "Work",
        "lookup_key": "work",
        "created_at": "2026-03-20T11:00:00.000Z",
        "updated_at": "2026-03-20T11:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003120",
        V2,
        payload,
    );

    let error = apply_envelope(&conn, &env)
        .expect_err("tag convergence should fail on malformed existing versions");

    let message = error.to_string().to_lowercase();
    assert!(message.contains("version"));
}
