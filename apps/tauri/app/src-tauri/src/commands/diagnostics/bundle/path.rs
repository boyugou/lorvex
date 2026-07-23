//! Path validation + `.zip` extension append for the diagnostic
//! bundle exporter. Two passes around the extension append: the
//! pre-pass rejects relative / traversing / symlinked input, and
//! the post-pass re-runs the symlink check after `.zip` is
//! appended so an attacker can't pre-create a symlink at
//! `<picked-name>.zip` that the first check would never see. The
//! parent directory is also resolved to a real directory so an
//! absent parent surfaces as a clean validation error instead of
//! a mid-export `File::create` failure.

use std::path::PathBuf;

use crate::error::{AppError, AppResult};

/// Resolve the ZIP output path, appending a `.zip` extension when the
/// caller supplied a bare filename (mirrors the data-snapshot exporter).
///
/// validation runs in two stages around the
/// `.zip`-append step. The first call rejects relative paths, `..`
/// components, and symlinks on the user-supplied input. The second
/// call re-runs the symlink check on the final path *after* the
/// extension is appended — without this, an attacker could pre-create
/// a symlink at `<picked-name>.zip` that the first check never sees,
/// and the bundle write would follow the link to an unintended target.
/// The parent directory is also verified to exist and to be a real
/// directory (not a symlink) so an absent parent surfaces as a clean
/// validation error instead of an opaque `File::create` failure mid-
/// export.
pub(super) fn normalize_zip_path(dest_path: &str) -> AppResult<PathBuf> {
    let trimmed = dest_path.trim();
    if trimmed.is_empty() {
        return Err(AppError::Validation(
            "Destination path cannot be empty".to_string(),
        ));
    }
    let mut path = PathBuf::from(trimmed);
    crate::commands::shared::reject_traversing_or_relative_path(&path, "Diagnostic bundle path")
        .map_err(AppError::Validation)?;
    let needs_extension = path
        .extension()
        .is_none_or(|ext| !ext.eq_ignore_ascii_case("zip"));
    if needs_extension {
        // Append `.zip` without clobbering an existing non-zip
        // extension so `foo.tar` becomes `foo.tar.zip`.
        let mut with_ext = path.into_os_string();
        with_ext.push(".zip");
        path = PathBuf::from(with_ext);
    }
    // re-validate the post-append path so a symlink
    // pre-created at `<picked-name>.zip` is detected even when the
    // user-supplied string was `<picked-name>` (no extension).
    crate::commands::shared::reject_symlinked_path(&path, "Diagnostic bundle path")
        .map_err(AppError::Validation)?;
    // Confirm the parent directory exists and resolves to a real
    // directory. `metadata` (rather than `symlink_metadata`) follows
    // symlinks intentionally — `reject_symlinked_path` above already
    // rejected a symlinked *immediate* parent, so any symlink hit by
    // this resolution is a benign system-level junction (e.g. macOS
    // `/var → /private/var`, where the OS publishes paths under the
    // public name even though the real directory lives elsewhere).
    // Without this existence check, a missing or typo'd folder
    // surfaces as a raw `File::create` error from `write_bundle_zip`
    // after we've already spent CPU + IO building the JSONL bodies.
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            match std::fs::metadata(parent) {
                Ok(meta) => {
                    if !meta.is_dir() {
                        return Err(AppError::Validation(format!(
                            "Diagnostic bundle parent is not a directory: {}",
                            parent.display()
                        )));
                    }
                }
                Err(_) => {
                    return Err(AppError::Validation(format!(
                        "Diagnostic bundle parent directory does not exist: {}",
                        parent.display()
                    )));
                }
            }
        }
    }
    Ok(path)
}
