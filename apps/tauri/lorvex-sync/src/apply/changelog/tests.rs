use super::*;
use crate::test_db;
use lorvex_domain::naming::EntityKind;

const VALID_PAYLOAD: &str = r#"{
    "timestamp": "2026-04-19T08:00:00.000Z",
    "operation": "create",
    "entity_type": "task",
    "entity_id": "t-1",
    "summary": "created task",
    "initiated_by": "ai",
    "undo_token": null,
    "is_preview": false
}"#;

/// a payload_schema_version that
/// exceeds local + 1 must be refused at the changelog handler
/// boundary, mirroring the envelope-level
/// `check_envelope_version` gate.
#[test]
fn refuses_payload_schema_version_more_than_one_ahead() {
    let conn = test_db();
    let result = apply_changelog_entry(
        &conn,
        "cl-too-new",
        VALID_PAYLOAD,
        PAYLOAD_SCHEMA_VERSION + 2,
    );
    assert!(
        matches!(result, Err(ApplyError::InvalidPayload(_))),
        "expected InvalidPayload for too-new schema version, got {result:?}"
    );

    // Row was not inserted.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            ["cl-too-new"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        count, 0,
        "row must not be inserted under too-new schema version"
    );
}

/// forward-compat one-version-ahead must be refused at the
/// append-only changelog handler boundary. `ai_changelog` has no
/// version column, so inserting a truncated row cannot be repaired by
/// a later payload-shadow promotion.
#[test]
fn refuses_payload_schema_version_one_ahead_for_append_only_changelog() {
    let conn = test_db();
    let result = apply_changelog_entry(
        &conn,
        "cl-fwd-compat",
        VALID_PAYLOAD,
        PAYLOAD_SCHEMA_VERSION + 1,
    );
    assert!(
        matches!(result, Err(ApplyError::InvalidPayload(_))),
        "expected InvalidPayload for forward-compatible ai_changelog, got {result:?}"
    );

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            ["cl-fwd-compat"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        count, 0,
        "forward-compatible ai_changelog must not insert a truncated row"
    );
}

#[test]
fn apply_envelope_defers_forward_compat_ai_changelog_without_row_or_shadow() {
    let conn = test_db();
    let changelog_id = "01966a3f-7c8b-7d4e-8f3a-000000050001";
    let envelope = crate::envelope::SyncEnvelope {
        entity_type: EntityKind::AiChangelog,
        entity_id: changelog_id.to_string(),
        operation: crate::envelope::SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("0000000000001_0000_a0a0a0a0a0a0a0a0").unwrap(),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION + 1,
        payload: VALID_PAYLOAD.to_string(),
        device_id: "device-peer".to_string(),
    };

    let result = crate::apply::apply_envelope(&conn, &envelope).unwrap();
    assert!(matches!(
        result,
        crate::apply::ApplyResult::Deferred {
            reason: crate::apply::DeferralReason::SchemaTooNew {
                remote_version,
                local_version,
            },
        } if remote_version == PAYLOAD_SCHEMA_VERSION + 1 && local_version == PAYLOAD_SCHEMA_VERSION
    ));

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            [changelog_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        row_count, 0,
        "deferred forward-compatible changelog must not write a truncated audit row"
    );

    let shadow_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_payload_shadow
             WHERE entity_type = ?1 AND entity_id = ?2",
            [EntityKind::AiChangelog.as_str(), changelog_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        shadow_count, 0,
        "deferred changelog must not create a shadow that could later clear unknown fields"
    );
}

