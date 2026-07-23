//! Filesystem durability helpers for atomic rename protocols.
//!
//! Writing file bytes and calling `File::sync_all()` only makes the file
//! contents durable. Atomic rename protocols also need the parent directory
//! entry to reach stable storage on Unix filesystems; otherwise a crash after
//! `rename(temp, final)` can leave the renamed file inaccessible by name.
//! Windows keeps this as an explicit no-op because the OS owns metadata
//! durability for rename targets there.

use std::path::Path;

#[cfg(test)]
use std::sync::atomic::{AtomicUsize, Ordering};

#[cfg(test)]
static FSYNC_DIR_CALLS: AtomicUsize = AtomicUsize::new(0);

#[cfg(test)]
fn note_fsync_dir_call() {
    FSYNC_DIR_CALLS.fetch_add(1, Ordering::AcqRel);
}

#[cfg(not(test))]
const fn note_fsync_dir_call() {}

/// Fsync a directory entry container on Unix; no-op on non-Unix platforms.
#[cfg(unix)]
pub(crate) fn fsync_dir(dir: &Path) -> std::io::Result<()> {
    note_fsync_dir_call();
    std::fs::File::open(dir).and_then(|d| d.sync_all())
}

/// Fsync a directory entry container on Unix; no-op on non-Unix platforms.
#[cfg(not(unix))]
pub(crate) fn fsync_dir(_dir: &Path) -> std::io::Result<()> {
    note_fsync_dir_call();
    Ok(())
}

/// Fsync the directory containing `path`.
pub(crate) fn fsync_parent_dir(path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fsync_dir(parent)?;
    }
    Ok(())
}
