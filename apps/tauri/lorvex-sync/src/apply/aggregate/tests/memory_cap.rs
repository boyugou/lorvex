use super::super::apply_memory_upsert;
use super::support::*;
use crate::conflict_log::get_conflicts_by_type;
use lorvex_domain::memory::{MAX_MEMORY_CONTENT_LENGTH, MEMORY_TRUNCATION_SENTINEL};
use serde_json::json;

fn memory_payload(content: &str) -> String {
    json!({
        "key": "k1",
        "content": content,
        "updated_at": "2026-03-23T12:00:00.000Z",
    })
    .to_string()
}

#[test]
fn memory_apply_caps_incoming_content_at_max() {
    let conn = test_db();
    let oversized = "x".repeat(MAX_MEMORY_CONTENT_LENGTH + 50_000);
    let payload = memory_payload(&oversized);

    apply_memory_upsert(
        &conn,
        "k1",
        &payload,
        "1711234567890_0000_aaaaaaaaaaaaaaaa",
        false.into(),
        "device-002",
        "",
    )
    .unwrap();

    let stored: String = conn
        .query_row("SELECT content FROM memories WHERE key='k1'", [], |r| {
            r.get(0)
        })
        .unwrap();

    assert!(
        stored.len() <= MAX_MEMORY_CONTENT_LENGTH,
        "stored length {} must be ≤ cap {}",
        stored.len(),
        MAX_MEMORY_CONTENT_LENGTH
    );
    assert!(
        stored.ends_with(MEMORY_TRUNCATION_SENTINEL.as_str()),
        "truncated content must end with sentinel: {:?}",
        &stored[stored.len().saturating_sub(100)..]
    );
}

#[test]
fn memory_apply_logs_conflict_on_truncation() {
    let conn = test_db();
    let oversized = "A".repeat(MAX_MEMORY_CONTENT_LENGTH + 1);
    let payload = memory_payload(&oversized);

    apply_memory_upsert(
        &conn,
        "k1",
        &payload,
        "1711234567890_0000_aaaaaaaaaaaaaaaa",
        false.into(),
        "device-peer",
        "",
    )
    .unwrap();

    let conflicts = get_conflicts_by_type(&conn, "content_truncated", 10).unwrap();
    assert_eq!(
        conflicts.len(),
        1,
        "expected one content_truncated log entry"
    );
    let entry = &conflicts[0];
    assert_eq!(entry.entity_type, lorvex_domain::naming::ENTITY_MEMORY);
    assert_eq!(entry.entity_id, "k1");
    assert_eq!(entry.loser_device_id, "device-peer");
    let scrubbed = entry.loser_payload.as_deref().unwrap_or("");
    assert!(
        !scrubbed.contains(&"A".repeat(1000)),
        "scrubbed payload must not contain raw content"
    );
    assert!(scrubbed.contains("[REDACTED_PII]"));
}

#[test]
fn memory_apply_under_cap_is_not_truncated_or_logged() {
    let conn = test_db();
    let content = "small content".to_string();
    let payload = memory_payload(&content);

    apply_memory_upsert(
        &conn,
        "k1",
        &payload,
        "1711234567890_0000_aaaaaaaaaaaaaaaa",
        false.into(),
        "device-001",
        "",
    )
    .unwrap();

    let stored: String = conn
        .query_row("SELECT content FROM memories WHERE key='k1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(stored, content);
    assert!(!stored.contains(MEMORY_TRUNCATION_SENTINEL.as_str()));

    let conflicts = get_conflicts_by_type(&conn, "content_truncated", 10).unwrap();
    assert!(
        conflicts.is_empty(),
        "under-cap payload must not log a conflict"
    );
}

#[test]
fn memory_apply_preserves_utf8_char_boundaries_when_truncating() {
    let conn = test_db();
    // Multi-byte character ("中" = 3 bytes). Build content where the
    // naive byte cut would land mid-codepoint.
    let cjk = "中".repeat(MAX_MEMORY_CONTENT_LENGTH); // way oversize
    let payload = memory_payload(&cjk);
    apply_memory_upsert(
        &conn,
        "k1",
        &payload,
        "1711234567890_0000_aaaaaaaaaaaaaaaa",
        false.into(),
        "device-peer",
        "",
    )
    .unwrap();

    let stored: String = conn
        .query_row("SELECT content FROM memories WHERE key='k1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert!(stored.ends_with(MEMORY_TRUNCATION_SENTINEL.as_str()));
}
