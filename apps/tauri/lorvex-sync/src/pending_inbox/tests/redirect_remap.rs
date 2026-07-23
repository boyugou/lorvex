use super::super::*;
use super::support::*;

const REDIRECT_TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000002163";
const REDIRECT_OLD_TAG_ID: &str = "01966a3f-7c8b-7d4e-8f3a-00000000215f";
const REDIRECT_NEW_TAG_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000002161";
const REDIRECT_EDGE_VERSION: &str = "1711234567890_0000_a1b2c3d4a1b2c3d4";

fn task_tag_envelope(task_id: &str, tag_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskTag,
        entity_id: format!("{task_id}:{tag_id}"),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(REDIRECT_EDGE_VERSION)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: r#"{"created_at":"2026-03-27T09:00:00Z"}"#.to_string(),
        device_id: "device-001".to_string(),
    }
}

#[test]
fn drain_pending_inbox_remaps_composite_redirect_via_entity_id_when_payload_lacks_fk_fields() {
    // a composite-edge envelope whose
    // payload omits the typed FK fields but whose entity_id
    // carries the loser identity is still actionable — the
    // entity_id rewrite alone fully specifies the redirect target.
    // The prior shape returned a hard error here, blocking the
    // drain pass for an envelope that could legitimately replay.
    let conn = test_db();
    enqueue_pending(
        &conn,
        &SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::TaskTag,
            entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002163:01966a3f-7c8b-7d4e-8f3a-00000000215f"
                .to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: 1,
            payload: r#"{"created_at":"2026-03-27T09:00:00Z"}"#.to_string(),
            device_id: "device-001".to_string(),
        },
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TAG),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000215f"),
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        "1711234569000_0000_deadbeefdeadbeef",
        "2026-03-27T10:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let result = drain_pending_inbox(&conn);
    assert!(
        result.is_ok(),
        "composite edge redirect via entity_id alone should drain cleanly"
    );
}

#[test]
fn drain_pending_inbox_coalesces_identity_collision_after_redirect_remap() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Merged tag', 'merged tag', ?2, '2026-03-27T09:00:00Z', '2026-03-27T09:00:00Z')",
        params![REDIRECT_NEW_TAG_ID, "1711234569000_0000_deadbeefdeadbeef"],
    )
    .expect("seed redirect target tag");

    enqueue_pending(
        &conn,
        &task_tag_envelope(REDIRECT_TASK_ID, REDIRECT_NEW_TAG_ID),
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some(REDIRECT_TASK_ID),
    )
    .expect("seed existing target identity row");
    enqueue_pending(
        &conn,
        &task_tag_envelope(REDIRECT_TASK_ID, REDIRECT_OLD_TAG_ID),
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TAG),
        Some(REDIRECT_OLD_TAG_ID),
    )
    .expect("seed row that will remap into existing target identity");
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        REDIRECT_OLD_TAG_ID,
        "1711234569000_0000_deadbeefdeadbeef",
        "2026-03-27T10:00:00.000Z",
        Some(REDIRECT_NEW_TAG_ID),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).expect("redirect collision should coalesce");

    assert_eq!(summary.errors, 0);
    assert_eq!(summary.remapped, 1);
    assert_eq!(count_pending(&conn).unwrap(), 1);

    let row = conn
        .query_row(
            "SELECT envelope_entity_type, envelope_entity_id, envelope_version,
                    missing_entity_type, missing_entity_id, attempt_count
             FROM sync_pending_inbox",
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            },
        )
        .expect("read coalesced pending row");

    assert_eq!(row.0, naming::EDGE_TASK_TAG);
    assert_eq!(
        row.1,
        format!("{REDIRECT_TASK_ID}:{REDIRECT_NEW_TAG_ID}"),
        "only the redirect target identity should remain pending"
    );
    assert_eq!(row.2, REDIRECT_EDGE_VERSION);
    assert_eq!(row.3.as_deref(), Some(naming::ENTITY_TASK));
    assert_eq!(row.4.as_deref(), Some(REDIRECT_TASK_ID));
    assert_eq!(
        row.5, 3,
        "existing row attempt, remapped row merge, and final reattempt should be reflected"
    );
}

#[test]
fn drain_discards_malformed_composite_redirect_entity_id() {
    let conn = test_db();
    enqueue_pending(
        &conn,
        &SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::TaskTag,
            entity_id:
                "01966a3f-7c8b-7d4e-8f3a-000000002163:01966a3f-7c8b-7d4e-8f3a-00000000215f:extra"
                    .to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: 1,
            payload: r#"{"created_at":"2026-03-27T09:00:00Z"}"#.to_string(),
            device_id: "device-001".to_string(),
        },
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TAG),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000215f"),
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        "1711234569000_0000_deadbeefdeadbeef",
        "2026-03-27T10:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).expect("malformed redirect should not abort drain");

    assert_eq!(summary.discarded, 1);
    assert_eq!(count_pending(&conn).unwrap(), 0);
}
