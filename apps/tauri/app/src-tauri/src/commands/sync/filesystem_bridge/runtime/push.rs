use super::super::{collection, fs, lease_heartbeat, Write};
use super::backoff::{record_outbox_retry, should_skip_outbox_for_backoff};
use super::naming::filesystem_bridge_file_stem;
use super::orchestration::usize_to_i64;
use crate::error::{AppError, AppResult};
use lorvex_sync::envelope::SyncEnvelope;
use lorvex_sync::outbox;

pub(super) fn classify_existing_sync_file(
    existing_raw: &str,
    envelope: &SyncEnvelope,
) -> AppResult<ExistingSyncFileClassification> {
    let existing_env: SyncEnvelope = serde_json::from_str(existing_raw).map_err(|error| {
        AppError::Serialization(format!(
            "failed to parse existing sync file during idempotency check: {error}"
        ))
    })?;

    if existing_env.entity_type != envelope.entity_type
        || existing_env.entity_id != envelope.entity_id
        || existing_env.device_id != envelope.device_id
    {
        return Ok(ExistingSyncFileClassification::Mismatch);
    }
    if existing_env.version == envelope.version {
        return Ok(ExistingSyncFileClassification::Match);
    }
    // typed `Hlc` at the wire boundary — `Ord` on
    // `Hlc` is the canonical lex-order on `(physical_ms, counter,
    // device_suffix)`, so this comparison no longer needs the
    // raw-string `<` shortcut.
    if existing_env.version < envelope.version {
        Ok(ExistingSyncFileClassification::OnDiskOlder)
    } else {
        Ok(ExistingSyncFileClassification::OnDiskNewer)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ExistingSyncFileClassification {
    Match,
    OnDiskOlder,
    OnDiskNewer,
    Mismatch,
}

fn record_push_write_error(
    push_write_errors: &mut i64,
    retry_ids: &mut Vec<i64>,
    error_messages: &mut Vec<String>,
    outbox_id: i64,
    message: String,
) {
    *push_write_errors += 1;
    retry_ids.push(outbox_id);
    error_messages.push(message);
}

pub(super) struct PushPhaseOutcome {
    pub(super) pushed_ids: Vec<i64>,
    pub(super) retry_ids: Vec<i64>,
    pub(super) push_write_errors: i64,
    pub(super) attempted_push: i64,
    pub(super) cancelled: bool,
    /// Per-write error messages collected during the filesystem-I/O
    /// loop. The caller writes them to error_logs after re-acquiring
    /// the DB connection — sending them only to stderr would leave
    /// them invisible on Tauri release binaries / MCP stdio hosts.
    pub(super) error_messages: Vec<String>,
}

struct PushPhaseRecorder {
    pushed_ids: Vec<i64>,
    retry_ids: Vec<i64>,
    push_write_errors: i64,
    error_messages: Vec<String>,
}

impl PushPhaseRecorder {
    fn with_capacity(capacity: usize) -> Self {
        Self {
            pushed_ids: Vec::with_capacity(capacity),
            retry_ids: Vec::new(),
            push_write_errors: 0,
            error_messages: Vec::new(),
        }
    }

    fn record_error(&mut self, outbox_id: i64, message: String) {
        record_push_write_error(
            &mut self.push_write_errors,
            &mut self.retry_ids,
            &mut self.error_messages,
            outbox_id,
            message,
        );
    }

    fn record_pushed(&mut self, outbox_id: i64) {
        self.pushed_ids.push(outbox_id);
    }

    fn into_outcome(self, attempted_push: i64, cancelled: bool) -> PushPhaseOutcome {
        PushPhaseOutcome {
            pushed_ids: self.pushed_ids,
            retry_ids: self.retry_ids,
            push_write_errors: self.push_write_errors,
            attempted_push,
            cancelled,
            error_messages: self.error_messages,
        }
    }
}

/// **Phase B -- Filesystem I/O:** push outbox entries to the sync directory.
pub(super) fn phase_push_to_filesystem(
    pending: Vec<outbox::OutboxEntry>,
    sync_dir: &std::path::Path,
) -> AppResult<PushPhaseOutcome> {
    phase_push_to_filesystem_with_cancel_probe(pending, sync_dir, || {
        crate::commands::sync::runtime::is_sync_cancelled_for(
            crate::commands::sync::runtime::SyncKind::FilesystemBridge,
        )
    })
}

pub(super) fn phase_push_to_filesystem_with_cancel_probe(
    pending: Vec<outbox::OutboxEntry>,
    sync_dir: &std::path::Path,
    mut is_cancelled: impl FnMut() -> bool,
) -> AppResult<PushPhaseOutcome> {
    let now_dt = chrono::Utc::now();
    let attempted_push = usize_to_i64("pending outbox count", pending.len())?;
    let mut recorder = PushPhaseRecorder::with_capacity(pending.len());

    for entry in pending {
        // cheap cancel probe at the head of every
        // iteration. The user can cancel mid-push; bail with
        // whatever results we already have so the caller's record
        // path keeps the partial-progress envelopes (rather than
        // losing them in an Err return).
        if is_cancelled() {
            return Ok(recorder.into_outcome(attempted_push, true));
        }
        // tick the lease heartbeat once per outbox
        // entry so a multi-minute push (large pending queue, slow
        // network share) extends the 30 s TTL before any sibling
        // device could steal it. When no heartbeat is installed (unit
        // tests that drive this phase directly) the call is a cheap
        // no-op.
        lease_heartbeat::tick()?;

        if should_skip_outbox_for_backoff(&entry, &now_dt) {
            continue;
        }
        // a filesystem-bridge `sync_dir` typically
        // sits inside Dropbox, Syncthing, or an SMB share where
        // every connected device — and any external auditor with
        // directory-listing access — sees filenames without ever
        // reading content. Embedding the raw `device_id` (a stable
        // UUID) and the monotonic outbox `id` leaks a per-device
        // identifier plus a usage-volume signal across that boundary.
        // We hash both into a single opaque file stem keyed on the
        // device_id so collisions remain impossible and the local GC
        // can still recognize "ours" via a precomputed hash prefix
        // (see `gc_stale_sync_files`).
        let file_stem = filesystem_bridge_file_stem(&entry.envelope.device_id, entry.id);
        let path = sync_dir.join(format!("{file_stem}.json"));
        let tmp_path = sync_dir.join(format!("{file_stem}.json.tmp"));

        let bytes = match serialize_outbox_entry_bytes(&entry) {
            Ok(bytes) => bytes,
            Err(message) => {
                recorder.record_error(entry.id, message);
                continue;
            }
        };

        // the `path.exists` probe and
        // the subsequent `write_new_sync_file` open are not atomic,
        // but the TOCTOU window is harmless on this surface. The
        // `{device_id}_{outbox_id}.json` filename is uniquely
        // owned by *this* device, and the surrounding sync_owner
        // RAII guard (see #2982-H1 + the per-cycle heartbeat from
        // #2986-M17 above) guarantees that no sibling device holds
        // the lease while this loop runs — so a sibling cannot
        // race-create the same path between the probe and the
        // write. Within this device the probe outcome only steers
        // us between two equally-safe code paths: if the file is
        // present we hand off to `handle_existing_sync_file` (which
        // verifies the bytes match before treating the row as
        // already-pushed), and if it is absent we call
        // `write_new_sync_file` whose tmp path uses POSIX `O_EXCL`
        // (`create_new(true)`) so a concurrent in-process writer
        // would surface `AlreadyExists` and either retry once or
        // record a recoverable error rather than truncating
        // someone else's bytes. Documenting the contract here so
        // future maintainers do not "fix" the probe by collapsing
        // it into the open call and accidentally lose the
        // hand-off to `handle_existing_sync_file`.
        if path.exists() {
            if let Err(message) = handle_existing_sync_file(&entry, &path, &mut recorder) {
                recorder.record_error(entry.id, message);
            }
            continue;
        }

        if let Err(message) = write_new_sync_file(&entry, &bytes, &path, &tmp_path, &mut recorder) {
            recorder.record_error(entry.id, message);
        }
    }

    Ok(recorder.into_outcome(attempted_push, false))
}

fn serialize_outbox_entry_bytes(entry: &outbox::OutboxEntry) -> Result<Vec<u8>, String> {
    serde_json::to_vec_pretty(&entry.envelope)
        .map_err(|error| format!("serialize outbox entry {} failed: {error}", entry.id))
}

fn handle_existing_sync_file(
    entry: &outbox::OutboxEntry,
    path: &std::path::Path,
    recorder: &mut PushPhaseRecorder,
) -> Result<(), String> {
    // Stat first — skip the read if an attacker planted an
    // oversized file at the target name. Mirrors the pull-side
    // cap in collection.rs so writes and reads agree.
    if let Ok(meta) = fs::metadata(path) {
        if meta.len() > collection::MAX_FILESYSTEM_BRIDGE_ENVELOPE_BYTES {
            return Err(format!(
                "sync file {} is oversized ({} bytes > cap); treating as non-idempotent write",
                path.display(),
                meta.len(),
            ));
        }
    }

    let existing_raw = fs::read_to_string(path).map_err(|read_error| {
        format!(
            "sync file {} already exists but cannot be read for idempotency check: {read_error}",
            path.display(),
        )
    })?;
    // Classify the version relationship instead of a single bool
    // match. We overwrite the older crash artifact and proceed; only
    // a truly impossible mismatch (different entity / device) raises
    // an error, and an on-disk-newer envelope quietly marks the
    // stale local row synced. A bool match would let a stale crash
    // artifact (older HLC) loop forever — recording an error every
    // cycle until the row hit MAX_RETRIES — because the same
    // mismatched file would keep being seen.
    let classification =
        classify_existing_sync_file(&existing_raw, &entry.envelope).map_err(|error| {
            format!(
                "sync file {} already exists but is malformed for idempotency check: {error}",
                path.display(),
            )
        })?;
    match classification {
        ExistingSyncFileClassification::Match => {
            recorder.record_pushed(entry.id);
            Ok(())
        }
        ExistingSyncFileClassification::OnDiskOlder => {
            // Stale crash artifact from a previous push that died
            // between write_all and rename. The on-disk version is
            // strictly < our outbox row's version, so it's safe to
            // overwrite — no peer has consumed it (pull-side reads
            // wouldn't load a non-renamed staging file anyway, and
            // a renamed older file would only have been consumed at
            // the older HLC which any peer applying it would have
            // since superseded with our outbox row's newer version).
            // Delete the stale file and let the caller proceed with
            // a fresh atomic rename.
            fs::remove_file(path).map_err(|error| {
                format!(
                    "failed to remove stale sync file {} (older HLC than outbox row {}): {error}",
                    path.display(),
                    entry.id,
                )
            })?;
            // Tell the caller the file is gone so it falls through to
            // write_new_sync_file's normal path. We do that by
            // signaling via Err — the calling site already handles
            // Err by recording_error and re-trying next cycle. The
            // next cycle sees no file at the path and takes the
            // create-fresh path. (A more invasive refactor would
            // return an enum here so the caller can write fresh in
            // the same cycle; for now we lean on the next-tick
            // retry which is mechanically simpler and bounded by the
            // retry budget.)
            Err(format!(
                "stale sync file {} removed; will write fresh next cycle",
                path.display(),
            ))
        }
        ExistingSyncFileClassification::OnDiskNewer => {
            // Our local outbox row is stale relative to what's
            // already on disk — a newer outbox row for the same
            // entity must have pushed before this one had a chance.
            // Mark THIS row synced (no-op push) so the queue can
            // proceed instead of blocking on a row whose work has
            // already been done by a successor.
            recorder.record_pushed(entry.id);
            Ok(())
        }
        ExistingSyncFileClassification::Mismatch => Err(format!(
            "sync file {} already exists with foreign-device or wrong-entity payload \
             for outbox entry {} — refusing to overwrite",
            path.display(),
            entry.id,
        )),
    }
}

fn write_new_sync_file(
    entry: &outbox::OutboxEntry,
    bytes: &[u8],
    path: &std::path::Path,
    tmp_path: &std::path::Path,
    recorder: &mut PushPhaseRecorder,
) -> Result<(), String> {
    // the filesystem-bridge sync_dir often lives on a
    // multi-writer surface (Dropbox, Syncthing, network share). The
    // tmp path is predictable (M14 hashes the stem, but
    // it's still derived deterministically from the device/outbox
    // pair), so a hostile or buggy peer could pre-plant a symlink
    // there and the legacy `.create(true).truncate(true)` would
    // happily follow it, letting the writer truncate-and-overwrite an
    // arbitrary path the attacker chose. `create_new` (POSIX `O_EXCL`
    // / Windows `CREATE_NEW`) refuses to open a pre-existing file or
    // symlink. If a stale crash-artifact tmp from a prior process is
    // genuinely sitting there we remove it and retry once, matching
    // the exclusive-create model used by the blob writer.
    let open_tmp = || {
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(tmp_path)
    };
    let mut file = match open_tmp() {
        Ok(f) => f,
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            fs::remove_file(tmp_path).map_err(|e| {
                format!("remove stale sync tmp {} failed: {e}", tmp_path.display(),)
            })?;
            open_tmp()
                .map_err(|error| format!("open sync file {} failed: {error}", path.display(),))?
        }
        Err(error) => {
            return Err(format!("open sync file {} failed: {error}", path.display(),));
        }
    };

    if let Err(error) = file.write_all(bytes).and_then(|_| file.sync_all()) {
        // drop the cleanup error. The write/sync
        // failure is the actionable signal returned to the caller; a
        // secondary remove_file failure is reaped by the next
        // successful push because the deterministic `.tmp` path is
        // reused (open() above takes the `AlreadyExists` retry branch).
        let _ = fs::remove_file(tmp_path);
        return Err(format!(
            "write sync file {} failed: {error}",
            path.display(),
        ));
    }
    if let Err(error) = fs::rename(tmp_path, path) {
        // same rationale as the L8 site — the rename
        // error is the actionable signal; a stale tmp is reaped on the
        // next push.
        let _ = fs::remove_file(tmp_path);
        return Err(format!(
            "rename sync file {} failed: {error}",
            path.display(),
        ));
    }
    recorder.record_pushed(entry.id);
    Ok(())
}

/// **Phase C – DB write:** record retries and mark pushed entries as synced.
pub(super) fn phase_record_push_results(
    conn: &rusqlite::Connection,
    outcome: &PushPhaseOutcome,
    now: &str,
) -> AppResult<()> {
    // the orchestrator (`run_filesystem_bridge_sync_inner`)
    // acquires a short-lived connection for this phase and explicitly
    // releases the writer between phases, so wrapping the retry + mark
    // sequence in `with_immediate_transaction` is both safe (short
    // write transaction) and necessary (each raw `conn.execute` call
    // would otherwise race with a sibling MCP writer and surface
    // `SQLITE_BUSY`). The per-message `error_logs` inserts remain
    // best-effort and inside the same transaction so they also inherit
    // busy-retry semantics.
    lorvex_store::with_immediate_transaction(conn, |conn| {
        for outbox_id in &outcome.retry_ids {
            record_outbox_retry(conn, *outbox_id, now)?;
        }
        for outbox_id in &outcome.pushed_ids {
            outbox::mark_synced(conn, *outbox_id, now).map_err(AppError::from)?;
        }
        // The filesystem-I/O loop collects per-write error messages
        // and persists them to `error_logs` so Settings →
        // Diagnostics can surface them — stderr-only logging would be
        // invisible in Tauri release / MCP stdio hosts. Best-effort:
        // if the error_logs insert itself fails, don't abort the
        // whole phase.
        for message in &outcome.error_messages {
            let _ = crate::commands::diagnostics::append_error_log_internal(
                conn,
                "sync.filesystem_bridge.push",
                message,
                None,
                Some("error".to_string()),
            );
        }
        Ok::<_, AppError>(())
    })?;
    Ok(())
}
