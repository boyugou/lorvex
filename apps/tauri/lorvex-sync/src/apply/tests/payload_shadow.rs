use super::*;
use crate::pending_inbox::get_all_pending;
fn assert_equal_version_clears_shadow(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &str,
) {
    // Arrange: a shadow row at MATRIX_V_A.
    lorvex_sync_payload::payload_shadow::upsert_shadow(
        conn,
        entity_type,
        entity_id,
        MATRIX_V_A,
        PAYLOAD_SCHEMA_VERSION,
        payload,
        "test-device",
    )
    .unwrap();
    let shadow_before =
        lorvex_sync_payload::payload_shadow::get_shadow(conn, entity_type, entity_id).unwrap();
    assert!(
        shadow_before.is_some(),
        "shadow arrangement failed for {entity_type}"
    );

    // Act: apply a fully-parsed envelope at the same version.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(MATRIX_V_A)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(conn, &env).unwrap();
    assert_eq!(
        result,
        ApplyResult::Applied,
        "baseline apply must succeed for {entity_type}"
    );

    // Assert: shadow cleared because `candidate_version >= shadow_version`.
    let shadow_after =
        lorvex_sync_payload::payload_shadow::get_shadow(conn, entity_type, entity_id).unwrap();
    assert!(
        shadow_after.is_none(),
        "equal-version fully-parsed apply must clear the payload shadow \
         for {entity_type}, still present: {shadow_after:?}"
    );
}

#[test]
fn promote_payload_shadows_applies_pending_shadows() {
    let conn = test_db();

    // Insert a shadow record that should be promotable
    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version, payload_schema_version, raw_payload_json, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            naming::ENTITY_LIST,
            "01966a3f-7c8b-7d4e-8f3a-00000000213e",
            "1711234560000_0000_a1b2c3d4a1b2c3d4",
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            r#"{"name":"Promoted List","created_at":"2026-03-01T00:00:00Z","updated_at":"2026-03-01T00:00:00Z"}"#,
            "2026-03-01T00:00:00Z",
        ],
    ).unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(promoted, 1, "should promote one shadow");

    // The list should now exist in the lists table
    let name: String = conn
        .query_row(
            "SELECT name FROM lists WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000213e'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(name, "Promoted List");
}

#[test]
fn promote_payload_shadows_skips_future_schema_versions() {
    let conn = test_db();

    // Insert a shadow with a future schema version
    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version, payload_schema_version, raw_payload_json, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            naming::ENTITY_LIST,
            "01966a3f-7c8b-7d4e-8f3a-000000002138",
            "1711234560000_0000_a1b2c3d4a1b2c3d4",
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION + 100,
            r#"{"name":"Future List","created_at":"","updated_at":""}"#,
            "2026-03-01T00:00:00Z",
        ],
    ).unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(promoted, 0, "should skip future-version shadows");
}

#[test]
fn equal_version_upsert_promotes_payload_shadow_task() {
    let conn = test_db();
    assert_equal_version_clears_shadow(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000219a",
        r#"{"title":"t","status":"open","defer_count":0,"created_at":"","updated_at":""}"#,
    );
}

#[test]
fn equal_version_upsert_promotes_payload_shadow_tag() {
    let conn = test_db();
    assert_equal_version_clears_shadow(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000002160",
        r#"{"display_name":"tag","lookup_key":"tag","created_at":"","updated_at":""}"#,
    );
}

#[test]
fn equal_version_upsert_promotes_payload_shadow_current_focus() {
    let conn = test_db();
    assert_equal_version_clears_shadow(
        &conn,
        naming::ENTITY_CURRENT_FOCUS,
        "2026-04-06",
        r#"{"briefing":"b","timezone":"UTC","task_ids":[],"created_at":"2026-04-06","updated_at":"2026-04-06"}"#,
    );
}

