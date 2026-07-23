//! Sync-apply boundary numeric validation tests.
//!
//! Pre-fix the apply path only rejected `m < 0` for
//! `estimated_minutes`, while every local writer (MCP, Tauri, CLI)
//! routed that field through
//! `lorvex_domain::validation::validate_estimated_minutes`, which
//! enforces a tighter `1..=MAX_ESTIMATED_MINUTES`. A peer envelope with
//! `estimated_minutes = 0` therefore round-tripped into the local DB
//! and the scheduler interpreted `Some(0)` as "scheduled but takes no
//! time" — an invariant violation. These tests pin the corrected
//! behavior: the apply boundary now uses the domain validators.

use super::super::apply_task_upsert;
use super::support::*;
use crate::apply::ApplyError;
use serde_json::json;

fn task_payload(list_id: &str, extra: &serde_json::Value) -> String {
    let mut payload = json!({
        "title": "Numeric guard test",
        "status": "open",
        "list_id": list_id,
        "defer_count": 0,
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z",
    });
    if let (Some(map), Some(extras)) = (payload.as_object_mut(), extra.as_object()) {
        for (k, v) in extras {
            map.insert(k.clone(), v.clone());
        }
    }
    payload.to_string()
}

#[test]
fn apply_rejects_estimated_minutes_zero() {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let payload = task_payload(list_id, &json!({ "estimated_minutes": 0 }));
    let err = apply_task_upsert(
        &conn,
        "task-numeric-est-zero",
        &payload,
        &next_version(),
        false.into(),
        "",
    )
    .expect_err("estimated_minutes=0 must be rejected at apply time");
    match err {
        ApplyError::InvalidPayload(msg) => {
            assert!(
                msg.contains("estimated_minutes"),
                "error must mention the field, got: {msg}"
            );
        }
        other => panic!("expected InvalidPayload for estimated_minutes=0, got {other:?}"),
    }
}

#[test]
fn apply_rejects_estimated_minutes_negative() {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let payload = task_payload(list_id, &json!({ "estimated_minutes": -5 }));
    let err = apply_task_upsert(
        &conn,
        "task-numeric-est-neg",
        &payload,
        &next_version(),
        false.into(),
        "",
    )
    .expect_err("negative estimated_minutes must be rejected");
    assert!(matches!(err, ApplyError::InvalidPayload(_)));
}

#[test]
fn apply_rejects_estimated_minutes_above_ceiling() {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    // MAX_ESTIMATED_MINUTES is 1440 (one day's worth). A peer sending
    // 100_000 minutes is malformed and must fail the apply boundary
    // even though the previous `m < 0` check accepted it.
    let payload = task_payload(list_id, &json!({ "estimated_minutes": 100_000 }));
    let err = apply_task_upsert(
        &conn,
        "task-numeric-est-over",
        &payload,
        &next_version(),
        false.into(),
        "",
    )
    .expect_err("estimated_minutes past MAX_ESTIMATED_MINUTES must be rejected");
    match err {
        ApplyError::InvalidPayload(msg) => assert!(msg.contains("estimated_minutes")),
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn apply_accepts_estimated_minutes_at_minimum() {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let payload = task_payload(list_id, &json!({ "estimated_minutes": 1 }));
    apply_task_upsert(
        &conn,
        "task-numeric-est-min",
        &payload,
        &next_version(),
        false.into(),
        "",
    )
    .expect("estimated_minutes=1 must apply cleanly");
}

#[test]
fn apply_accepts_estimated_minutes_at_ceiling() {
    let conn = test_db();
    let list_id = lorvex_store::INBOX_LIST_ID;
    seed_list(&conn, list_id);

    let payload = task_payload(list_id, &json!({ "estimated_minutes": 1440 }));
    apply_task_upsert(
        &conn,
        "task-numeric-est-cap",
        &payload,
        &next_version(),
        false.into(),
        "",
    )
    .expect("estimated_minutes at MAX_ESTIMATED_MINUTES must apply cleanly");
}
