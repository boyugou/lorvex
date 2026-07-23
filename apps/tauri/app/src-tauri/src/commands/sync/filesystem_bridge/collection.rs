use super::cursor::FilesystemBridgePullCursor;
use super::diagnostics::FilesystemBridgeDiagnostic;
use super::{
    compare_sync_versions_with_outbox_id, fs, is_supported_incoming_record, params, HashSet,
    IncomingSyncRecord, Path, PathBuf, FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER,
    FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS,
};
use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{OP_DELETE, OP_UPSERT};
use lorvex_sync::envelope::SyncEnvelope;

/// Extract the millisecond physical timestamp from an HLC version string.
///
/// HLC format: `{ms:013}_{counter:04}_{suffix}`. Returns `None` for
/// non-HLC strings.
fn hlc_millis(version: &str) -> Option<i64> {
    let ms_part = version.split('_').next()?;
    ms_part.parse::<i64>().ok()
}

fn within_filesystem_bridge_cursor_lookback(event_version: &str, cursor_updated_at: &str) -> bool {
    match (hlc_millis(event_version), hlc_millis(cursor_updated_at)) {
        (Some(event_ms), Some(cursor_ms)) => {
            let floor_ms = cursor_ms - FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS * 1000;
            event_ms >= floor_ms
        }
        (_, None) => true,
        (None, Some(_)) => event_version >= cursor_updated_at,
    }
}

#[derive(Debug, Clone, super::Serialize, super::Deserialize)]
pub(crate) struct CollectedRemoteFilesystemBridgeEnvelopes {
    pub(crate) pulled_files: i64,
    pub(crate) pull_parse_errors: i64,
    pub(crate) cursor_blocking_parse_errors: i64,
    pub(crate) lookback_known_id_skipped: i64,
    pub(crate) pull_limit_hit: bool,
    pub(crate) diagnostics: Vec<FilesystemBridgeDiagnostic>,
    pub(crate) remote_events: Vec<IncomingSyncRecord>,
}

/// Hard cap on an individual filesystem-bridge envelope file.
///
/// The sync folder is shared across devices via Dropbox/Syncthing / Dropbox /
/// SMB — treat every file as attacker-controlled. Without a size cap a
/// 10 GB blob would OOM the app on every pull attempt and persist the
/// crash loop forever. The canonical envelope payload + metadata fits
/// comfortably inside 2 MiB (large task bodies + notes + reminders);
/// anything bigger is rejected with a parse-error counter bump so the
/// caller still advances its cursor and surfaces the issue in sync
/// status.
pub(crate) const MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES: u64 = 2 * 1024 * 1024;

/// Hard cap on directory entries enumerated per pull pass.
///
/// An attacker with write access to the shared sync folder could drop
/// 1 M tiny JSON files and stall sync indefinitely on the sort + per-
/// file parse loop. Cap enumeration and let the caller process the
/// oldest-sorted cap-many entries; the rest get rejected next cycle
/// after some entries are GC'd.
const MAX_FILESYSTEM_BRIDGE_PULL_ENTRIES: usize = 10_000;

/// hard cap on AGGREGATE in-memory envelope bytes for a
/// single pull pass. The per-envelope cap (2 MiB) × the per-enumeration
/// cap (10 K) is a theoretical 20 GiB resident before sort +
/// truncation. This aggregate cap forces the read loop to break early
/// once the accumulated pre-truncate heap exceeds a sane budget.
/// 64 MiB comfortably covers normal steady-state pulls (a few MB at
/// most) while refusing to service a pathological flood.
pub(crate) const MAX_FILESYSTEM_BRIDGE_AGGREGATE_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
enum SyncFileParseError {
    EmptyEventId,
    MalformedEnvelope(String),
    UnknownOperation { raw: String },
    EnvelopeValidation(String),
}

impl SyncFileParseError {
    const fn blocks_pull_cursor(&self) -> bool {
        matches!(self, Self::UnknownOperation { .. })
    }
}

impl std::fmt::Display for SyncFileParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyEventId => {
                write!(
                    f,
                    "filesystem bridge sync file must have a non-empty event id"
                )
            }
            Self::MalformedEnvelope(error) => {
                write!(
                    f,
                    "Failed to parse filesystem bridge sync envelope: {error}"
                )
            }
            Self::UnknownOperation { raw } => {
                write!(
                    f,
                    "filesystem bridge sync envelope has unknown operation: {raw:?}"
                )
            }
            Self::EnvelopeValidation(error) => {
                write!(
                    f,
                    "filesystem bridge sync envelope failed validation: {error}"
                )
            }
        }
    }
}