/// when a payload shadow's `base_version`
/// is older than the current local row's version (i.e. the row has
/// been updated since the shadow was written), `promote_payload_shadows`
/// must NOT silently drop the shadow's contents. The fix logs a
/// `shadow_obsolete` conflict, removes the shadow, and leaves the
/// live row untouched.
#[test]
fn promote_payload_shadows_refuses_to_overwrite_newer_local_row_and_logs_conflict() {
    let conn = test_db();

    // Seed a `list` row at the NEWER version. This represents the
    // local row state as of right now (e.g. a subsequent edit).
    let list_id = "01966a3f-7c8b-7d4e-8f3a-000000002139";
    let newer_local_version = "1711234600000_0000_dec0000100000001";
    let older_shadow_version = "1711234560000_0000_dec0000200000002";
    lorvex_store::test_support::ListBuilder::new(list_id)
        .name("Updated Name")
        .version(newer_local_version)
        .created_at("2026-04-01T00:00:00Z")
        .updated_at("2026-04-01T00:01:00Z")
        .insert(&conn);

    // Seed a payload shadow at an OLDER base_version, representing
    // an earlier forward-compat envelope whose unknown fields the
    // shadow was preserving for promotion.
    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version,
                                          payload_schema_version, raw_payload_json,
                                          source_device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            naming::ENTITY_LIST,
            list_id,
            older_shadow_version,
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            r#"{"id":"01966a3f-7c8b-7d4e-8f3a-000000002139","name":"Old Name","created_at":"2026-03-01T00:00:00Z","updated_at":"2026-03-01T00:00:00Z","future_field":"forward-compat"}"#,
            "remote-device",
            "2026-04-01T00:00:00Z",
        ],
    )
    .unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(
        promoted, 0,
        "promotion must refuse when local row is strictly newer than shadow"
    );

    // The live row's name must remain unchanged ("Updated Name").
    let stored_name: String = conn
        .query_row("SELECT name FROM lists WHERE id = ?1", [list_id], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(
        stored_name, "Updated Name",
        "the newer local row must NOT be overwritten by the obsolete shadow"
    );

    // The live row's version must remain at the newer local version.
    let stored_version: String = conn
        .query_row(
            "SELECT version FROM lists WHERE id = ?1",
            [list_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored_version, newer_local_version);

    // The shadow must be reaped — leaving it would re-trigger the
    // same flawed promote on the next pass.
    let shadow_after =
        lorvex_sync_payload::payload_shadow::get_shadow(&conn, naming::ENTITY_LIST, list_id)
            .unwrap();
    assert!(
        shadow_after.is_none(),
        "obsolete shadow must be reaped after a refused promotion"
    );

    // A `shadow_obsolete` conflict_log entry must surface the drop.
    let conflict_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![
                naming::ENTITY_LIST,
                list_id,
                naming::RESOLUTION_SHADOW_OBSOLETE
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_count, 1,
        "exactly one `shadow_obsolete` conflict_log entry must be written"
    );
}

/// An obsolete shadow must be dropped before FK preflight. Otherwise a
/// stale shadow whose payload names a missing parent gets parked in
/// `sync_pending_inbox` even though the newer live row has already won.
#[test]
fn promote_payload_shadows_drops_obsolete_shadow_before_fk_preflight() {
    let conn = test_db();

    let valid_list_id = "01966a3f-7c8b-7d4e-8f3a-000000002135";
    let missing_list_id = "01966a3f-7c8b-7d4e-8f3a-00000000213b";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000219c";
    let newer_local_version = "1711234600000_0000_dec0000100000001";
    let older_shadow_version = "1711234560000_0000_dec0000200000002";

    lorvex_store::test_support::ListBuilder::new(valid_list_id)
        .name("Current List")
        .version(newer_local_version)
        .created_at("2026-04-01T00:00:00Z")
        .updated_at("2026-04-01T00:01:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title("Current Task")
        .list_id(Some(valid_list_id))
        .version(newer_local_version)
        .created_at("2026-04-01T00:00:00Z")
        .updated_at("2026-04-01T00:01:00Z")
        .insert(&conn);

    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version,
                                          payload_schema_version, raw_payload_json,
                                          source_device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            naming::ENTITY_TASK,
            task_id,
            older_shadow_version,
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            format!(
                r#"{{"title":"Obsolete Task","status":"open","list_id":"{missing_list_id}","defer_count":0,"created_at":"2026-03-01T00:00:00Z","updated_at":"2026-03-01T00:00:00Z","future_field":"forward-compat"}}"#,
            ),
            "remote-device",
            "2026-04-01T00:00:00Z",
        ],
    )
    .unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(
        promoted, 0,
        "obsolete shadow must not promote over the newer live row"
    );

    let pending = get_all_pending(&conn).unwrap();
    assert!(
        pending.is_empty(),
        "obsolete shadow must be dropped instead of parked in pending inbox: {pending:?}"
    );

    let shadow_after =
        lorvex_sync_payload::payload_shadow::get_shadow(&conn, naming::ENTITY_TASK, task_id)
            .unwrap();
    assert!(
        shadow_after.is_none(),
        "obsolete shadow must be reaped after the newer live row wins"
    );

    let stored_title: String = conn
        .query_row("SELECT title FROM tasks WHERE id = ?1", [task_id], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(stored_title, "Current Task");

    let conflict_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![
                naming::ENTITY_TASK,
                task_id,
                naming::RESOLUTION_SHADOW_OBSOLETE
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_count, 1,
        "obsolete shadow must write one shadow_obsolete diagnostic"
    );
}

/// A corrupt local version must not make the obsolete-shadow gate fail
/// before FK preflight can park an otherwise retryable shadow.
#[test]
fn promote_payload_shadows_defers_missing_fk_when_local_version_is_corrupt() {
    let conn = test_db();

    let valid_list_id = "01966a3f-7c8b-7d4e-8f3a-000000002133";
    let missing_list_id = "01966a3f-7c8b-7d4e-8f3a-000000002134";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000219b";
    let shadow_version = "1711234560000_0000_dec0000300000003";

    lorvex_store::test_support::ListBuilder::new(valid_list_id)
        .name("Current List")
        .version(shadow_version)
        .created_at("2026-04-01T00:00:00Z")
        .updated_at("2026-04-01T00:01:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title("Current Task")
        .list_id(Some(valid_list_id))
        .version("not-an-hlc")
        .created_at("2026-04-01T00:00:00Z")
        .updated_at("2026-04-01T00:01:00Z")
        .insert(&conn);

    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version,
                                          payload_schema_version, raw_payload_json,
                                          source_device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            naming::ENTITY_TASK,
            task_id,
            shadow_version,
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            format!(
                r#"{{"title":"Retryable Task","status":"open","list_id":"{missing_list_id}","defer_count":0,"created_at":"2026-03-01T00:00:00Z","updated_at":"2026-03-01T00:00:00Z","future_field":"forward-compat"}}"#,
            ),
            "remote-device",
            "2026-04-01T00:00:00Z",
        ],
    )
    .unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(
        promoted, 0,
        "missing FK shadow cannot promote until its parent arrives"
    );

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "retryable shadow must be parked once");

    let shadow_after =
        lorvex_sync_payload::payload_shadow::get_shadow(&conn, naming::ENTITY_TASK, task_id)
            .unwrap();
    assert!(
        shadow_after.is_some(),
        "retryable FK-missing shadow must remain durable until replay"
    );

    let corruption_logs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.apply.local_version_corruption'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        corruption_logs, 1,
        "corrupt local version must be surfaced diagnostically"
    );

    let conflict_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![
                naming::ENTITY_TASK,
                task_id,
                naming::RESOLUTION_SHADOW_OBSOLETE
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_count, 0,
        "corrupt local version is not enough evidence to reap the shadow"
    );
}
