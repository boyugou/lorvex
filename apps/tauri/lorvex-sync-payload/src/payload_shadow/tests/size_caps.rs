//! Size-cap enforcement at every writer entry point. Both
//! `upsert_shadow` (sync apply) and `restore_shadow` (import) must
//! reject `raw_payload_json` over `MAX_RAW_PAYLOAD_JSON_BYTES`.

use super::support::*;

/// `restore_shadow` (the import path)
/// MUST enforce the same `MAX_RAW_PAYLOAD_JSON_BYTES` cap as
/// `upsert_shadow`. Pre-fix the cap lived only on `upsert_shadow`,
/// so a malicious or corrupted import archive could ship a single
/// 50 MB `payload_shadows.jsonl` line and pin disk + page-cache
/// memory until horizon GC.
#[test]
fn restore_shadow_rejects_oversize_raw_payload_json() {
    let conn = open_db_in_memory().unwrap();
    let oversize = "x".repeat(MAX_RAW_PAYLOAD_JSON_BYTES + 1);
    let row = PayloadShadowRow {
        entity_type: EntityKind::Task,
        entity_id: "task-bomb".to_string(),
        base_version: "0001000000000_0001_devicea1234567".to_string(),
        payload_schema_version: 1,
        raw_payload_json: oversize,
        source_device_id: "device-import".to_string(),
        updated_at: "2026-04-19T08:00:00.000Z".to_string(),
    };

    let err = restore_shadow(&conn, &row).expect_err("oversize raw_payload_json must be rejected");
    let PayloadError::Validation(message) = err else {
        panic!("expected PayloadError::Validation, got: {err:?}");
    };
    assert!(
        message.contains("exceeds maximum"),
        "expected size-cap diagnostic, got: {message}"
    );
    // No row was written.
    assert!(get_shadow(&conn, ENTITY_TASK, "task-bomb")
        .unwrap()
        .is_none());
}

#[test]
fn upsert_shadow_rejects_oversize_raw_payload_json() {
    let conn = open_db_in_memory().unwrap();
    let oversize = "y".repeat(MAX_RAW_PAYLOAD_JSON_BYTES + 1);

    let err = upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-bomb-up",
        "0001000000000_0001_devicea1234567",
        1,
        &oversize,
        "device-local",
    )
    .expect_err("oversize raw_payload_json must be rejected");
    let PayloadError::Validation(message) = err else {
        panic!("expected PayloadError::Validation, got: {err:?}");
    };
    assert!(
        message.contains("exceeds maximum"),
        "expected size-cap diagnostic, got: {message}"
    );
    assert!(get_shadow(&conn, ENTITY_TASK, "task-bomb-up")
        .unwrap()
        .is_none());
}
