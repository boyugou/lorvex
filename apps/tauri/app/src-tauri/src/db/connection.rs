use lorvex_store::ConnectionPool;
use lorvex_store::PoolError;
use rusqlite::Connection;
use std::path::{Path, PathBuf};
use std::sync::{MutexGuard, OnceLock};

use crate::error::{AppError, AppResult};

use super::path::db_path;

// ---------------------------------------------------------------------------
// Connection pool (writer + read-only connections)
// ---------------------------------------------------------------------------

/// Number of read-only connections in the pool.
///
/// bumped from 3 → 4 to give the
/// Tauri-side reader pool a small amount of additional burst
/// headroom. The desktop app routinely runs four concurrent read
/// callers in steady state — the today-view query, a calendar
/// timeline projection, the FTS-backed quick-capture suggester,
/// and one of the periodic background panels (changelog feed,
/// streak rebuild, jump-list refresh). With pool size 3 a single
/// long-running read (a wide changelog window, a cold streak
/// rebuild) would gate every other reader behind it on the same
/// connection mutex, even though the SQLite WAL would otherwise
/// let them all run in parallel. Each read connection costs a
/// single open file descriptor and ~1 KB of cached page memory,
/// so the additional slot is effectively free; the upper bound
/// stays well below the four-connection ceiling recommended in
/// `ConnectionPool::new`. The MCP-server side keeps `2` because
/// its reader cardinality is bounded by the assistant's tool-call
/// fan-out, which never exceeds two concurrent SELECTs.
// The MCP-server's reader pool size lives under the distinct name
// `MCP_READ_POOL_SIZE` in `mcp-server/src/server/connections.rs`.
// The two pools
// have different sizes and different sizing rationales; sharing a
// name would force readers searching for "where is the pool sized"
// to disambiguate from context.
const READ_POOL_SIZE: usize = 4;

// Store Result so init failures are surfaced as errors, not panics.
static POOL: OnceLock<Result<ConnectionPool, String>> = OnceLock::new();

fn get_pool() -> AppResult<&'static ConnectionPool> {
    POOL.get_or_init(init_pool)
        .as_ref()
        .map_err(|e| AppError::Internal(e.clone()))
}

/// Return a reference to the connection pool.
///
/// Initializes the pool on first call (creates parent directories, opens the
/// writer connection, applies PRAGMAs + migrations, and initializes HLC state).
/// Subsequent calls return the cached pool.
pub fn get_db() -> AppResult<&'static ConnectionPool> {
    get_pool()
}

/// Lock the writer connection and return a `MutexGuard`.
///
/// This is the primary write-path accessor. The guard holds the write lock
/// for its lifetime, serializing all write operations.
pub fn get_conn() -> AppResult<MutexGuard<'static, Connection>> {
    get_pool()?
        .writer_result()
        .map_err(|e| AppError::Internal(format!("failed to lock writer connection: {e}")))
}

/// Try to lock the writer connection without blocking.
///
/// This is reserved for best-effort diagnostics on error-return paths. Those
/// paths may already be unwinding while holding the writer guard, so blocking
/// on `get_conn()` can self-deadlock before Tauri receives the IPC error.
pub(crate) fn try_get_conn() -> AppResult<Option<MutexGuard<'static, Connection>>> {
    get_pool()?
        .try_writer_result()
        .map_err(|e| AppError::Internal(format!("failed to try-lock writer connection: {e}")))
}

/// Return a read-only connection from the round-robin pool.
///
/// Read connections are opened with `SQLITE_OPEN_READ_ONLY` and
/// `PRAGMA query_only = ON`. They share the same WAL-mode database and can
/// serve queries concurrently without blocking the writer.
pub fn get_read_conn() -> AppResult<MutexGuard<'static, Connection>> {
    get_pool()?
        .read_lock_result()
        .map_err(|e| AppError::Internal(format!("failed to lock read connection: {e}")))
}

// ---------------------------------------------------------------------------
// Pool initialization
// ---------------------------------------------------------------------------

