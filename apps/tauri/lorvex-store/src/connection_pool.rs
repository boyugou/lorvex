//! Unified connection pool for Lorvex runtimes.
//!
//! Owns both the single writer connection (as `Mutex<Connection>`) and a small
//! pool of read-only connections for parallel query serving.
//!
//! WAL mode enables readers to proceed without blocking on the writer, and the
//! writer never contends with itself because the `Mutex` serializes all write
//! access to a single connection.

use rusqlite::Connection;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, TryLockError};

use crate::migration::apply_migrations;
use crate::schema::all_migrations;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Errors that can occur when constructing a [`ConnectionPool`].
#[derive(Debug)]
pub enum PoolError {
    /// The configured read pool size is invalid.
    InvalidReadPoolSize { size: usize },
    /// The database path cannot be represented as UTF-8 for SQLite.
    InvalidPath(std::path::PathBuf),
    /// A pooled connection mutex was poisoned by a panic while held.
    PoisonedLock { lock: &'static str },
    /// Failed to create the parent directory for the database file.
    CreateDir(std::io::Error),
    /// Failed to open a SQLite connection.
    Sqlite(rusqlite::Error),
    /// Failed to apply migrations on the writer connection.
    Migration(crate::migration::MigrationError),
    /// Failed to run store-level startup maintenance.
    Store(crate::error::StoreError),
}

impl std::fmt::Display for PoolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PoolError::InvalidReadPoolSize { size } => {
                write!(f, "read_pool_size must be at least 1, got {size}")
            }
            PoolError::InvalidPath(path) => {
                write!(
                    f,
                    "database path must be valid UTF-8 for SQLite: {}",
                    path.display()
                )
            }
            PoolError::PoisonedLock { lock } => write!(f, "{lock} lock poisoned"),
            PoolError::CreateDir(e) => write!(f, "failed to create db directory: {e}"),
            PoolError::Sqlite(e) => write!(f, "SQLite error: {e}"),
            PoolError::Migration(e) => write!(f, "migration error: {e}"),
            PoolError::Store(e) => write!(f, "store error: {e}"),
        }
    }
}

impl std::error::Error for PoolError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            PoolError::InvalidReadPoolSize { .. }
            | PoolError::InvalidPath(_)
            | PoolError::PoisonedLock { .. } => None,
            PoolError::CreateDir(e) => Some(e),
            PoolError::Sqlite(e) => Some(e),
            PoolError::Migration(e) => Some(e),
            PoolError::Store(e) => Some(e),
        }
    }
}

impl From<rusqlite::Error> for PoolError {
    fn from(e: rusqlite::Error) -> Self {
        PoolError::Sqlite(e)
    }
}

impl From<crate::migration::MigrationError> for PoolError {
    fn from(e: crate::migration::MigrationError) -> Self {
        PoolError::Migration(e)
    }
}

impl From<crate::error::StoreError> for PoolError {
    fn from(e: crate::error::StoreError) -> Self {
        PoolError::Store(e)
    }
}

impl PoolError {
    /// Whether this open failure means the file at the database path is not a
    /// usable Lorvex database — an incompatible schema (`ChecksumMismatch`), a
    /// database written by a newer build (`DowngradeDetected`), corrupt schema
    /// bookkeeping (`CorruptedSchema`), a file that is not a database at all
    /// (`SQLITE_NOTADB`), or a malformed image (`SQLITE_CORRUPT`).
    ///
    /// It is the inverse of "transient / environmental, retry would succeed":
    /// locking, busy, I/O, permissions, an unrepresentable path, a poisoned
    /// lock, and `LockChecksumMismatch` (a build-side error where the schema SQL
    /// was edited without regenerating `checksums.lock`) all return `false` — a
    /// caller must NOT discard the file for those.
    ///
    /// Callers use this to decide whether to quarantine the existing file and
    /// start fresh. Deliberately conservative: anything not positively known to
    /// mean "this file is not a usable database" returns `false`.
    #[must_use]
    pub const fn is_incompatible_database(&self) -> bool {
        use crate::migration::MigrationError as ME;
        match self {
            PoolError::Migration(
                ME::ChecksumMismatch { .. }
                | ME::DowngradeDetected { .. }
                | ME::CorruptedSchema { .. },
            ) => true,
            PoolError::Migration(ME::Sql(e)) | PoolError::Sqlite(e) => {
                is_corrupt_or_not_a_database(e)
            }
            _ => false,
        }
    }
}

