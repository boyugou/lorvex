//! Windows-specific helpers: UNC / network-share path detection
//! (rejected at the locator boundary because SQLite WAL mode is unsafe
//! over SMB).

/// detect Windows UNC / network share paths in either
/// backslash (`\\server\share\db.sqlite`) or forward-slash
/// (`//server/share/db.sqlite`) form. SQLite WAL mode is unsafe over
/// SMB, and silently locking a network DB risks corrupting the WAL log
/// for every other client.
///
/// #3051 M5: the backslash arm runs on every platform — a UNC-style
/// override surfaced from a cross-platform deployment script should be
/// rejected uniformly so the failure mode is identical across `lorvex`
/// invocations on every OS. The forward-slash arm, however, is gated
/// to Windows: on Unix, `//Volumes/Data/db.sqlite` is a valid POSIX
/// path with a (collapsing) double-slash root, NOT a UNC reference.
/// A cross-platform `//` reject would block legitimate Unix paths
/// whose first segment happens to start with a duplicate separator.
pub(super) fn is_windows_unc_path(path: &str) -> bool {
    let bytes = path.as_bytes();
    if bytes.len() < 2 {
        return false;
    }
    if bytes.starts_with(b"\\\\") {
        return true;
    }
    #[cfg(target_os = "windows")]
    {
        if bytes.starts_with(b"//") {
            return true;
        }
    }
    false
}