/// Open the connection pool, recovering from a database file that is not a
/// usable Lorvex database by setting it aside and starting fresh.
///
/// On the first open failure, [`PoolError::is_incompatible_database`] decides
/// whether the file is genuinely unusable (incompatible schema, a DB written by
/// a newer build, corrupt schema bookkeeping, not-a-database, or a malformed
/// image). If so — and the file exists — it is renamed to a unique timestamped
/// `…​.incompatible-<unix-secs>-<nanos>.bak` (together with its `-wal`/`-shm`
/// sidecars, so the stale WAL can never be replayed onto the fresh file) and
/// the pool is reopened against the now-empty path. The quarantined file is
/// preserved, never deleted, and the recovery is recorded to `error_logs`.
///
/// Transient/environmental failures (locked, busy, I/O, permissions) and the
/// build-side `LockChecksumMismatch` are NOT recovered — they map to the
/// existing actionable `[FATAL_MIGRATION_*]` messages and propagate so the
/// process exits without touching the user's data. If the quarantine rename
/// itself fails, the original failure is surfaced rather than risking a
/// destructive half-step.
fn open_pool_with_recovery(path: &Path) -> Result<ConnectionPool, String> {
    let first = match ConnectionPool::new(path, READ_POOL_SIZE) {
        Ok(pool) => return Ok(pool),
        Err(e) => e,
    };

    if !(first.is_incompatible_database() && path.exists()) {
        return Err(map_fatal_pool_error(&first));
    }

    let reason = first.to_string();
    let backup = match quarantine_incompatible_database(path) {
        Ok(backup) => backup,
        Err(io_err) => {
            // Could not move the file aside — refuse to proceed rather than
            // attempt a destructive open. Surface the original incompatibility.
            return Err(format!(
                "{}. Additionally, the database could not be set aside automatically \
                 ({io_err}); it has not been modified.",
                map_fatal_pool_error(&first)
            ));
        }
    };

    let pool = ConnectionPool::new(path, READ_POOL_SIZE).map_err(|e| map_fatal_pool_error(&e))?;
    if let Ok(conn) = pool.writer_result() {
        record_startup_diagnostic(
            &conn,
            "store.database.incompatible_recovered",
            "existing database could not be opened; set aside and recreated",
            &format!("reason: {reason}; backup: {}", backup.display()),
            "warning",
        );
    }
    Ok(pool)
}

/// Map a non-recoverable pool-open failure to the user-facing fatal message.
///
/// The `[FATAL_MIGRATION_*]` prefixes are consumed by
/// `lib.rs::show_startup_fatal_dialog` to surface a native dialog before any
/// window mounts; `startup_failure::ensure_database_ready_fail` matches the
/// same prefixes for its actionable copy.
fn map_fatal_pool_error(e: &PoolError) -> String {
    use lorvex_store::MigrationError as ME;
    match e {
        PoolError::Migration(ME::ChecksumMismatch { version, name, .. }) => format!(
            "[FATAL_MIGRATION_CHECKSUM] Migration {version} ({name}) has a different \
             hash than the one recorded in your database. This usually means the app \
             binary is older than the one that wrote this database. \
             Download the latest Lorvex release, or reset the database from Settings \
             → Data → Reset. Underlying error: {e}"
        ),
        PoolError::Migration(ME::DowngradeDetected {
            binary_max_version,
            db_max_version,
        }) => format!(
            "[FATAL_MIGRATION_DOWNGRADE] Your database was written by a newer version \
             of Lorvex (v{db_max_version}) than this one supports (v{binary_max_version}). \
             Update to the latest release to open it. Underlying error: {e}"
        ),
        // surface lock-checksum drift as a distinct fatal so a developer running
        // an unbuilt binary against an unfrozen `001_schema.sql` sees exactly
        // which file is out of sync. This is a build-side error, never a user
        // DB problem, so it is deliberately NOT auto-recovered.
        PoolError::Migration(ME::LockChecksumMismatch { name, .. }) => format!(
            "[FATAL_MIGRATION_CHECKSUM] {name} hash disagrees with checksums.lock. \
             The schema SQL was edited without regenerating the lock — this is a \
             build-side error, not a corrupted database. Run \
             `npm run verify:migration-checksums --update` to refresh the lock, \
             then rebuild. Underlying error: {e}"
        ),
        _ => format!("failed to create connection pool: {e}"),
    }
}

