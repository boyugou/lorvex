use std::fs::{self, File, OpenOptions};
use std::io::{Error, ErrorKind, Result};
use std::path::Path;

/// Create the deterministic export temp file without following a planted
/// symlink at `<output>.zip.tmp`.
///
/// A stale regular temp file from a crashed prior export is safe to remove.
/// Any other existing entry is rejected. `create_new(true)` closes the race
/// after that cleanup: if another process plants a symlink before open, the
/// open fails instead of truncating the symlink target.
pub(super) fn create_export_temp_file(path: &Path) -> Result<File> {
    match fs::symlink_metadata(path) {
        Ok(meta) => {
            if meta.file_type().is_symlink() {
                return Err(Error::new(
                    ErrorKind::AlreadyExists,
                    format!("export temp path is a symbolic link: {}", path.display()),
                ));
            }
            if meta.file_type().is_file() {
                fs::remove_file(path)?;
            } else {
                return Err(Error::new(
                    ErrorKind::AlreadyExists,
                    format!(
                        "export temp path already exists and is not a regular file: {}",
                        path.display()
                    ),
                ));
            }
        }
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }

    OpenOptions::new().write(true).create_new(true).open(path)
}

/// RAII guard that deletes a filesystem path on drop unless `disarm()` was
/// called. The export paths create a `.zip.tmp` then fail via
/// one of dozens of `?` branches, leaking the temp file forever. This guard
/// wraps the temp-file lifetime so the drop always runs (panic or error
/// unwind or early return), and the successful rename calls `disarm()` to
/// keep the renamed-to file. Ignoring `remove_file` errors is intentional —
/// the filesystem may already have reclaimed the inode on some error
/// paths, and secondary failures during cleanup are not actionable.
pub(super) struct TempFileGuard<'a> {
    path: &'a Path,
    armed: bool,
}

impl<'a> TempFileGuard<'a> {
    pub(super) const fn new(path: &'a Path) -> Self {
        Self { path, armed: true }
    }

    pub(super) const fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for TempFileGuard<'_> {
    fn drop(&mut self) {
        if self.armed {
            let _ = std::fs::remove_file(self.path);
        }
    }
}
