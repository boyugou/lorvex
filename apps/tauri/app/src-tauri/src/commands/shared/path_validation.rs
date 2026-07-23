//! Shared path-validation helpers for IPC command boundaries.
//!
//! Legitimate IPC paths come from native file dialogs that return
//! canonicalized absolute paths. Rejecting relative or traversing
//! inputs at the command boundary turns frontend bugs and malformed
//! IPC calls into clean errors instead of writes/reads at unintended
//! locations.

use std::path::{Component, Path};

/// Reject paths containing `..` *path components*.
///
/// Component-aware so legitimate names like `My..Project` or
/// `foo..bar.txt` (substrings of `..` inside a name) pass through.
/// Only a `Component::ParentDir` segment that walks up the tree
/// fails.
pub(crate) fn reject_path_traversal(path: &Path, kind: &str) -> Result<(), String> {
    for component in path.components() {
        if matches!(component, Component::ParentDir) {
            return Err(format!("{kind} must not contain '..' components"));
        }
    }
    Ok(())
}

/// Reject relative paths in addition to `..` components.
pub(crate) fn reject_traversing_or_relative_path(path: &Path, kind: &str) -> Result<(), String> {
    if !path.is_absolute() {
        return Err(format!(
            "{kind} must be absolute — use the file dialog to pick a location"
        ));
    }
    reject_path_traversal(path, kind)?;
    reject_symlinked_path(path, kind)
}

/// reject paths whose target file (if it already exists)
/// or whose immediate parent directory is a symbolic link.
///
/// `reject_traversing_or_relative_path` defeats `..` traversal at the
/// component level, but a parent directory replaced by a symlink can
/// still redirect a write to a location the user did not pick — for
/// example, a malicious app that pre-creates `~/Documents/Lorvex →
/// /tmp/attacker` would have us write a snapshot or diagnostic bundle
/// into `/tmp/attacker` even though every component check passes. We
/// use `symlink_metadata` (rather than `metadata`) because it does
/// NOT follow the link, so we can detect that the entry itself is a
/// symlink.
///
/// Scope: we deliberately check the target plus its immediate parent
/// rather than walking every ancestor. macOS routes `/tmp` and `/var`
/// through `/private/...` symlinks at the system level; a blanket
/// ancestor walk would refuse every legitimate save-dialog
/// destination on those platforms. The audit's attack model is a
/// user-writable directory replaced by a symlink — the directory the
/// user sees in the dialog — so checking only the target and its
/// direct parent captures that without breaking the platform's
/// standard layout. A path whose components don't yet exist (a
/// brand-new destination) returns `Ok(())` — there's nothing to
/// check, and the write itself will surface any later error.
pub(crate) fn reject_symlinked_path(path: &Path, kind: &str) -> Result<(), String> {
    // Check the target itself: if it already exists as a symlink, the
    // write would follow the link and clobber whatever it points at.
    if let Ok(meta) = std::fs::symlink_metadata(path) {
        if meta.file_type().is_symlink() {
            return Err(format!(
                "{kind} resolves through a symbolic link — pick a real file location"
            ));
        }
    }
    // Check the immediate parent. The user picked this directory via
    // the native save dialog, so a symlinked parent here is the
    // attack signal — an attacker who can pre-create a symlink in a
    // user-writable location targets the directory the user sees,
    // not a system-level junction higher up.
    if let Some(parent) = path.parent() {
        if let Ok(meta) = std::fs::symlink_metadata(parent) {
            if meta.file_type().is_symlink() {
                return Err(format!(
                    "{kind} contains a symbolic-link directory — pick a real folder"
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_target_that_is_a_symlink() {
        // a destination path that already exists as a
        // symlink must be rejected so we don't follow the link to an
        // unintended location.
        let temp = std::env::temp_dir();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let real = temp.join(format!("lorvex-pathval-real-{nanos}.txt"));
        let link = temp.join(format!("lorvex-pathval-link-{nanos}.txt"));
        std::fs::write(&real, b"target").expect("seed real file");
        #[cfg(unix)]
        std::os::unix::fs::symlink(&real, &link).expect("create symlink");
        #[cfg(windows)]
        std::os::windows::fs::symlink_file(&real, &link).expect("create symlink");

        let err = reject_symlinked_path(&link, "Test path")
            .expect_err("symlinked target must be rejected");
        assert!(
            err.contains("symbolic link"),
            "error must mention symlink, got: {err}"
        );

        let _ = std::fs::remove_file(&link);
        let _ = std::fs::remove_file(&real);
    }

    #[test]
    fn accepts_nonexistent_path_with_real_parent() {
        // A path that doesn't exist yet but whose parent is a real
        // directory must pass — that's the normal "save dialog gave us
        // a new filename" case.
        let temp = std::env::temp_dir();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let target = temp.join(format!("lorvex-pathval-fresh-{nanos}.txt"));
        assert!(reject_symlinked_path(&target, "Test path").is_ok());
    }

    #[test]
    fn rejects_path_whose_parent_is_a_symlink() {
        // Even if the file itself doesn't exist yet, a symlinked
        // *parent* would redirect the write to the link target.
        let temp = std::env::temp_dir();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let real_dir = temp.join(format!("lorvex-pathval-real-dir-{nanos}"));
        let link_dir = temp.join(format!("lorvex-pathval-link-dir-{nanos}"));
        std::fs::create_dir(&real_dir).expect("create real dir");
        #[cfg(unix)]
        std::os::unix::fs::symlink(&real_dir, &link_dir).expect("create dir symlink");
        #[cfg(windows)]
        std::os::windows::fs::symlink_dir(&real_dir, &link_dir).expect("create dir symlink");

        let target = link_dir.join("inside.txt");
        let err = reject_symlinked_path(&target, "Test path")
            .expect_err("symlinked parent must be rejected");
        assert!(err.contains("symbolic-link directory"), "got: {err}");

        let _ = std::fs::remove_dir(&link_dir);
        let _ = std::fs::remove_dir(&real_dir);
    }
}