impl std::error::Error for SyncFileParseError {}

fn parse_sync_file_result(
    raw: &str,
    file_stem: &str,
) -> Result<IncomingSyncRecord, SyncFileParseError> {
    if file_stem.trim().is_empty() {
        return Err(SyncFileParseError::EmptyEventId);
    }

    let value = serde_json::from_str::<serde_json::Value>(raw)
        .map_err(|error| SyncFileParseError::MalformedEnvelope(error.to_string()))?;
    if let Some(operation) = value.get("operation").and_then(serde_json::Value::as_str) {
        match operation {
            OP_DELETE | OP_UPSERT => {}
            other => {
                return Err(SyncFileParseError::UnknownOperation {
                    raw: other.to_string(),
                });
            }
        }
    }

    let envelope = serde_json::from_value::<SyncEnvelope>(value)
        .map_err(|error| SyncFileParseError::MalformedEnvelope(error.to_string()))?;
    // Reject oversized/empty fields before any downstream processing
    // (apply pipeline, HLC parse). This is the transport boundary and
    // any file in the sync folder must be treated as attacker-
    // controlled.
    envelope
        .validate()
        .map_err(|error| SyncFileParseError::EnvelopeValidation(error.to_string()))?;
    // typed `version: Hlc` at the wire boundary, so the
    // post-deserialize `typed_version()` reparse is gone — serde
    // already rejected unparseable versions during deserialization.
    Ok(IncomingSyncRecord {
        id: file_stem.to_string(),
        envelope,
    })
}

