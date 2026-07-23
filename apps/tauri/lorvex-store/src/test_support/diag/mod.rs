//! Rich diagnostics for test-DB setup.
//!
//! Background — issue #2544. CI runners occasionally fail with an opaque
//! `rusqlite::Error("disk I/O error")` or `io::Error("Permission denied")`
//! when /tmp is full, mounted `noexec`, or owned by another user. The
//! stock `tempfile::tempdir()` + `Connection::open()` call stack hides
//! all the context that would let an engineer distinguish "bad test"
//! from "bad runner": free disk, whether the path is actually writable,
//! the errno, and where the playbook lives.
//!
//! This module exposes:
//! - [`open_test_db_with_diag`]: the in-memory DB helper — byte-identical
//!   happy-path behaviour versus [`crate::open_db_in_memory`], plus a
//!   [`DiagContext`] returned alongside the connection so callers that
//!   want to log "test setup inspected path X, had Y bytes free" can do so.
//! - [`open_test_db_at_temp_path_with_diag`]: an on-disk temp-DB variant
//!   for tests that exercise the path-based DB opener.
//! - [`unique_test_dir_with_diag`]: the non-DB counterpart for tests that
//!   write plain files (export fixtures, etc).
//! - [`probe_writability`] / [`free_bytes_at`]: standalone helpers the
//!   `app/src-tauri` `unique_test_dir` path can call to surface the same
//!   diagnostic when filesystem fixtures (not DBs) fail.
//! - [`TestSetupError`]: the rich error type. Its `Display` impl is the
//!   thing a flaky-CI log should contain.
//!
//! Fault injection — tests use the [`fault`] submodule (thread-locals) to
//! simulate ENOSPC / EACCES without actually filling the disk or changing
//! permissions. The whole `diag` module is itself gated behind the
//! `test-support` feature (or `#[cfg(test)]` inside this crate), so none
//! of this reaches a production binary.

use rusqlite::Connection;
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::connection::open_db_at_path;

/// Pointer to the durable playbook. Kept in code so the error message
/// can't drift out of sync with a renamed doc.
pub const PLAYBOOK_POINTER: &str = "docs/execution/TEST_FLAKINESS.md";

/// Outcome of the writability probe — a touch+remove of a 1-byte file.
#[derive(Debug, Clone)]
pub enum WritabilityProbe {
    /// The probe succeeded; path is writable.
    Writable,
    /// The probe failed. Holds the errno string for log legibility.
    Rejected { reason: String },
    /// The parent directory didn't exist, so no probe was attempted.
    PathAbsent,
}

impl fmt::Display for WritabilityProbe {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WritabilityProbe::Writable => write!(f, "writable"),
            WritabilityProbe::Rejected { reason } => write!(f, "rejected ({reason})"),
            WritabilityProbe::PathAbsent => write!(f, "path absent"),
        }
    }
}

/// Context gathered at the moment of a test-setup attempt. Always
/// produced — success or failure — so a passing test can still log
/// "we used /tmp, 42 GB free" if something nearby regresses.
#[derive(Debug, Clone)]
pub struct DiagContext {
    /// The exact path the helper tried (DB file for on-disk, sentinel
    /// `<in-memory>` marker for [`open_test_db_with_diag`]).
    pub attempted_path: PathBuf,
    /// Free bytes reported for the filesystem backing the path's parent,
    /// or `None` if the platform-specific probe failed (Windows stub,
    /// missing parent, etc).
    pub free_bytes: Option<u64>,
    /// Touch-probe outcome. Cheap (one create + one remove) but skipped
    /// on the happy path — see [`open_test_db_with_diag`] for when it runs.
    pub writability: WritabilityProbe,
    /// Value of `$TMPDIR` / `std::env::temp_dir()` at attempt time — useful
    /// for spotting CI overrides that point at a slow NFS mount.
    pub tmpdir: PathBuf,
}

impl fmt::Display for DiagContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "path={}, tmpdir={}, free_bytes={}, writability={}",
            self.attempted_path.display(),
            self.tmpdir.display(),
            self.free_bytes
                .map_or_else(|| "<unavailable>".to_string(), |n| format!("{n}")),
            self.writability,
        )
    }
}