/// True only for the SQLite result codes that mean the on-disk bytes are not a
/// readable database: `SQLITE_NOTADB` (wrong magic / encrypted / truncated
/// header) and `SQLITE_CORRUPT` (malformed image). All other SQLite errors
/// (busy, locked, I/O, can't-open, read-only, permission) are transient or
/// environmental and must not trigger discarding the file.
const fn is_corrupt_or_not_a_database(e: &rusqlite::Error) -> bool {
    matches!(
        e,
        rusqlite::Error::SqliteFailure(err, _)
            if matches!(
                err.code,
                rusqlite::ffi::ErrorCode::NotADatabase
                    | rusqlite::ffi::ErrorCode::DatabaseCorrupt
            )
    )
}

// ---------------------------------------------------------------------------
// ConnectionPool
// ---------------------------------------------------------------------------

/// Unified connection model for Lorvex runtimes (Tauri app and MCP server).
///
/// # Writer
///
/// A single read-write connection protected by a `Mutex`. All write operations
/// go through [`ConnectionPool::writer`], which returns a `MutexGuard` that
/// serializes access. This matches SQLite's single-writer constraint.
///
/// # Read pool
///
/// A small pool of read-only connections (opened with
/// `SQLITE_OPEN_READ_ONLY`) serves queries in parallel. WAL mode allows
/// readers to proceed concurrently with the writer.
///
/// # Thread safety
///
/// `ConnectionPool` is `Send + Sync`. The writer is wrapped in a `Mutex`, and
/// each read connection is wrapped in `Arc<Mutex<_>>`.
pub struct ConnectionPool {
    writer: Mutex<Connection>,
    read_pool: Vec<Arc<Mutex<Connection>>>,
    read_index: AtomicUsize,
}

impl std::fmt::Debug for ConnectionPool {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConnectionPool")
            .field("read_pool_size", &self.read_pool.len())
            .field("read_index", &self.read_index.load(Ordering::Relaxed))
            .finish_non_exhaustive()
    }
}

