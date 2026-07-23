//! `ShadowIndex` is the fast-path snapshot the export pipeline uses
//! to short-circuit `merge_payload_with_shadow_indexed` when the
//! `(entity_type, entity_id)` key has no shadow row. Closes
//! cross-cutting audit finding #7 — the helper shipped without unit
//! tests; only an export-integration round-trip implicitly exercised
//! it.

use super::support::*;

#[test]
fn shadow_index_indexed_returns_known_payload_when_no_shadow() {
    // Empty `sync_payload_shadow` table → the index reports no
    // membership → `merge_payload_with_shadow_indexed` must return
    // the input payload byte-equal (cloned) without any DB lookup
    // beyond the index build.
    let conn = open_db_in_memory().unwrap();

    let index = super::super::merge::ShadowIndex::build(&conn).expect("build empty shadow index");
    let known = serde_json::json!({"id": "task-1", "title": "no shadow"});
    let merged = super::super::merge::merge_payload_with_shadow_indexed(
        &conn,
        &index,
        ENTITY_TASK,
        "task-1",
        &known,
    )
    .expect("merge with empty index should succeed");
    assert_eq!(merged, known, "absent shadow must round-trip the input");
}

#[test]
fn shadow_index_indexed_falls_through_to_unindexed_merge_when_shadow_exists() {
    // A real shadow row is present for (task, task-2). The index
    // must report it, so `merge_payload_with_shadow_indexed` falls
    // through to the unindexed merge — which overlays the shadow's
    // forward-compat unknown keys onto the known payload.
    let conn = open_db_in_memory().unwrap();
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-2",
        "0001000000000_0001_devicea0000000",
        1,
        r#"{"future_field":"hello","title":"old"}"#,
        "device-x",
    )
    .expect("seed shadow row");

    let index = super::super::merge::ShadowIndex::build(&conn).expect("build index");
    let known = serde_json::json!({"id": "task-2", "title": "current"});
    let merged = super::super::merge::merge_payload_with_shadow_indexed(
        &conn,
        &index,
        ENTITY_TASK,
        "task-2",
        &known,
    )
    .expect("merge with shadow present should succeed");

    let obj = merged.as_object().expect("merged result must be an object");
    assert_eq!(
        obj.get("future_field").and_then(|v| v.as_str()),
        Some("hello"),
        "indexed merge must preserve the shadow's forward-compat keys",
    );
    assert_eq!(
        obj.get("title").and_then(|v| v.as_str()),
        Some("current"),
        "known fields must override shadow on collision",
    );
}

#[test]
fn shadow_index_indexed_does_not_short_circuit_for_cross_type_redirect_tombstone() {
    // The index intentionally indexes only the shadow-present case.
    // A cross-type redirect tombstone with no shadow row must NOT
    // be short-circuited by the index — the unindexed merge path
    // owns the cross-type stale-shadow drop logic. This test pins
    // that contract: with no shadow but a cross-type tombstone in
    // place, the indexed path returns the known payload (because
    // the index reports no shadow). The cross-type tombstone
    // detection only fires inside the unindexed merge AFTER it
    // confirms a shadow exists; the index correctly skips that
    // case.
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at, redirect_entity_type, redirect_entity_id) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            ENTITY_TASK,
            "task-3",
            "0001000000000_0001_devicea0000000",
            "2026-04-01T12:00:00Z",
            ENTITY_LIST,
            "list-3",
        ],
    )
    .expect("seed cross-type redirect tombstone");

    let index = super::super::merge::ShadowIndex::build(&conn).expect("build index");
    let known = serde_json::json!({"id": "task-3", "status": "open"});
    let merged = super::super::merge::merge_payload_with_shadow_indexed(
        &conn,
        &index,
        ENTITY_TASK,
        "task-3",
        &known,
    )
    .expect("merge with no shadow + cross-type tombstone should succeed");
    assert_eq!(
        merged, known,
        "cross-type tombstone with no shadow must round-trip — the index correctly reports no shadow",
    );
}