/// Error returned when test-DB setup fails. `Display` intentionally
/// renders everything a CI debugger needs on one line, then references
/// the playbook for the long-form remediation steps.
#[derive(Debug)]
pub struct TestSetupError {
    pub kind: TestSetupErrorKind,
    pub context: DiagContext,
}

/// What went wrong, as distinct variants so matchers in tests can
/// assert on the class of failure without string-sniffing.
#[derive(Debug)]
pub enum TestSetupErrorKind {
    /// Couldn't create the parent directory for the temp DB.
    CreateParent(io::Error),
    /// The writability probe failed — we refuse to go further.
    NotWritable(io::Error),
    /// SQLite-level failure opening the connection or applying PRAGMAs/migrations.
    OpenDb(crate::connection::OpenError),
}

impl fmt::Display for TestSetupError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (label, inner): (&str, String) = match &self.kind {
            TestSetupErrorKind::CreateParent(e) => (
                "test-setup: failed to create parent directory",
                format!("{e} (errno: {:?})", e.raw_os_error()),
            ),
            TestSetupErrorKind::NotWritable(e) => (
                "test-setup: temp path not writable",
                format!("{e} (errno: {:?})", e.raw_os_error()),
            ),
            TestSetupErrorKind::OpenDb(e) => ("test-setup: open_db failed", format!("{e}")),
        };
        write!(
            f,
            "{label}: {inner} | context: {ctx} | see {playbook}",
            ctx = self.context,
            playbook = PLAYBOOK_POINTER,
        )
    }
}

impl std::error::Error for TestSetupError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match &self.kind {
            TestSetupErrorKind::CreateParent(e) | TestSetupErrorKind::NotWritable(e) => Some(e),
            TestSetupErrorKind::OpenDb(e) => Some(e),
        }
    }
}

/// In-memory test DB with diagnostics. Happy-path cost is one extra
/// struct allocation (the `DiagContext`) — no syscalls, no probes — so
/// the hot test loop stays fast.
///
/// On `Err`, the [`TestSetupError`] carries a writability probe against
/// `$TMPDIR` (where an on-disk retry would land) and the free-space read,
/// so the failure report is identical whether the test uses this helper
/// or [`open_test_db_at_temp_path_with_diag`].
// `TestSetupError` carries a nested `OpenError` chain that can be large;
// clippy's `result_large_err` threshold flags the raw form. Box it so
// the hot happy path only pays for a pointer-sized `Err` discriminant.
pub type TestSetupResult<T> = Result<T, Box<TestSetupError>>;

pub fn open_test_db_with_diag() -> TestSetupResult<(Connection, DiagContext)> {
    let tmpdir = std::env::temp_dir();
    match crate::open_db_in_memory() {
        Ok(conn) => {
            let context = DiagContext {
                attempted_path: PathBuf::from("<in-memory>"),
                free_bytes: free_bytes_at(&tmpdir),
                writability: WritabilityProbe::Writable, // in-memory can't reject
                tmpdir: tmpdir.clone(),
            };
            Ok((conn, context))
        }
        Err(e) => {
            // Only now do we pay for the diagnostic probes — the in-memory
            // path already failed, so the test run is doomed; spending a
            // few syscalls to explain why is worth it.
            let context = DiagContext {
                attempted_path: PathBuf::from("<in-memory>"),
                free_bytes: free_bytes_at(&tmpdir),
                writability: probe_writability(&tmpdir),
                tmpdir,
            };
            Err(Box::new(TestSetupError {
                kind: TestSetupErrorKind::OpenDb(e),
                context,
            }))
        }
    }
}