pub(crate) fn collect_remote_filesystem_bridge_envelopes(
    sync_dir: &Path,
    local_device_id: &str,
    pull_cap: usize,
    since: Option<&FilesystemBridgePullCursor>,
    known_lookback_event_ids: Option<&HashSet<String>>,
) -> AppResult<CollectedRemoteFilesystemBridgeEnvelopes> {
    let mut json_paths: Vec<PathBuf> = Vec::new();
    let mut enumerated_json_files = 0_usize;
    let mut enumeration_cap_hit = false;
    for entry in fs::read_dir(sync_dir).map_err(|e| {
        AppError::Internal(format!(
            "Failed to read sync directory {}: {e}",
            sync_dir.display()
        ))
    })? {
        let entry = entry
            .map_err(|e| AppError::Internal(format!("Failed to read sync directory entry: {e}")))?;
        let file_type = entry.file_type().map_err(|e| {
            AppError::Internal(format!("Failed to inspect sync directory entry type: {e}"))
        })?;
        if !file_type.is_file() {
            continue;
        }
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        enumerated_json_files += 1;
        if enumerated_json_files > MAX_FILESYSTEM_BRIDGE_PULL_ENTRIES {
            enumeration_cap_hit = true;
            break;
        }
        json_paths.push(path);
    }

    json_paths.sort();
    let mut diagnostics = Vec::new();
    if enumeration_cap_hit {
        diagnostics.push(FilesystemBridgeDiagnostic::warn(
            "sync.filesystem_bridge.pull.enumeration_cap",
            "Filesystem bridge pull directory entry cap hit",
            format!(
                "enumerated_json_files={enumerated_json_files}, max_entries={MAX_FILESYSTEM_BRIDGE_PULL_ENTRIES}"
            ),
        ));
    }

    let mut pulled_files = 0_i64;
    let mut pull_parse_errors = 0_i64;
    let mut cursor_blocking_parse_errors = 0_i64;
    let mut lookback_known_id_skipped = 0_i64;
    let mut remote_events: Vec<IncomingSyncRecord> = Vec::new();
    let mut lookback_events: Vec<IncomingSyncRecord> = Vec::new();
    // track aggregate bytes read so a pathological flood
    // of near-cap files can't accumulate into multi-GiB resident
    // memory before the post-loop truncate runs.
    let mut aggregate_bytes_read: u64 = 0;

    for path in json_paths {
        // cancel-signal probe at the head of every
        // envelope iteration. A slow shared-folder pull can run for
        // tens of seconds; the user's "Cancel" must take effect
        // before the next file IO begins.
        if crate::commands::sync::runtime::is_sync_cancelled_for(
            crate::commands::sync::runtime::SyncKind::FilesystemBridge,
        ) {
            return Err(AppError::Cancelled(
                "filesystem-bridge sync cancelled by user during pull".to_string(),
            ));
        }
        // tick the lease heartbeat once per envelope
        // candidate so a slow shared-folder pull (thousands of files
        // sorted, opened, parsed) extends the 30 s TTL before any
        // sibling device could steal it. When no heartbeat is
        // installed (unit tests that exercise the collector directly)
        // the call is a cheap no-op.
        super::lease_heartbeat::tick()?;

        pulled_files += 1;

        // Stat first to skip oversized files cheaply, then re-validate
        // *after* opening the handle so a TOCTOU swap on a shared
        // sync folder (provider/SMB) can't bypass the cap by
        // shrinking the file between stat and open.
        let stat_size: u64 = if let Ok(meta) = fs::metadata(&path) {
            if meta.len() > MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES {
                pull_parse_errors += 1;
                diagnostics.push(oversized_envelope_diagnostic(
                    "stat",
                    meta.len(),
                    path.as_path(),
                ));
                continue;
            }
            meta.len()
        } else {
            0
        };

        // break before read if this file would push us
        // past the aggregate cap. Next cycle picks up the rest after
        // some backlog clears. Use the stat-time size as the
        // estimate; the post-open check below catches files that
        // grew between stat and open.
        if aggregate_bytes_read.saturating_add(stat_size) > MAX_FILESYSTEM_BRIDGE_AGGREGATE_BYTES {
            diagnostics.push(FilesystemBridgeDiagnostic::warn(
                "sync.filesystem_bridge.pull.aggregate_cap",
                "Filesystem bridge pull aggregate byte cap reached",
                format!(
                    "aggregate_bytes_read={aggregate_bytes_read}, stat_size={stat_size}, max_aggregate_bytes={MAX_FILESYSTEM_BRIDGE_AGGREGATE_BYTES}"
                ),
            ));
            break;
        }

        // Open then enforce the per-envelope cap with `Read::take` so
        // a file that grew (or got swapped to something larger)
        // between the stat and the read can't exceed the budget. We
        // request `cap + 1` bytes so that "at exactly the cap" still
        // passes while "one byte over" gets caught.
        let file = match fs::File::open(&path) {
            Ok(f) => f,
            Err(error) => {
                return Err(AppError::Internal(format!(
                    "Failed to open filesystem bridge sync file {}: {error}",
                    path.display()
                )));
            }
        };
        let mut reader = std::io::Read::take(file, MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES + 1);
        let mut raw = String::new();
        if let Err(error) = std::io::Read::read_to_string(&mut reader, &mut raw) {
            return Err(AppError::Internal(format!(
                "Failed to read filesystem bridge sync file {}: {error}",
                path.display()
            )));
        }
        if raw.len() as u64 > MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES {
            pull_parse_errors += 1;
            diagnostics.push(oversized_envelope_diagnostic(
                "read",
                raw.len() as u64,
                path.as_path(),
            ));
            continue;
        }
        aggregate_bytes_read = aggregate_bytes_read.saturating_add(raw.len() as u64);

        // Extract file stem for use as a fallback event ID.
        let file_stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();

        match parse_sync_file_result(&raw, &file_stem) {
            Ok(record) => {
                if record.envelope.device_id == local_device_id {
                    continue;
                }
                if !is_supported_incoming_record(&record) {
                    pull_parse_errors += 1;
                    continue;
                }
                if let Some(cursor) = since {
                    // typed `Hlc` envelopes at the wire
                    // boundary; the comparator helpers still take
                    // `&str`, so format once per record into a stack
                    // local.
                    let record_version_str = record.envelope.version.to_string();
                    let is_newer_than_cursor = compare_sync_versions_with_outbox_id(
                        &record_version_str,
                        &record.id,
                        &cursor.updated_at,
                        &cursor.event_id,
                    )
                    .is_gt();
                    if is_newer_than_cursor {
                        remote_events.push(record);
                    } else if within_filesystem_bridge_cursor_lookback(
                        &record_version_str,
                        &cursor.updated_at,
                    ) {
                        if known_lookback_event_ids.is_some_and(|ids| ids.contains(&record.id)) {
                            lookback_known_id_skipped += 1;
                            continue;
                        }
                        lookback_events.push(record);
                    }
                    continue;
                }
                remote_events.push(record);
            }
            Err(error) => {
                pull_parse_errors += 1;
                if error.blocks_pull_cursor() {
                    cursor_blocking_parse_errors += 1;
                }
                diagnostics.push(FilesystemBridgeDiagnostic::warn(
                    "sync.filesystem_bridge.pull.parse_error",
                    "Filesystem bridge pull failed to parse envelope",
                    format!("path={}, error={error}", path.display()),
                ));
            }
        }
    }

    let normalized_pull_cap = pull_cap.max(1);
    let max_lookback_candidates = normalized_pull_cap
        .saturating_mul(FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER)
        .max(1);
    remote_events.sort_by(|left, right| {
        compare_sync_versions_with_outbox_id(
            &left.envelope.version.to_string(),
            &left.id,
            &right.envelope.version.to_string(),
            &right.id,
        )
    });
    lookback_events.sort_by(|left, right| {
        compare_sync_versions_with_outbox_id(
            &left.envelope.version.to_string(),
            &left.id,
            &right.envelope.version.to_string(),
            &right.id,
        )
    });
    if lookback_events.len() > max_lookback_candidates {
        let drop_count = lookback_events.len() - max_lookback_candidates;
        lookback_events.drain(0..drop_count);
    }

    let pull_limit_hit;
    if remote_events.is_empty() {
        pull_limit_hit = lookback_events.len() > normalized_pull_cap;
        if lookback_events.len() > normalized_pull_cap {
            lookback_events.truncate(normalized_pull_cap);
        }
        remote_events = lookback_events;
    } else {
        pull_limit_hit = remote_events.len() > normalized_pull_cap;
        if remote_events.len() > normalized_pull_cap {
            remote_events.truncate(normalized_pull_cap);
        }
    }

    Ok(CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files,
        pull_parse_errors,
        cursor_blocking_parse_errors,
        lookback_known_id_skipped,
        pull_limit_hit,
        diagnostics,
        remote_events,
    })
}

