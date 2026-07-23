pub(super) use super::*;

mod core;
mod filesystem_bridge;
mod remote_apply;
mod status;
mod timestamp_format;

/// Build an HLC version from an RFC3339 timestamp and device_id for test use.
///
/// If `version_or_ts` already contains `_` (HLC format), it is returned as-is.
/// Otherwise, the timestamp is converted to milliseconds and formatted as an
/// HLC string: `{ms:013}_{counter:04}_{suffix}` where `suffix` is a strict
/// 16-character lowercase-hex device-suffix derived deterministically from
/// `device_id`.
///
/// `Hlc::parse` now enforces the 16-hex device-suffix
/// invariant on every parse (see `validate_device_suffix`, issue
/// #2973-H5). The legacy implementation took the first 8 alphanumeric
/// chars of `device_id` as the suffix verbatim — for device ids like
/// `"device-a"` the resulting `devicea` carries non-hex characters
/// (`v`, `i`) and is shorter than the canonical 16-char width, so
/// every fixture-built HLC silently failed to round-trip through
/// `Hlc::parse` once the strict validator landed. We now hex-encode
/// `device_id` byte-by-byte (preserving the lex ordering of distinct
/// device ids — `device-a` < `device-z` round-trips byte-wise to
/// `…61` < `…7a`), then truncate or right-pad to exactly 16 chars.
fn make_hlc_version(version_or_ts: &str, device_id: &str) -> lorvex_domain::hlc::Hlc {
    // `IncomingSyncRecord` carries a typed `Hlc`, so malformed version
    // fixtures must be built at the serialized transport boundary rather
    // than hidden behind a placeholder HLC here.
    if version_or_ts.contains('_') {
        return lorvex_domain::hlc::Hlc::parse(version_or_ts)
            .expect("test fixture HLC must be canonical");
    }
    if let Ok(ts) = chrono::DateTime::parse_from_rfc3339(version_or_ts) {
        let ms = ts.timestamp_millis() as u64;
        let s = format!("{:013}_{:04}_{}", ms, 0, hex_device_suffix(device_id));
        return lorvex_domain::hlc::Hlc::parse(&s).expect("synthesized HLC must parse");
    }
    panic!("test fixture version must be a canonical HLC or RFC3339 timestamp: {version_or_ts:?}");
}

/// Hex-encode `device_id` and normalize to exactly
/// `HLC_DEVICE_SUFFIX_HEX_LEN` (16) lowercase hex characters so the
/// resulting suffix passes `validate_device_suffix`. Empty input
/// degenerates to all-zero, matching the parser's strict-shape but
/// falsy-content contract.
fn hex_device_suffix(device_id: &str) -> String {
    const TARGET_LEN: usize = 16;
    let mut hex = String::with_capacity(TARGET_LEN);
    for byte in device_id.bytes() {
        hex.push_str(&format!("{byte:02x}"));
        if hex.len() >= TARGET_LEN {
            break;
        }
    }
    while hex.len() < TARGET_LEN {
        hex.push('0');
    }
    hex.truncate(TARGET_LEN);
    hex
}

fn make_sync_event(
    id: &str,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: serde_json::Value,
    version_or_ts: &str,
    device_id: &str,
) -> IncomingSyncRecord {
    use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};
    let op = match operation {
        "delete" => SyncOperation::Delete,
        _ => SyncOperation::Upsert,
    };
    let version = make_hlc_version(version_or_ts, device_id);
    let payload =
        canonicalize_sync_test_payload(entity_type, entity_id, operation, payload, version_or_ts);
    IncomingSyncRecord {
        id: id.to_string(),
        envelope: SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
                .expect("test entity_type must be a known EntityKind"),
            entity_id: entity_id.to_string(),
            operation: op,
            version,
            payload_schema_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            payload: payload.to_string(),
            device_id: device_id.to_string(),
        },
    }
}

fn ensure_str_field(map: &mut serde_json::Map<String, serde_json::Value>, key: &str, value: &str) {
    map.entry(key.to_string())
        .or_insert_with(|| serde_json::Value::String(value.to_string()));
}

fn ensure_i64_field(map: &mut serde_json::Map<String, serde_json::Value>, key: &str, value: i64) {
    map.entry(key.to_string())
        .or_insert_with(|| serde_json::Value::Number(value.into()));
}