impl ConnectionPool {
    /// Create a new connection pool.
    ///
    /// - `db_path`: path to the SQLite database file. Parent directories are
    ///   created if they do not exist.
    /// - `read_pool_size`: number of read-only connections (2--4 recommended).
    ///
    /// The writer connection has full PRAGMAs and all migrations applied.
    /// Read connections are opened with `SQLITE_OPEN_READ_ONLY`.
    pub fn new(db_path: &Path, read_pool_size: usize) -> Result<Self, PoolError> {
        if read_pool_size == 0 {
            return Err(PoolError::InvalidReadPoolSize {
                size: read_pool_size,
            });
        }
        // #3053 DC5: cap on the upper bound. The MCP server pools 3,
        // the desktop app pools 4; anything past 8 is almost
        // certainly a misconfig (a typo turning `4` into `40`, a
        // future caller copy-pasting a server-class default), and
        // each extra reader is a real SQLite handle eating fds
        // forever. Debug-asserting in dev catches the typo at the
        // call site without a panic in release; production stays
        // tolerant so a weird-but-conscious large value (multi-pane
        // dashboards, future MCP fan-out) still works.
        debug_assert!(
            read_pool_size <= 8,
            "read_pool_size {read_pool_size} is unusually large; expected <=8 \
             (MCP=3, desktop=4 today). Bumping intentionally? Update this assert."
        );

        let db_path_str = db_path
            .to_str()
            .ok_or_else(|| PoolError::InvalidPath(db_path.to_path_buf()))?;

        // Ensure parent directory exists.
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).map_err(PoolError::CreateDir)?;
        }

        // Open the writer connection, apply PRAGMAs and migrations.
        let writer_conn = Connection::open(db_path_str)?;
        apply_writer_pragmas(&writer_conn)?;
        apply_migrations(&writer_conn, &all_migrations())?;
        // align with `open_db_at_path` — the two entry
        // points were drifting. Without these, agent-first installs
        // (MCP binary first) missed self-healing of any
        // maintenance-mode-interrupted FTS trigger state and the
        // markdown-checklist promotion pass.
        crate::connection::reconcile_projections(&writer_conn)?;
        crate::repositories::task::checklist::promote_markdown_task_checklists(&writer_conn)?;

        // Open read-only connections.
        let mut read_conns = Vec::with_capacity(read_pool_size);
        for _ in 0..read_pool_size {
            let conn = Connection::open_with_flags(
                db_path_str,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
                    | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
            )?;
            apply_read_pragmas(&conn)?;
            read_conns.push(Arc::new(Mutex::new(conn)));
        }

        Ok(Self {
            writer: Mutex::new(writer_conn),
            read_pool: read_conns,
            read_index: AtomicUsize::new(0),
        })
    }

    /// Create a fresh in-memory connection pool — for tests only.
    ///
    /// production ConnectionPool tests had
    /// to spin up a `tempfile::TempDir`, write a real WAL/SHM/sqlite
    /// triple, and `unlink` it on Drop. Each round-trip cost ~50 ms
    /// of fs IO before the test even ran a single SQL statement.
    /// The in-memory variant uses a per-call unique URI name with
    /// `vfs=memdb` shared-cache semantics so the writer and read-only
    /// connections all attach to the SAME logical DB without any
    /// tempdir, while staying perfectly isolated from any other test
    /// running in parallel (each gets its own URI nonce).
    ///
    /// **Tests only.** The connection naming scheme is process-local
    /// and not durable; use [`ConnectionPool::new`] for any real
    /// persistence.
    #[cfg(any(test, feature = "test-support"))]
    pub fn new_in_memory(read_pool_size: usize) -> Result<Self, PoolError> {
        use std::sync::atomic::AtomicU64;

        if read_pool_size == 0 {
            return Err(PoolError::InvalidReadPoolSize {
                size: read_pool_size,
            });
        }

        // Per-call unique URI: every pool instance is a fresh,
        // isolated logical DB even when many tests run in parallel.
        // The `mode=memory&cache=shared` knobs make the URI behave
        // like an anonymous in-memory DB whose pages are visible
        // across every connection that opens THIS exact URI string.
        static URI_COUNTER: AtomicU64 = AtomicU64::new(0);
        // `Ordering::Relaxed`
        // is sufficient for the test-pool nonce. Two parallel test
        // threads racing this counter only need uniqueness, not a
        // happens-before with any other state — and the URI itself
        // is the only carrier of the nonce, so SQLite's URI parser
        // is the next observation point. The counter is bumped once
        // per `new_in_memory` call (test-only), so the cost of a
        // stronger ordering would be invisible, but `Relaxed`
        // documents the actual contract.
        let nonce = URI_COUNTER.fetch_add(1, Ordering::Relaxed);
        let pid = std::process::id();
        let uri = format!("file:lorvex-test-{pid}-{nonce}?mode=memory&cache=shared");

        let writer_conn = Connection::open_with_flags(
            &uri,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE
                | rusqlite::OpenFlags::SQLITE_OPEN_CREATE
                | rusqlite::OpenFlags::SQLITE_OPEN_URI,
        )?;
        // The shared in-memory cache has no on-disk file, so
        // `journal_mode = WAL` would silently fall back to MEMORY.
        // Use `apply_standard_pragmas` for parity with the file
        // path; SQLite is tolerant about applying the same PRAGMAs
        // to memdb.
        apply_writer_pragmas(&writer_conn)?;
        apply_migrations(&writer_conn, &all_migrations())?;
        crate::connection::reconcile_projections(&writer_conn)?;
        crate::repositories::task::checklist::promote_markdown_task_checklists(&writer_conn)?;

        let mut read_conns = Vec::with_capacity(read_pool_size);
        for _ in 0..read_pool_size {
            let conn = Connection::open_with_flags(
                &uri,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
                    | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX
                    | rusqlite::OpenFlags::SQLITE_OPEN_URI,
            )?;
            apply_read_pragmas(&conn)?;
            read_conns.push(Arc::new(Mutex::new(conn)));
        }

        Ok(Self {
            writer: Mutex::new(writer_conn),
            read_pool: read_conns,
            read_index: AtomicUsize::new(0),
        })
    }

    /// Lock the writer connection for exclusive write access.
    ///
    /// The returned `MutexGuard` dereferences to `&Connection`. The caller
    /// holds the write lock for the duration of the guard's lifetime, which
    /// serializes all write operations — matching SQLite's single-writer
    /// constraint.
    pub fn writer_result(&self) -> Result<MutexGuard<'_, Connection>, PoolError> {
        self.writer.lock().map_err(|_| PoolError::PoisonedLock {
            lock: "writer connection",
        })
    }

    /// Try to lock the writer connection without blocking.
    ///
    /// Returns `Ok(None)` when another caller already holds the writer. This
    /// is for best-effort diagnostics on paths that must not wait for, or
    /// re-enter, the global writer mutex while returning an error.
    pub fn try_writer_result(&self) -> Result<Option<MutexGuard<'_, Connection>>, PoolError> {
        match self.writer.try_lock() {
            Ok(guard) => Ok(Some(guard)),
            Err(TryLockError::WouldBlock) => Ok(None),
            Err(TryLockError::Poisoned(_)) => Err(PoolError::PoisonedLock {
                lock: "writer connection",
            }),
        }
    }

    /// Convenience wrapper that panics on poisoned lock.
    /// Test-only — production code must use `writer_result()`.
    #[cfg(test)]
    pub fn writer(&self) -> MutexGuard<'_, Connection> {
        self.writer_result()
            .expect("writer connection lock poisoned")
    }

    /// Get a read-only connection handle from the pool (round-robin).
    ///
    /// The returned `Arc<Mutex<Connection>>` can be locked and used for
    /// queries. Useful when the pool is behind `Arc` and the caller needs
    /// an owned handle. The caller must not attempt write operations on it
    /// — the connection is opened with `SQLITE_OPEN_READ_ONLY`.
    pub fn read(&self) -> Arc<Mutex<Connection>> {
        // `Ordering::Relaxed`
        // is the right contract for round-robin slot picking. The
        // counter is private to the pool, no other state's
        // visibility hangs off this load, and the only invariant we
        // need is "two concurrent callers don't both observe the
        // same `idx` and serialize on the same `Mutex`." Atomicity
        // alone provides that — every `Ordering` variant satisfies
        // it. A stronger ordering would just emit fences on a
        // hot-path counter that is read once per query.
        let idx = self.read_index.fetch_add(1, Ordering::Relaxed) % self.read_pool.len();
        Arc::clone(&self.read_pool[idx])
    }

    /// Lock a read-only connection from the pool (round-robin) and return
    /// a `MutexGuard` that borrows from the pool.
    ///
    /// This is the preferred accessor when the pool itself has a sufficient
    /// lifetime (e.g., `&'static ConnectionPool` from a `OnceLock`). The
    /// returned guard dereferences to `&Connection`.
    pub fn read_lock_result(&self) -> Result<MutexGuard<'_, Connection>, PoolError> {
        let idx = self.read_index.fetch_add(1, Ordering::Relaxed) % self.read_pool.len();
        self.read_pool[idx]
            .lock()
            .map_err(|_| PoolError::PoisonedLock {
                lock: "read connection",
            })
    }

    /// Convenience wrapper that panics on poisoned lock.
    /// Test-only — production code must use `read_lock_result()`.
    #[cfg(test)]
    pub fn read_lock(&self) -> MutexGuard<'_, Connection> {
        self.read_lock_result()
            .expect("read connection lock poisoned")
    }

    /// Apply a callback to every read-pool connection.
    ///
    /// Primarily useful for installing per-connection hooks (e.g.
    /// SQLite authorizers in tests). Authorizers are per-connection,
    /// not per-database, so this helper ensures every read
    /// connection is covered.
    ///
    /// **Intended for tests only** — the typed
    /// [`PoolError::PoisonedLock`] error surfaces a poisoned mutex
    /// rather than panicking. Production code should use
    /// `read_lock_result()` directly on a single connection rather
    /// than fan-out to every member of the pool.
    ///
    /// the previous shape `.expect("read connection
    /// lock poisoned")` panicked on the first poisoned mutex, which
    /// poisoned every other read connection in a domino — a single
    /// test-setup panic could cascade and brick the whole pool
    /// during a CI run. The `try_` prefix marks the fallible variant;
    /// returning a Result lets the caller decide (skip, abort, or
    /// recover) and stops the cascade.
    pub fn try_for_each_read_conn(&self, f: impl Fn(&Connection)) -> Result<(), PoolError> {
        for arc in &self.read_pool {
            let guard = arc.lock().map_err(|_| PoolError::PoisonedLock {
                lock: "read connection",
            })?;
            f(&guard);
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// PRAGMA helpers
// ---------------------------------------------------------------------------

/// Apply PRAGMAs for the read-write writer connection.
///
/// Delegate to `apply_standard_pragmas` so the writer paths stay
/// aligned. `ConnectionPool` is the writer path for the MCP server
/// (whereas `open_db_at_path` is the Tauri-app path); a hand-rolled
/// PRAGMA block here would risk omitting `auto_vacuum = INCREMENTAL`
/// and `temp_store = MEMORY`, leaving agent-first installs that
/// first open the DB via the MCP binary with a non-incremental-
/// vacuum file.
fn apply_writer_pragmas(conn: &Connection) -> Result<(), rusqlite::Error> {
    crate::connection::apply_standard_pragmas(conn)
}

/// Apply PRAGMAs for read-only pool connections.
///
/// Read connections use `query_only = ON` as a safety net (SQLite will reject
/// writes even though the connection is opened read-only). A smaller cache
/// is sufficient since reads are typically short-lived queries.
///
/// `temp_store = MEMORY` keeps every per-connection
/// transient B-tree (the kind SQLite materializes for `ORDER BY`,
/// `GROUP BY`, large `IN`-list expansions, intermediate joins, …) in
/// RAM rather than spilling to a file in the system temp directory.
/// The writer connection inherits this via `apply_standard_pragmas`,
/// but read connections fall through to SQLite's default of
/// "file-backed when over a small threshold" — every paginated task
/// list / search / changelog read on the read pool was therefore
/// liable to round-trip through disk for sort buffers. Standardize
/// the read pool to in-memory temp tables so read latency is bounded
/// by RAM, not by tmpfs/sandboxed temp paths.
fn apply_read_pragmas(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        "PRAGMA query_only = ON;
         PRAGMA busy_timeout = 5000;
         PRAGMA cache_size = -4096;
         PRAGMA temp_store = MEMORY;",
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
