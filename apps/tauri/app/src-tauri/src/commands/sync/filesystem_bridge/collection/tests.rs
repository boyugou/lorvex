use super::*;

use crate::test_support::test_conn;
use lorvex_sync::envelope::SyncOperation;

fn hlc_from_rfc3339(ts: &str) -> String {
    let ms = chrono::DateTime::parse_from_rfc3339(ts)
        .expect("parse RFC3339 timestamp")
        .timestamp_millis();
    format!("{ms:013}_0000_6465766963656162")
}

#[test]
fn parse_sync_file_result_rejects_malformed_json() {
    let error = parse_sync_file_result("{not-valid-json", "event-1")
        .expect_err("malformed sync JSON should be rejected explicitly");
    let rendered = error.to_string();
    assert!(
        rendered.contains("Failed to parse filesystem bridge sync envelope"),
        "unexpected parse error: {rendered}"
    );
}

#[test]
fn parse_sync_file_result_rejects_empty_event_id() {
    let raw = serde_json::json!({
        "entity_type": "task",
        "entity_id": "task-1",
        "operation": "upsert",
        "payload_schema_version": 1,
        "payload": "{}",
        "version": "0001743573600000_0001_f115b71d6efa11ed",
        "device_id": "device-remote",
    })
    .to_string();

    let error = parse_sync_file_result(&raw, "")
        .expect_err("empty file stem should be rejected explicitly");
    let rendered = error.to_string();
    assert!(
        rendered.contains("event id"),
        "unexpected parse error: {rendered}"
    );
}

#[test]
fn parse_sync_file_result_rejects_non_hlc_version() {
    let raw = serde_json::json!({
        "entity_type": "task",
        "entity_id": "task-1",
        "operation": "upsert",
        "payload_schema_version": 1,
        "payload": "{}",
        "version": "not-a-valid-hlc",
        "device_id": "device-remote",
    })
    .to_string();

    let error = parse_sync_file_result(&raw, "event-1")
        .expect_err("non-HLC version should be rejected explicitly");
    // serde now rejects unparseable HLCs at
    // deserialize time (the typed `version: Hlc` field), so the
    // surfaced error is the `HlcParseError::InvalidFormat` chain
    // rather than the previous post-parse "valid HLC version"
    // string. Assert on the underlying `HlcParseError` Display
    // form so the rejection-path coverage stays meaningful.
    let rendered = error.to_string();
    assert!(
        rendered.contains("invalid HLC format") && rendered.contains("not-a-valid-hlc"),
        "unexpected parse error: {rendered}"
    );
}

#[test]
fn parse_sync_file_result_rejects_unknown_operation() {
    let raw = serde_json::json!({
        "entity_type": "task",
        "entity_id": "task-1",
        "operation": "merge",
        "payload_schema_version": 1,
        "payload": "{}",
        "version": "0001743573600000_0001_f115b71d6efa11ed",
        "device_id": "device-remote",
    })
    .to_string();

    let error = parse_sync_file_result(&raw, "event-1")
        .expect_err("unknown operation should be rejected explicitly");
    let rendered = error.to_string();
    assert!(
        rendered.contains("operation") && rendered.contains("merge"),
        "unexpected parse error: {rendered}"
    );
}