fn canonicalize_sync_test_payload(
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: serde_json::Value,
    version_or_ts: &str,
) -> serde_json::Value {
    if operation == "delete" {
        return payload;
    }

    let serde_json::Value::Object(mut map) = payload else {
        return payload;
    };

    match entity_type {
        "task" => {
            ensure_str_field(&mut map, "id", entity_id);
            ensure_str_field(&mut map, "title", "Task");
            ensure_str_field(&mut map, "status", "open");
            ensure_str_field(&mut map, "created_at", version_or_ts);
            ensure_str_field(&mut map, "updated_at", version_or_ts);
            ensure_i64_field(&mut map, "defer_count", 0);
        }
        "list" => {
            ensure_str_field(&mut map, "id", entity_id);
            ensure_str_field(&mut map, "name", "List");
            ensure_str_field(&mut map, "created_at", version_or_ts);
            ensure_str_field(&mut map, "updated_at", version_or_ts);
        }
        "calendar_event" => {
            ensure_str_field(&mut map, "id", entity_id);
            ensure_str_field(&mut map, "title", "Event");
            ensure_str_field(&mut map, "start_date", "2026-01-01");
            ensure_i64_field(&mut map, "all_day", 0);
            ensure_str_field(&mut map, "event_type", "event");
            ensure_str_field(&mut map, "created_at", version_or_ts);
            ensure_str_field(&mut map, "updated_at", version_or_ts);
        }
        "task_dependency" => {
            ensure_str_field(&mut map, "created_at", version_or_ts);
        }
        "task_tag" => {
            ensure_str_field(&mut map, "created_at", version_or_ts);
        }
        "task_calendar_event_link" => {
            ensure_str_field(&mut map, "created_at", version_or_ts);
            ensure_str_field(&mut map, "updated_at", version_or_ts);
        }
        _ => {}
    }

    serde_json::Value::Object(map)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
#[allow(clippy::too_many_arguments)]
/// Write a SyncEnvelope-format JSON file for filesystem bridge collection tests.
/// The file is named `{event_id}.json` so that `parse_sync_file` sets the
/// resulting `IncomingSyncRecord.id` to `event_id` (from the file stem).
/// `version` maps to `IncomingSyncRecord.updated_at`.
///
/// `entity_type` is serialized verbatim so tests can exercise the
/// unknown-entity-type rejection path of `parse_sync_file` by passing
/// values like `"unsupported"`. Going through the typed `EntityKind`
/// would panic at fixture-write time before the collector got a chance
/// to reject it.
fn write_sync_envelope_file(
    dir: &std::path::Path,
    event_id: &str,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: serde_json::Value,
    version_or_ts: &str,
    device_id: &str,
) {
    // Write the version string verbatim so tests can exercise the
    // file collector's malformed-HLC rejection path by passing strings
    // like `"not-a-valid-hlc"`. Going through `make_hlc_version` would
    // fall back to a canonical placeholder and silently bypass the
    // rejection branch that the test wants to count.
    let version_string = if version_or_ts.contains('_') {
        version_or_ts.to_string()
    } else if let Ok(ts) = chrono::DateTime::parse_from_rfc3339(version_or_ts) {
        let ms = ts.timestamp_millis() as u64;
        format!("{:013}_{:04}_{}", ms, 0, hex_device_suffix(device_id))
    } else {
        version_or_ts.to_string()
    };
    let envelope = serde_json::json!({
        "entity_type": entity_type,
        "entity_id": entity_id,
        "operation": operation,
        "version": version_string,
        "payload_schema_version": 1,
        "payload": payload.to_string(),
        "device_id": device_id,
    });
    let serialized = serde_json::to_string_pretty(&envelope).expect("serialize SyncEnvelope");
    fs::write(dir.join(format!("{event_id}.json")), serialized).expect("write SyncEnvelope file");
}
#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
#[allow(clippy::too_many_arguments)]
fn insert_sync_event_row(
    conn: &Connection,
    _id: &str,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: serde_json::Value,
    version_or_ts: &str,
    device_id: &str,
    synced_at: Option<&str>,
) {
    // Extract version from payload if available, else convert the timestamp to HLC.
    // this column is the `sync_outbox.version` TEXT
    // storage cell — keep it as a String. Render the typed
    // `make_hlc_version` helper through `Display` for the fallback
    // path.
    let version = payload.get("version").and_then(|v| v.as_str()).map_or_else(
        || make_hlc_version(version_or_ts, device_id).to_string(),
        std::string::ToString::to_string,
    );
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
         ) VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, ?8, 0)",
        params![
            entity_type,
            entity_id,
            operation,
            version,
            payload.to_string(),
            device_id,
            version_or_ts,
            synced_at
        ],
    )
    .expect("insert sync outbox row");
}
fn task_title(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT title FROM tasks WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )
    .optional()
    .expect("query task title")
}
fn task_status(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT status FROM tasks WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )
    .optional()
    .expect("query task status")
}
fn task_snapshot(conn: &Connection) -> Vec<(String, String, String, Option<String>)> {
    let mut stmt = conn
        .prepare("SELECT id, title, status, list_id FROM tasks ORDER BY id ASC")
        .expect("prepare task snapshot query");
    stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, Option<String>>(3)?,
        ))
    })
    .expect("query task snapshot")
    .collect::<rusqlite::Result<Vec<_>>>()
    .expect("collect task snapshot")
}
