use crate::error::{AppError, AppResult};

/// Record the highest actually-applied envelope version for each remote device.
///
/// the `ver > *entry` comparison is an ASCII byte-
/// compare on the canonical HLC wire form. That is correct in
/// production because the prefilter pass in
/// `apply_remote_sync_records_with_checkpoint_writer` parses every incoming
/// envelope's `version` through
/// `Hlc::parse` and shunts malformed records into `error_logs`
/// before they reach this site. Under that invariant, ASCII lex
/// order on the wire form matches typed `Hlc::cmp` byte-for-byte
/// (canonical HLCs are fixed-width, zero-padded, lowercase-hex
/// device suffix).
///
/// `IncomingSyncRecord` carries typed `Hlc` versions, and the fixture
/// builders synthesize canonical fixed-width values. Materializing each
/// HLC with `to_string()` is therefore enough to make lexical max match
/// HLC max for per-device cursor persistence.
pub(super) fn record_device_cursors_from_applied_records(
    conn: &rusqlite::Connection,
    records: &[super::IncomingSyncRecord],
    synced_ts: &str,
) -> AppResult<()> {
    // typed `version: Hlc` at the wire boundary.
    // Materialize the canonical string view per record once into a
    // parallel buffer so the borrow-by-`&str` HashMap below stays
    // valid for the loop's lifetime; the tombstone helper still
    // accepts `&str`.
    let version_strings: Vec<String> = records
        .iter()
        .map(|r| r.envelope.version.to_string())
        .collect();
    let mut device_max: std::collections::HashMap<&str, &str> = std::collections::HashMap::new();
    for (r, ver_str) in records.iter().zip(version_strings.iter()) {
        let did = r.envelope.device_id.as_str();
        let ver = ver_str.as_str();
        let entry = device_max.entry(did).or_insert(ver);
        if ver > *entry {
            *entry = ver;
        }
    }
    for (device_id, max_version) in device_max {
        lorvex_sync::tombstone::upsert_device_cursor_with_version(
            conn,
            device_id,
            synced_ts,
            Some(max_version),
        )
        .map_err(AppError::from)?;
    }
    Ok(())
}

pub(super) fn record_seen_remote_device_cursors(
    conn: &rusqlite::Connection,
    records: &[super::IncomingSyncRecord],
    synced_ts: &str,
) -> AppResult<()> {
    let mut seen_devices: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for record in records {
        let device_id = record.envelope.device_id.as_str();
        if device_id.trim().is_empty()
            || device_id.len() > lorvex_sync::envelope::MAX_ENVELOPE_DEVICE_ID_LEN
        {
            continue;
        }
        seen_devices.insert(device_id);
    }

    for device_id in seen_devices {
        lorvex_sync::tombstone::upsert_device_cursor_with_version(conn, device_id, synced_ts, None)
            .map_err(AppError::from)?;
    }
    Ok(())
}
