//! `merge_shadow_into_redirect`: when a redirect tombstone lands, the
//! loser's shadow row must merge its forward-compat keys into the
//! winner's shadow row, even at equal versions.

use super::support::*;

/// when redirect-merge runs and the loser's
/// `base_version` ties the existing winner's, the merged
/// row MUST land — its `raw_payload_json` carries the union of
/// loser-exclusive keys with the winner's. The previous
/// strictly-greater predicate dropped this write silently, then
/// `remove_shadow(loser)` deleted the loser unconditionally, so
/// any forward-compat fields that lived only on the loser were
/// silently lost.
#[test]
fn merge_shadow_into_redirect_preserves_loser_keys_at_equal_version() {
    let conn = open_db_in_memory().unwrap();
    let shared_version = "1711234567000_0001_a1b2c3d4a1b2c3d4".to_string();

    // Winner shadow at the redirect target — has `winner_only` key.
    restore_shadow(
        &conn,
        &PayloadShadowRow {
            entity_type: EntityKind::Task,
            entity_id: "task-target".to_string(),
            base_version: shared_version.clone(),
            payload_schema_version: 1,
            raw_payload_json: r#"{"id":"task-target","title":"Winner","winner_only":"keep_me"}"#
                .to_string(),
            source_device_id: "device-winner".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
        },
    )
    .unwrap();

    // Loser shadow at the original id — has `loser_only` key,
    // SAME `base_version` as the winner.
    restore_shadow(
        &conn,
        &PayloadShadowRow {
            entity_type: EntityKind::Task,
            entity_id: "task-source".to_string(),
            base_version: shared_version,
            payload_schema_version: 1,
            raw_payload_json:
                r#"{"id":"task-source","title":"Loser","loser_only":"forward_compat"}"#.to_string(),
            source_device_id: "device-loser".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
        },
    )
    .unwrap();

    merge_shadow_into_redirect(
        &conn,
        ENTITY_TASK,
        "task-source",
        ENTITY_TASK,
        "task-target",
    )
    .expect("redirect merge must succeed");

    let merged = get_shadow(&conn, ENTITY_TASK, "task-target")
        .unwrap()
        .expect("winner shadow must survive");
    let merged_json: serde_json::Value = serde_json::from_str(&merged.raw_payload_json).unwrap();
    assert_eq!(
        merged_json.get("winner_only").and_then(|v| v.as_str()),
        Some("keep_me"),
        "winner-only keys must persist after merge"
    );
    assert_eq!(
        merged_json.get("loser_only").and_then(|v| v.as_str()),
        Some("forward_compat"),
        "loser-only keys MUST survive equal-version redirect merge (#2858)"
    );

    // Loser row is gone.
    assert!(
        get_shadow(&conn, ENTITY_TASK, "task-source")
            .unwrap()
            .is_none(),
        "loser shadow row should be removed after merge"
    );
}