/// On-disk temp-DB variant — used by tests that need a real SQLite file
/// path (WAL tests, path-based opener tests, widget-snapshot persistence).
///
/// Caller passes a `prefix` that's incorporated into the unique path,
/// e.g. `"widget-snapshot"` yields `<tmpdir>/lorvex-tests/widget-snapshot-<nanos>/db.sqlite`.
pub fn open_test_db_at_temp_path_with_diag(
    prefix: &str,
) -> TestSetupResult<(Connection, PathBuf, DiagContext)> {
    let (db_path, _dir) = match allocate_temp_path(prefix, "db.sqlite") {
        Ok(p) => p,
        Err((e, attempted_path)) => {
            let tmpdir = std::env::temp_dir();
            let context = DiagContext {
                free_bytes: free_bytes_at(&tmpdir),
                writability: probe_writability(&tmpdir),
                attempted_path,
                tmpdir,
            };
            return Err(Box::new(TestSetupError {
                kind: TestSetupErrorKind::CreateParent(e),
                context,
            }));
        }
    };

    // Run the writability probe against the parent before calling into
    // rusqlite — a crisp "not writable" is more useful than "disk I/O error".
    let probe = probe_writability(db_path.parent().unwrap_or(&db_path));
    if let WritabilityProbe::Rejected { reason } = &probe {
        let tmpdir = std::env::temp_dir();
        let context = DiagContext {
            free_bytes: free_bytes_at(db_path.parent().unwrap_or(&tmpdir)),
            writability: probe.clone(),
            attempted_path: db_path,
            tmpdir,
        };
        return Err(Box::new(TestSetupError {
            kind: TestSetupErrorKind::NotWritable(io::Error::new(
                io::ErrorKind::PermissionDenied,
                reason.clone(),
            )),
            context,
        }));
    }

    match open_db_at_path(&db_path) {
        Ok(conn) => {
            let tmpdir = std::env::temp_dir();
            let context = DiagContext {
                free_bytes: free_bytes_at(db_path.parent().unwrap_or(&tmpdir)),
                writability: probe,
                attempted_path: db_path.clone(),
                tmpdir,
            };
            Ok((conn, db_path, context))
        }
        Err(e) => {
            let tmpdir = std::env::temp_dir();
            let context = DiagContext {
                free_bytes: free_bytes_at(db_path.parent().unwrap_or(&tmpdir)),
                writability: probe,
                attempted_path: db_path,
                tmpdir,
            };
            Err(Box::new(TestSetupError {
                kind: TestSetupErrorKind::OpenDb(e),
                context,
            }))
        }
    }
}

/// Allocate a unique filesystem directory for a test fixture and return
/// it alongside a [`DiagContext`]. This is the non-DB counterpart of
/// [`open_test_db_at_temp_path_with_diag`] — used by tests that write plain
/// files (not SQLite).
///
/// If allocation or the writability probe fails, the returned
/// [`TestSetupError`] carries the same rich context as the DB helpers,
/// so CI logs stay consistent across failure modes.
pub fn unique_test_dir_with_diag(prefix: &str) -> TestSetupResult<(PathBuf, DiagContext)> {
    let tmpdir = std::env::temp_dir();
    let (_file_sentinel, dir) = match allocate_temp_path(prefix, ".sentinel") {
        Ok(paths) => paths,
        Err((e, attempted_path)) => {
            let context = DiagContext {
                free_bytes: free_bytes_at(&tmpdir),
                writability: probe_writability(&tmpdir),
                attempted_path,
                tmpdir,
            };
            return Err(Box::new(TestSetupError {
                kind: TestSetupErrorKind::CreateParent(e),
                context,
            }));
        }
    };

    let probe = probe_writability(&dir);
    let context = DiagContext {
        free_bytes: free_bytes_at(&dir),
        writability: probe.clone(),
        attempted_path: dir.clone(),
        tmpdir,
    };

    if let WritabilityProbe::Rejected { reason } = probe {
        return Err(Box::new(TestSetupError {
            kind: TestSetupErrorKind::NotWritable(io::Error::new(
                io::ErrorKind::PermissionDenied,
                reason,
            )),
            context,
        }));
    }

    Ok((dir, context))
}

/// Touch-probe a path: create a 1-byte file, remove it, return the result.
pub fn probe_writability(path: &Path) -> WritabilityProbe {
    if let Some(forced) = fault::current_writability_override() {
        return forced;
    }

    if !path.exists() {
        return WritabilityProbe::PathAbsent;
    }
    let probe = path.join(".lorvex-write-probe");
    match fs::write(&probe, b"x") {
        Ok(()) => {
            let _ = fs::remove_file(&probe);
            WritabilityProbe::Writable
        }
        Err(e) => WritabilityProbe::Rejected {
            reason: format!("{e} (errno: {:?})", e.raw_os_error()),
        },
    }
}

/// Return free bytes available on the filesystem backing `path`, or
/// `None` if the platform probe fails or isn't implemented.
pub fn free_bytes_at(path: &Path) -> Option<u64> {
    if let Some(forced) = fault::current_free_bytes_override() {
        return forced;
    }

    free_bytes_impl(path)
}