/// Rename the database file and its `-wal`/`-shm` sidecars to a unique
/// timestamped `…​.incompatible-<unix-secs>-<nanos>.bak` alongside the original.
/// Returns the backup path of the main file. The data is preserved, never
/// deleted. The unique stamp ensures a second occurrence never overwrites an
/// earlier backup.
fn quarantine_incompatible_database(path: &Path) -> std::io::Result<PathBuf> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let stamp = format!("{}-{}", now.as_secs(), now.subsec_nanos());

    let file_name = path
        .file_name()
        .map(|n| n.to_os_string())
        .unwrap_or_else(|| std::ffi::OsString::from("db.sqlite"));
    let mut backup_name = file_name;
    backup_name.push(format!(".incompatible-{stamp}.bak"));
    let backup = path.with_file_name(&backup_name);

    std::fs::rename(path, &backup)?;
    // Move the WAL/SHM sidecars under the same suffix when present. A leftover
    // `-wal` next to a freshly-created DB would be replayed by SQLite and
    // corrupt it, so these must not be left behind.
    for sidecar in ["-wal", "-shm"] {
        let from = sidecar_path(path, sidecar);
        if from.exists() {
            let to = sidecar_path(&backup, sidecar);
            // Sidecars are recreated on the next open; a failure to move one is
            // non-fatal as long as the main file moved.
            let _ = std::fs::rename(&from, &to);
        }
    }
    Ok(backup)
}

/// Append a SQLite sidecar suffix (`-wal` / `-shm`) to a database path.
fn sidecar_path(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}

fn init_pool() -> Result<ConnectionPool, String> {
    let path = db_path();
    let pool = open_pool_with_recovery(&path)?;

    // Post-init steps that require the writer connection:
    // initialize HLC before any canonical writes.
    {
        let conn = pool
            .writer_result()
            .map_err(|e| format!("failed to lock writer connection: {e}"))?;
        lorvex_store::persist_pending_db_location_diagnostics(&conn);
        if let Err(e) = crate::hlc::init_hlc(&conn) {
            return Err(format!("HLC initialization failed: {e}"));
        }
        // Best-effort recovery steps — these should never prevent the app from starting.
        // A corrupt sync entry, stale shadow, or blob issue is recoverable at runtime.
        //
        // route payload-shadow promotion failures
        // through `error_logs` (matching the background pending_inbox
        // drain) so Settings → Diagnostics surfaces them instead of
        // burying the failure in stderr where the user never sees it.
        if let Err(e) = lorvex_sync::startup_maintenance::promote_startup_payload_shadows(&conn) {
            record_startup_diagnostic(
                &conn,
                "store.payload_shadow.startup_promote_failed",
                "payload-shadow startup promotion failed",
                &e.to_string(),
                "error",
            );
        }
        // pending_inbox drain is unbounded (FK retries can
        // iterate over thousands of pending envelopes under a
        // post-reseed scenario) and is recoverable from later sync
        // ticks. Move it to the background thread below so window
        // mount isn't gated on it. HLC init + payload-shadow
        // promotion remain synchronous because they establish
        // invariants the first read depends on.
    }

    Ok(pool)
}

