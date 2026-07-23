//! `merge_payload_with_shadow` semantics — the unindexed merge that
//! composes the live envelope with the persisted unknown-key shadow,
//! including the cross-type vs. same-type redirect tombstone branches
//! and malformed-shadow rejection.

use super::support::*;

#[test]
fn merge_payload_with_shadow_preserves_unknown_fields() {
    let conn = open_db_in_memory().unwrap();
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-1",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        r#"{"id":"task-1","title":"Shadow","new_field":"preserve","version":"1711234567000_0000_a1b2c3d4a1b2c3d4"}"#,
        "device-test",
    )
    .unwrap();

    let merged = merge_payload_with_shadow(
        &conn,
        ENTITY_TASK,
        "task-1",
        &serde_json::json!({
            "id": "task-1",
            "title": "Known",
            "status": "open",
        }),
    )
    .unwrap();

    assert_eq!(merged.get("title").and_then(Value::as_str), Some("Known"));
    assert_eq!(merged.get("status").and_then(Value::as_str), Some("open"));
    assert_eq!(
        merged.get("new_field").and_then(Value::as_str),
        Some("preserve")
    );
    assert!(merged.get("version").is_none());
}

/// a stale shadow at `(T1, id)` paired with a
/// cross-type-redirect tombstone at the same key (T1, id) →
/// (T2, id) must NOT be merged into the local known payload.
/// Pre-fix `merge_payload_with_shadow` had no way to detect the
/// cross-type redirect — it would happily merge loser-schema
/// unknown keys into the live payload, polluting fields that
/// don't exist in the loser schema (or worse, fields whose
/// semantics differ between schemas).
///
/// Setup:
///   - Shadow at (`task`, `id-merged`) with forward-compat
///     unknown key from a peer running a newer task schema.
///   - Tombstone at (`task`, `id-merged`) redirecting to
///     (`habit`, `id-merged`) — a hypothetical cross-type merge.
///
/// Expected: `merge_payload_with_shadow` returns the known
/// payload UNCHANGED (the stale loser-schema unknown key is NOT
/// included), and the stale shadow is reaped from the table.
#[test]
fn merge_payload_with_shadow_drops_shadow_when_cross_type_redirect_tombstone_present() {
    let conn = open_db_in_memory().unwrap();
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "id-merged",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        r#"{"id":"id-merged","loser_schema_only_field":"would-pollute"}"#,
        "device-test",
    )
    .unwrap();
    // Pre-condition: shadow exists.
    assert!(get_shadow(&conn, ENTITY_TASK, "id-merged")
        .unwrap()
        .is_some());

    // Plant a cross-type redirect tombstone directly via SQL —
    // this models the post-merge state without going through the
    // sync crate (which would also call `merge_shadow_into_redirect`
    // and drop the shadow at tombstone creation; here we model
    // the race window where the shadow re-appeared after the
    // tombstone).
    conn.execute(
        "INSERT INTO sync_tombstones \
         (entity_type, entity_id, version, deleted_at, \
          redirect_entity_id, redirect_entity_type) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            ENTITY_TASK,
            "id-merged",
            "1711234568000_0000_a1b2c3d4a1b2c3d4",
            "2026-04-25T00:00:00.000Z",
            "id-merged",
            ENTITY_HABIT, // Different type — cross-type redirect.
        ],
    )
    .unwrap();

    let known = serde_json::json!({
        "id": "id-merged",
        "title": "Live task title",
        "status": "open",
    });
    let merged = merge_payload_with_shadow(&conn, ENTITY_TASK, "id-merged", &known).unwrap();

    // The stale loser-schema unknown key MUST NOT pollute the
    // merged payload.
    assert!(
        merged.get("loser_schema_only_field").is_none(),
        "cross-type redirect detector should have dropped the \
         stale shadow rather than cross-pollinating loser-schema fields"
    );
    // Live known fields are preserved.
    assert_eq!(
        merged.get("title").and_then(Value::as_str),
        Some("Live task title")
    );
    assert_eq!(merged.get("status").and_then(Value::as_str), Some("open"));

    // The stale shadow has been reaped.
    assert!(
        get_shadow(&conn, ENTITY_TASK, "id-merged")
            .unwrap()
            .is_none(),
        "cross-type redirect detector should have removed the stale shadow"
    );
}

/// when the tombstone at the same key redirects
/// WITHIN the same entity type (intra-type merge), the shadow
/// MUST still merge normally — same-type forward-compat keys
/// are schema-compatible with the local re-emit.
#[test]
fn merge_payload_with_shadow_keeps_shadow_when_same_type_redirect_tombstone_present() {
    let conn = open_db_in_memory().unwrap();
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "id-loser",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        r#"{"id":"id-loser","forward_compat_field":"keep"}"#,
        "device-test",
    )
    .unwrap();

    // Same-type redirect (task → task) — semantically a tag-merge
    // / recurrence-dedup pattern that the cross-type detector
    // must NOT trigger on.
    conn.execute(
        "INSERT INTO sync_tombstones \
         (entity_type, entity_id, version, deleted_at, \
          redirect_entity_id, redirect_entity_type) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            ENTITY_TASK,
            "id-loser",
            "1711234568000_0000_a1b2c3d4a1b2c3d4",
            "2026-04-25T00:00:00.000Z",
            "id-winner",
            ENTITY_TASK,
        ],
    )
    .unwrap();

    let known = serde_json::json!({
        "id": "id-loser",
        "title": "Live title",
    });
    let merged = merge_payload_with_shadow(&conn, ENTITY_TASK, "id-loser", &known).unwrap();
    // Same-type forward-compat key survives the merge.
    assert_eq!(
        merged.get("forward_compat_field").and_then(Value::as_str),
        Some("keep"),
        "same-type redirect must NOT trigger the cross-type drop branch"
    );
}

#[test]
fn merge_payload_with_shadow_rejects_malformed_shadow_json() {
    let conn = open_db_in_memory().unwrap();
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-1",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        r#"{"id":"task-1","title":"Broken""#,
        "device-test",
    )
    .unwrap();

    let result = merge_payload_with_shadow(
        &conn,
        ENTITY_TASK,
        "task-1",
        &serde_json::json!({
            "id": "task-1",
            "title": "Known",
            "status": "open",
        }),
    );

    assert!(result.is_err(), "expected malformed shadow json to fail");
}