#[cfg(unix)]
fn free_bytes_impl(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;

    let c_path = CString::new(path.as_os_str().as_bytes()).ok()?;
    // SAFETY: `statvfs` writes into a zero-initialized struct; we hand
    // it a valid C string and a pointer to our own stack slot.
    unsafe {
        let mut stat: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c_path.as_ptr(), &mut stat) != 0 {
            return None;
        }
        // `f_bavail` is non-privileged available blocks.
        Some((stat.f_bavail as u64).saturating_mul(stat.f_frsize as u64))
    }
}

#[cfg(windows)]
fn free_bytes_impl(_path: &Path) -> Option<u64> {
    // Intentional stub — a Windows implementation would call
    // `GetDiskFreeSpaceExW`, which would pull the `windows` crate into
    // the test graph. Revisit if a Windows plain-file fixture needs this.
    None
}

#[cfg(not(any(unix, windows)))]
fn free_bytes_impl(_path: &Path) -> Option<u64> {
    None
}

/// Allocate a unique temp path rooted under `<tmpdir>/lorvex-tests/`.
/// Returns `(file_path, dir_path)` on success; on failure, returns
/// the underlying `io::Error` plus the path we were trying to create
/// so the caller can surface it in `DiagContext`.
fn allocate_temp_path(
    prefix: &str,
    filename: &str,
) -> Result<(PathBuf, PathBuf), (io::Error, PathBuf)> {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    let dir = std::env::temp_dir()
        .join("lorvex-tests")
        .join(format!("{prefix}-{nanos}"));
    if let Err(e) = fs::create_dir_all(&dir) {
        return Err((e, dir));
    }
    let file = dir.join(filename);
    Ok((file, dir))
}

// ---------------------------------------------------------------------------
// Fault injection
// ---------------------------------------------------------------------------

pub mod fault {
    //! Thread-local overrides for [`super::probe_writability`] /
    //! [`super::free_bytes_at`].
    //!
    //! The whole `diag` module is itself gated behind the `test-support`
    //! feature (or `#[cfg(test)]` inside this crate), so these hooks never
    //! reach a production binary. Using thread-locals (not globals) means
    //! parallel tests can each inject their own failure without cross-talk.
    use super::WritabilityProbe;
    use std::cell::RefCell;

    thread_local! {
        static WRITABILITY: RefCell<Option<WritabilityProbe>> = const { RefCell::new(None) };
        static FREE_BYTES: RefCell<Option<Option<u64>>> = const { RefCell::new(None) };
    }

    pub(super) fn current_writability_override() -> Option<WritabilityProbe> {
        WRITABILITY.with(|cell| cell.borrow().clone())
    }

    pub(super) fn current_free_bytes_override() -> Option<Option<u64>> {
        FREE_BYTES.with(|cell| *cell.borrow())
    }

    /// RAII guard that forces [`super::probe_writability`] to return a
    /// specific outcome on the current thread. Dropping the guard
    /// restores the previous value.
    pub struct WritabilityGuard {
        prev: Option<WritabilityProbe>,
    }

    impl WritabilityGuard {
        pub fn new(outcome: WritabilityProbe) -> Self {
            let prev = WRITABILITY.with(|cell| cell.replace(Some(outcome)));
            Self { prev }
        }
    }

    impl Drop for WritabilityGuard {
        fn drop(&mut self) {
            WRITABILITY.with(|cell| *cell.borrow_mut() = self.prev.take());
        }
    }

    /// RAII guard for the free-bytes return value. The outer `Option`
    /// is whether we override at all; the inner is what the override
    /// returns (allowing `Some(0)` for "disk full" and `None` for
    /// "platform probe unavailable").
    pub struct FreeBytesGuard {
        prev: Option<Option<u64>>,
    }

    impl FreeBytesGuard {
        pub fn new(value: Option<u64>) -> Self {
            let prev = FREE_BYTES.with(|cell| cell.replace(Some(value)));
            Self { prev }
        }
    }

    impl Drop for FreeBytesGuard {
        fn drop(&mut self) {
            FREE_BYTES.with(|cell| *cell.borrow_mut() = self.prev.take());
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