/// an older or current payload_schema_version
/// applies normally.
#[test]
fn accepts_current_payload_schema_version() {
    let conn = test_db();
    apply_changelog_entry(&conn, "cl-current", VALID_PAYLOAD, PAYLOAD_SCHEMA_VERSION)
        .expect("current schema version must apply");

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            ["cl-current"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

/// Round-trip pins the cross-crate-audit fix: the `is_preview`
/// and `undo_token` columns must propagate through the sync
/// envelope. Pre-fix the apply INSERT bound only the original
/// 12 columns and silently fell back to schema defaults
/// (`is_preview = 0`, `undo_token = NULL`), so a peer's preview
/// row landed locally as a real audit entry — visible in the
/// user's changelog as if the dry-run had committed.
#[test]
fn round_trips_is_preview_and_undo_token_columns() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-04-19T08:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "t-preview",
        "summary": "preview create",
        "initiated_by": "ai",
        "is_preview": true,
        "undo_token": "tok-abc"
    }"#;
    apply_changelog_entry(&conn, "cl-preview", payload, PAYLOAD_SCHEMA_VERSION)
        .expect("apply preview row");

    let (is_preview, undo_token): (i64, Option<String>) = conn
        .query_row(
            "SELECT is_preview, undo_token FROM ai_changelog WHERE id = ?1",
            ["cl-preview"],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .expect("read row back");
    assert_eq!(is_preview, 1, "is_preview must round-trip from envelope");
    assert_eq!(
        undo_token.as_deref(),
        Some("tok-abc"),
        "undo_token must round-trip from envelope",
    );
}

/// A payload with an `is_preview` field that isn't a bool or
/// null is rejected at the trust boundary so a malformed peer
/// can't poison the discriminator.
#[test]
fn rejects_non_bool_is_preview_field() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-04-19T08:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "t-bad",
        "summary": "bad preview",
        "initiated_by": "ai",
        "undo_token": null,
        "is_preview": "yes"
    }"#;
    let err = apply_changelog_entry(&conn, "cl-bad", payload, PAYLOAD_SCHEMA_VERSION)
        .expect_err("non-bool is_preview must be rejected");
    match err {
        ApplyError::InvalidPayload(message) => {
            assert!(
                message.contains("is_preview"),
                "error must mention the offending field: {message}"
            );
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

/// Current builders must emit the nullable `undo_token`
/// field explicitly. An omitted field means the payload did not come
/// from the current contract and must fail at the apply boundary
/// instead of silently defaulting.
#[test]
fn rejects_payload_missing_undo_token() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-04-19T08:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "t-missing-undo",
        "summary": "missing undo",
        "initiated_by": "ai",
        "is_preview": false
    }"#;
    let err = apply_changelog_entry(&conn, "cl-missing-undo", payload, PAYLOAD_SCHEMA_VERSION)
        .expect_err("missing undo_token must be rejected");
    match err {
        ApplyError::InvalidPayload(message) => {
            assert!(
                message.contains("undo_token"),
                "error must mention the missing field: {message}"
            );
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

/// `is_preview` is a non-nullable bool in the current wire shape.
/// Missing or null should not be treated as the schema default.
#[test]
fn rejects_payload_missing_is_preview() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-04-19T08:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "t-missing-preview",
        "summary": "missing preview",
        "initiated_by": "ai",
        "undo_token": null
    }"#;
    let err = apply_changelog_entry(&conn, "cl-missing-preview", payload, PAYLOAD_SCHEMA_VERSION)
        .expect_err("missing is_preview must be rejected");
    match err {
        ApplyError::InvalidPayload(message) => {
            assert!(
                message.contains("is_preview"),
                "error must mention the missing field: {message}"
            );
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn rejects_null_is_preview() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-04-19T08:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "t-null-preview",
        "summary": "null preview",
        "initiated_by": "ai",
        "undo_token": null,
        "is_preview": null
    }"#;
    let err = apply_changelog_entry(&conn, "cl-null-preview", payload, PAYLOAD_SCHEMA_VERSION)
        .expect_err("null is_preview must be rejected");
    match err {
        ApplyError::InvalidPayload(message) => {
            assert!(
                message.contains("is_preview"),
                "error must mention the offending field: {message}"
            );
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn accepts_current_payload_with_null_undo_token_and_false_preview() {
    let conn = test_db();
    apply_changelog_entry(
        &conn,
        "cl-current-shape",
        VALID_PAYLOAD,
        PAYLOAD_SCHEMA_VERSION,
    )
    .expect("current payload must apply");

    let (is_preview, undo_token): (i64, Option<String>) = conn
        .query_row(
            "SELECT is_preview, undo_token FROM ai_changelog WHERE id = ?1",
            ["cl-current-shape"],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .expect("read row back");
    assert_eq!(is_preview, 0);
    assert!(undo_token.is_none());
}