fn oversized_envelope_diagnostic(
    phase: &str,
    size_bytes: u64,
    path: &Path,
) -> FilesystemBridgeDiagnostic {
    FilesystemBridgeDiagnostic::warn(
        "sync.filesystem_bridge.pull.oversized_envelope",
        "Filesystem bridge pull skipped oversized envelope",
        format!(
            "phase={phase}, size_bytes={}, max_envelope_bytes={}, path={}",
            size_bytes,
            MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES,
            path.display()
        ),
    )
}

pub(super) fn load_recent_lookback_outbox_ids(
    conn: &rusqlite::Connection,
    cursor: Option<&FilesystemBridgePullCursor>,
) -> AppResult<HashSet<String>> {
    let Some(cursor) = cursor else {
        return Ok(HashSet::new());
    };
    let cursor_ms = hlc_millis(&cursor.updated_at).ok_or_else(|| {
        AppError::Validation(
            "filesystem bridge lookback cursor must use a valid HLC version".to_string(),
        )
    })?;
    let cursor_ts = chrono::DateTime::from_timestamp_millis(cursor_ms).ok_or_else(|| {
        AppError::Validation(format!(
            "filesystem bridge lookback cursor HLC millis out of range: {}",
            cursor.updated_at
        ))
    })?;

    // produce the canonical millisecond-Z form so the
    // `created_at >= ?1` compare against `sync_outbox.created_at`
    // (written via `sync_timestamp_now`) stays at uniform precision.
    let floor_ts = lorvex_domain::time::format_sync_timestamp(
        cursor_ts - chrono::Duration::seconds(FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS),
    );
    let mut stmt = conn.prepare_cached(
        // bare comparison uses any index on created_at;
        // the datetime() wrapper forced a full scan of sync_outbox.
        "SELECT CAST(id AS TEXT) FROM sync_outbox WHERE created_at >= ?1",
    )?;
    let rows = stmt.query_map(params![floor_ts], |row| row.get::<_, String>(0))?;

    let mut ids = HashSet::new();
    for row in rows {
        ids.insert(row?);
    }
    Ok(ids)
}

#[cfg(test)]
mod tests;