/// Spawn the startup maintenance pass on a background thread.
/// MUST be called AFTER `get_db()`
/// (which runs `init_pool`) has returned — otherwise the spawned
/// thread's `crate::db::get_conn()` re-enters `POOL.get_or_init`
/// and blocks on the still-in-flight initial init.
///
/// Calling this from inside `init_pool` is unsafe: the spawn would
/// return while the caller is still inside
/// `OnceLock::get_or_init`, so the new thread's `get_or_init` call
/// would block waiting for the first init to finish. Benign on the
/// happy path but with two concrete risks:
/// 1. If `init_pool` panics (e.g. HLC init fails), the spawned
///    thread blocks FOREVER — `OnceLock` does not propagate poison.
///    The maintenance thread becomes a zombie waiter.
/// 2. The thread-creation-failure fallback called
///    `pool.writer_result()` on a local `pool` variable while
///    `pool` was still owned by `init_pool` — borrow-checker
///    accident that worked only because of evaluation order.
///
/// This helper is called from `tauri::Builder::setup()` so
/// `init_pool` has definitively completed before the spawn runs.
pub fn schedule_startup_maintenance() {
    if let Err(e) = std::thread::Builder::new()
        .name("lorvex-startup-maintenance".into())
        .spawn(move || {
            if let Ok(conn) = crate::db::get_conn() {
                // drain the pending inbox off the
                // critical path. FK-retry can be unbounded under
                // a post-reseed scenario. Deferring here means
                // first paint doesn't wait on it; the next sync
                // tick (on window focus or interval) will
                // continue the drain regardless.
                //
                // When the startup drain unblocks FK-stalled rows,
                // fan out `data-changed` so the UI re-renders the
                // just-applied state. Without the event, the drain
                // would mutate the DB while the renderer kept its
                // first-paint snapshot until a manual refresh.
                match lorvex_sync::startup_maintenance::run_startup_sync_maintenance_with_options(
                    &conn,
                    lorvex_sync::startup_maintenance::StartupSyncMaintenanceOptions {
                        promote_payload_shadows: false,
                    },
                ) {
                    Ok(report) => {
                        lorvex_sync::startup_maintenance::persist_startup_maintenance_warnings(
                            &conn,
                            &report.warnings,
                        );
                        if report.payload_shadows_promoted > 0 {
                            record_startup_info(
                                &conn,
                                "app.startup.payload_shadows_promoted",
                                "payload shadow rows promoted during startup maintenance",
                                &format!(
                                    "payload_shadows_promoted={}",
                                    report.payload_shadows_promoted
                                ),
                            );
                        }
                        if !report.pending_inbox_drain.replayed_entity_types.is_empty() {
                            crate::commands::emit_data_changed_for_entity_types(
                                &report.pending_inbox_drain.replayed_entity_types,
                            );
                        }
                    }
                    Err(e) => {
                        record_startup_warning(
                            &conn,
                            "app.startup.pending_inbox_drain_failed",
                            "background pending inbox drain failed",
                            &e.to_string(),
                        );
                    }
                }
                if let Err(e) = lorvex_store::run_startup_preferences_integrity(&conn) {
                    record_startup_warning(
                        &conn,
                        "app.startup.preferences_integrity_failed",
                        "background preferences integrity pass failed",
                        &e.to_string(),
                    );
                }
                // auto-purge Trash entries older than the
                // retention window. `run_startup_trash_purge` swallows
                // errors after logging them — a malformed trash row
                // must never block first paint.
                crate::commands::run_startup_trash_purge(&conn);
            }
        })
    {
        // Fall back to synchronous run so we don't skip the
        // startup maintenance pass entirely on thread-creation failure.
        // `get_conn` is safe here because `init_pool` already
        // completed before this fallback runs.
        if let Ok(conn) = crate::db::get_conn() {
            record_startup_warning(
                &conn,
                "app.startup.thread_spawn_failed",
                "failed to spawn startup maintenance thread",
                &e.to_string(),
            );
            match lorvex_sync::startup_maintenance::run_startup_sync_maintenance_with_options(
                &conn,
                lorvex_sync::startup_maintenance::StartupSyncMaintenanceOptions {
                    promote_payload_shadows: false,
                },
            ) {
                Ok(report) => {
                    lorvex_sync::startup_maintenance::persist_startup_maintenance_warnings(
                        &conn,
                        &report.warnings,
                    );
                    if !report.pending_inbox_drain.replayed_entity_types.is_empty() {
                        crate::commands::emit_data_changed_for_entity_types(
                            &report.pending_inbox_drain.replayed_entity_types,
                        );
                    }
                }
                Err(e) => {
                    record_startup_warning(
                        &conn,
                        "app.startup.fallback_pending_inbox_drain_failed",
                        "fallback pending inbox drain failed",
                        &e.to_string(),
                    );
                }
            }
            if let Err(e) = lorvex_store::run_startup_preferences_integrity(&conn) {
                record_startup_warning(
                    &conn,
                    "app.startup.fallback_preferences_integrity_failed",
                    "fallback preferences integrity pass failed",
                    &e.to_string(),
                );
            }
            crate::commands::run_startup_trash_purge(&conn);
        }
    }
}