#[test]
fn load_recent_lookback_outbox_ids_uses_hlc_cursor_timestamp() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
         ) VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, NULL, 0)",
        rusqlite::params![
            "task",
            "task-recent",
            "upsert",
            hlc_from_rfc3339("2026-03-02T11:30:00Z"),
            "{}",
            "device-remote",
            "2026-03-01T12:00:00Z",
        ],
    )
    .expect("insert recent outbox row");
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
         ) VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, NULL, 0)",
        rusqlite::params![
            "task",
            "task-old",
            "upsert",
            hlc_from_rfc3339("2026-03-01T10:00:00Z"),
            "{}",
            "device-remote",
            "2026-03-01T10:00:00Z",
        ],
    )
    .expect("insert old outbox row");

    let cursor = FilesystemBridgePullCursor {
        updated_at: hlc_from_rfc3339("2026-03-02T11:00:00Z"),
        device_id: "device-cursor".to_string(),
        event_id: "evt-cursor".to_string(),
    };

    let ids = load_recent_lookback_outbox_ids(&conn, Some(&cursor))
        .expect("load recent lookback ids from HLC cursor");

    assert_eq!(ids.len(), 1);
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_stops_before_aggregate_byte_cap() {
    let temp =
        std::env::temp_dir().join(format!("lorvex-fs-aggregate-cap-{}", uuid::Uuid::now_v7()));
    fs::create_dir_all(&temp).expect("create temp sync dir");

    let large_body = "x".repeat(900_000);
    let mut expected_ids = Vec::new();
    let mut aggregate_bytes = 0_u64;
    let total_files = 80;

    for idx in 0..total_files {
        let file_id = format!("event-{idx:03}");
        let envelope = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::Task,
            entity_id: format!("01966a3f-7c8b-7d4e-8f3a-0000000{idx:05}"),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse(&format!(
                "0001743573600{idx:03}_0000_6465766963656162"
            ))
            .expect("test fixture HLC"),
            payload_schema_version: 1,
            payload: serde_json::json!({
                "id": format!("01966a3f-7c8b-7d4e-8f3a-0000000{idx:05}"),
                "title": format!("Huge payload {idx:03}"),
                "status": "open",
                "body": large_body,
            })
            .to_string(),
            device_id: "device-remote".to_string(),
        };
        let raw = serde_json::to_string(&envelope).expect("serialize large envelope");
        let raw_len = raw.len() as u64;
        assert!(
            raw_len <= MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES,
            "fixture must stay under per-envelope cap: {raw_len}"
        );
        if aggregate_bytes.saturating_add(raw_len) <= MAX_FILESYSTEM_BRIDGE_AGGREGATE_BYTES {
            expected_ids.push(file_id.clone());
            aggregate_bytes = aggregate_bytes.saturating_add(raw_len);
        }
        fs::write(temp.join(format!("{file_id}.json")), raw).expect("write sync file");
    }

    let collected =
        collect_remote_filesystem_bridge_envelopes(&temp, "device-local", total_files, None, None)
            .expect("collect envelopes under aggregate cap");

    let actual_ids: Vec<String> = collected
        .remote_events
        .iter()
        .map(|record| record.id.clone())
        .collect();

    assert_eq!(
        actual_ids, expected_ids,
        "collector should stop before exceeding aggregate byte cap and keep the oldest-sorted prefix"
    );
    assert_eq!(
        collected.pulled_files,
        i64::try_from(expected_ids.len() + 1).expect("convert pulled file count"),
        "collector should count the first file that crosses the aggregate budget, then stop"
    );
    assert_eq!(collected.pull_parse_errors, 0);
    assert!(!collected.pull_limit_hit);
    assert!(
        collected.diagnostics.iter().any(|diagnostic| {
            diagnostic.source == "sync.filesystem_bridge.pull.aggregate_cap"
                && diagnostic.level == "warn"
                && diagnostic
                    .details
                    .as_deref()
                    .unwrap_or("")
                    .contains("max_aggregate_bytes")
        }),
        "aggregate cap should be returned as a persisted diagnostic candidate"
    );
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_returns_parse_diagnostics() {
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-parse-diagnostic-{}",
        uuid::Uuid::now_v7()
    ));
    fs::create_dir_all(&temp).expect("create temp sync dir");
    fs::write(temp.join("event-bad.json"), "{not-valid-json").expect("write bad sync file");

    let collected =
        collect_remote_filesystem_bridge_envelopes(&temp, "device-local", 10, None, None)
            .expect("collect envelopes with bad remote file");

    assert_eq!(collected.pulled_files, 1);
    assert_eq!(collected.pull_parse_errors, 1);
    assert_eq!(collected.remote_events.len(), 0);
    assert!(
        collected.diagnostics.iter().any(|diagnostic| {
            diagnostic.source == "sync.filesystem_bridge.pull.parse_error"
                && diagnostic.message == "Filesystem bridge pull failed to parse envelope"
                && diagnostic.level == "warn"
                && diagnostic
                    .details
                    .as_deref()
                    .unwrap_or("")
                    .contains("event-bad.json")
        }),
        "parse failure should be returned as a persisted diagnostic candidate"
    );
}
