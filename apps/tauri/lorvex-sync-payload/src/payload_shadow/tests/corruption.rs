//! Defensive recovery from a corrupted persisted shadow row.

use super::support::*;

#[test]
fn remove_shadow_if_superseded_drops_corrupted_shadow_row_instead_of_failing() {
    // Audit (payload_shadow F4): a corrupted persisted
    // `base_version` used to fail the entire apply path here —
    // one bad shadow row blocked every subsequent envelope for
    // the entity. The new contract is log-and-delete: we can't
    // compare a malformed version against the candidate, so we
    // also can't claim the shadow is preserving anything useful.
    // The candidate envelope MUST be allowed to proceed.
    let conn = open_db_in_memory().unwrap();
    restore_shadow(
        &conn,
        &PayloadShadowRow {
            entity_type: EntityKind::Task,
            entity_id: "task-1".to_string(),
            base_version: "not-a-valid-hlc".to_string(),
            payload_schema_version: 2,
            raw_payload_json: r#"{"id":"task-1","title":"Shadow"}"#.to_string(),
            source_device_id: "token=secret".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
        },
    )
    .unwrap();

    let result = remove_shadow_if_superseded(
        &conn,
        ENTITY_TASK,
        "task-1",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
    );

    assert!(
        result.is_ok(),
        "corrupted shadow must NOT block apply — got {result:?}"
    );
    let surviving = get_shadow(&conn, ENTITY_TASK, "task-1").unwrap();
    assert!(
        surviving.is_none(),
        "corrupted shadow row must be dropped so it cannot block future applies"
    );

    let diagnostic: (String, String, String, Option<String>) = conn
        .query_row(
            "SELECT source, level, message, details FROM error_logs",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read corrupted payload-shadow diagnostic");
    assert_eq!(diagnostic.0, "store.payload_shadow.corrupted_base_version");
    assert_eq!(diagnostic.1, "warn");
    assert_eq!(
        diagnostic.2,
        "corrupted base_version on persisted payload shadow"
    );
    assert_eq!(
        diagnostic.3.as_deref(),
        Some(
            "entity_type=task entity_id=task-1 base_version=not-a-valid-hlc \
             source_device_id=[REDACTED] error=validation error: invalid HLC in payload shadow \
             base_version: not-a-valid-hlc"
        )
    );
}
