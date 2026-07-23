//! Fatal startup-failure path.
//!
//! A database file that is not a usable Lorvex database (incompatible schema,
//! a DB written by a newer build, corrupt schema bookkeeping, not-a-database,
//! or a malformed image) is recovered upstream in
//! `db::connection::open_pool_with_recovery`: the file is set aside with a
//! unique timestamped name and a fresh database is created. This path is only
//! reached for failures that are NOT safe to auto-recover — a build-side
//! `LockChecksumMismatch`, a transient/environmental error (locked, busy, I/O,
//! permissions), or the rare case where the quarantine rename itself failed.
//!
//! For those, [`ensure_database_ready_fail`] writes a redacted on-disk marker
//! next to the database file, then panics with a user-facing message the panic
//! hook (`super::panic_hook`) persists to `error_logs`. This path never
//! modifies the DB file — the user's data is left exactly as it was so they can
//! take informed action (re-install the correct build, fix the lock, retry once
//! the file is no longer locked). The marker file is the triage artifact.

use crate::db;

use super::migration_progress::{format_migration_progress_timeline, MigrationProgressEvent};

/// write the startup-failure marker with owner-only
/// permissions so the redacted error body is not world-readable on a
/// shared Unix host. On Windows the file inherits NTFS ACLs from the
/// parent directory (which is already per-user under
/// `%APPDATA%/Lorvex/`), so a plain write is sufficient. Best-effort
/// throughout — the panic that follows is the user-visible signal,
/// the marker is a courtesy artifact for triage.
pub(super) fn write_owner_only_marker(marker: &std::path::Path, body: &str) {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;

        match std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(marker)
        {
            Ok(mut f) => {
                let _ = f.write_all(body.as_bytes());
            }
            Err(_) => {
                // Fallback: best-effort plain write. Better to leave a
                // marker the user can inspect than to lose the diagnostic
                // entirely just because the strict-permission open
                // failed (e.g. exotic FS that rejects the mode bits).
                let _ = std::fs::write(marker, body);
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = std::fs::write(marker, body);
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(super) fn ensure_database_ready_fail(
    error_str: String,
    migration_progress_events: &[MigrationProgressEvent],
) -> ! {
    // This fatal path never renames or deletes the DB file. Failures that ARE
    // safe to auto-recover (incompatible schema, downgrade, corrupt schema, a
    // non-database file) are handled upstream in `open_pool_with_recovery`,
    // which sets the file aside under a unique timestamped name before
    // recreating it. Anything that reaches here is non-recoverable (a build-side
    // lock-checksum drift, a transient/environmental error, or a failed
    // quarantine), so the file is left exactly as it was and a persistent
    // on-disk marker gives the user the information they need to act, without
    // any destructive side effect.
    let db = db::db_path();

    if let Some(parent) = db.parent() {
        let marker = parent.join("db.startup-failure.txt");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        // Both `error_str` (which can carry caller-controlled fragments
        // — a serde failure formats the failing JSON; a SQLite I/O
        // error formats the absolute filesystem path) and the raw
        // `db.display()` path (which contains the user's home dir on
        // every platform) are routed through the diagnostics redactor
        // before persisting, so a user emailing this file to support
        // doesn't leak `/Users/<name>/...` or other PII.
        let redacted_error = lorvex_domain::diagnostics::redact_diagnostic_text(&error_str);
        let redacted_path =
            lorvex_domain::diagnostics::redact_diagnostic_text(&db.display().to_string());
        let migration_timeline = format_migration_progress_timeline(migration_progress_events);
        let body = format!(
            "Lorvex failed to open the local database at startup.\n\
             \n\
             Timestamp (unix seconds): {now}\n\
             Database path: {redacted_path}\n\
             Error: {redacted_error}\n\
             \n\
             Migration progress:\n\
             {migration_timeline}\
             \n\
             YOUR DATA HAS NOT BEEN DELETED OR MOVED. The DB file\n\
             is still at the path above, in exactly the state it\n\
             was when the app last closed.\n\
             \n\
             Common causes and recovery:\n\
               - Schema checksum mismatch from downgrading Lorvex:\n\
                 re-install the later version you were running,\n\
                 OR contact support for a supervised migration.\n\
               - Disk corruption (rare): copy the .sqlite file\n\
                 elsewhere before attempting repair, then run\n\
                 `sqlite3 db.sqlite 'PRAGMA integrity_check;'`.\n\
               - App bug (version skew during rollout): try\n\
                 quitting, launching the last-known-good build,\n\
                 or contact support.\n",
        );
        // `OpenOptions` with explicit 0o600 mode is used on Unix so
        // the marker is owner-only — a plain `std::fs::write` would
        // leave the file at the process default umask (0644 on most
        // Unixes, world-readable), and the body still surfaces the
        // redacted DB path and error string that a co-tenant on a
        // shared host shouldn't be able to tail. Windows inherits
        // ACLs from the parent directory which is already user-scoped under
        // %APPDATA%.
        write_owner_only_marker(&marker, &body);
    }

    // detect the two specific migration-layer
    // errors that warrant actionable copy rather than a generic
    // "failed to initialize local database" string. The
    // [FATAL_MIGRATION_*] prefixes are set in
    // `db::connection::init_pool`.
    let message = if error_str.contains("[FATAL_MIGRATION_CHECKSUM]") {
        format!(
            "[startup] Lorvex cannot open the local database because a migration's \
             checksum does not match the recorded hash. This typically means the app \
             binary is older than the one that wrote this database (a downgrade). \
             Install the latest Lorvex release, or reset the database from \
             Settings → Data → Reset on a device that can open it. \
             Your data at {path} has NOT been touched. Details: {error_str}",
            path = db.display(),
        )
    } else if error_str.contains("[FATAL_MIGRATION_DOWNGRADE]") {
        format!(
            "[startup] Lorvex cannot open the local database because it was written \
             by a newer version than this binary supports. Update to the latest \
             Lorvex release to open it. Your data at {path} has NOT been touched. \
             Details: {error_str}",
            path = db.display(),
        )
    } else {
        format!(
            "[startup] failed to initialize local database: {error_str}. \
             Lorvex will not proceed to avoid data loss. A diagnostic \
             file has been written next to the DB. If this is a schema \
             downgrade, re-install the later version that was running \
             previously. The DB file at {path} is intact.",
            path = db.display(),
        )
    };
    panic!("{message}");
}