fn record_startup_info(conn: &rusqlite::Connection, source: &str, message: &str, details: &str) {
    record_startup_diagnostic(conn, source, message, details, "info");
}

fn record_startup_warning(conn: &rusqlite::Connection, source: &str, message: &str, details: &str) {
    record_startup_diagnostic(conn, source, message, details, "warn");
}

fn record_startup_diagnostic(
    conn: &rusqlite::Connection,
    source: &str,
    message: &str,
    details: &str,
    level: &str,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        source,
        message,
        Some(details.to_string()),
        Some(level.to_string()),
    );
}

#[cfg(test)]
mod recovery_tests {
    use super::*;

    /// A garbage (non-database) file is set aside under a unique timestamped
    /// backup and replaced with a fresh, usable database.
    #[test]
    fn quarantines_a_non_database_file_and_starts_fresh() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("db.sqlite");
        std::fs::write(&path, b"this is definitely not a sqlite database").expect("seed garbage");

        let pool = open_pool_with_recovery(&path).expect("recovery should produce a fresh pool");
        // The fresh DB is real and queryable.
        {
            let conn = pool.writer_result().expect("writer");
            let count: i64 = conn
                .query_row("SELECT count(*) FROM tasks", [], |r| r.get(0))
                .expect("fresh schema has a tasks table");
            assert_eq!(count, 0, "recovered database starts empty");
        }
        drop(pool);

        // The original bytes are preserved under exactly one timestamped backup.
        let backups: Vec<_> = std::fs::read_dir(dir.path())
            .expect("read dir")
            .filter_map(Result::ok)
            .filter(|e| e.file_name().to_string_lossy().contains(".incompatible-"))
            .collect();
        assert_eq!(backups.len(), 1, "expected exactly one quarantined backup");
        let preserved = std::fs::read(backups[0].path()).expect("read backup");
        assert_eq!(preserved, b"this is definitely not a sqlite database");
    }

    /// A valid existing database is reopened in place — never quarantined.
    /// Guards against a false-positive that would silently reset real data.
    #[test]
    fn a_valid_existing_database_is_never_quarantined() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("db.sqlite");

        // First open creates and migrates a real database, then we mark it so a
        // reset would be detectable.
        {
            let pool = open_pool_with_recovery(&path).expect("fresh open");
            let conn = pool.writer_result().expect("writer");
            conn.execute("CREATE TABLE recovery_probe (id INTEGER PRIMARY KEY)", [])
                .expect("create probe table");
        }

        // Reopen through the same path: must reuse the existing DB.
        let pool = open_pool_with_recovery(&path).expect("reopen existing db");
        {
            let conn = pool.writer_result().expect("writer");
            let probe_exists: bool = conn
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='recovery_probe')",
                    [],
                    |r| r.get(0),
                )
                .expect("probe query");
            assert!(probe_exists, "reopen must preserve the existing database");
        }
        drop(pool);

        let backups = std::fs::read_dir(dir.path())
            .expect("read dir")
            .filter_map(Result::ok)
            .filter(|e| e.file_name().to_string_lossy().contains(".incompatible-"))
            .count();
        assert_eq!(backups, 0, "a valid database must never be set aside");
    }

    /// The WAL/SHM sidecars move with the main file so a stale WAL can never be
    /// replayed onto the fresh database.
    #[test]
    fn quarantine_moves_wal_and_shm_sidecars() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("db.sqlite");
        std::fs::write(&path, b"garbage").expect("seed");
        std::fs::write(sidecar_path(&path, "-wal"), b"stale wal").expect("seed wal");
        std::fs::write(sidecar_path(&path, "-shm"), b"stale shm").expect("seed shm");

        let backup = quarantine_incompatible_database(&path).expect("quarantine");

        assert!(backup.exists(), "main file moved to backup");
        assert!(
            sidecar_path(&backup, "-wal").exists(),
            "wal moved alongside"
        );
        assert!(
            sidecar_path(&backup, "-shm").exists(),
            "shm moved alongside"
        );
        assert!(!path.exists(), "original main file no longer present");
        assert!(
            !sidecar_path(&path, "-wal").exists(),
            "stale wal must not be left next to the fresh db"
        );
    }
}
