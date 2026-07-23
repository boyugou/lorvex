//! Public entry points and the core resolver pipeline.
//!
//! Precedence order (first match wins):
//!   1. `DB_PATH` env override (gated in release builds; UNC rejected)
//!   2. Platform default (`dirs::data_dir().join("Lorvex/db.sqlite")`)
//!   3. Home fallback (`~/.local/share/Lorvex/db.sqlite`)

use std::path::{Path, PathBuf};

use super::diagnostics_queue::{
    enqueue_db_location_diagnostics, take_db_location_diagnostics_inner,
};
use super::env::current_db_path_env_resolution;
use super::platform_windows::is_windows_unc_path;
use super::types::{
    DbLocationDetails, DbLocationDiagnostic, DbLocationDiagnosticCode, DbPathSource,
};
use super::{DB_FILE, LORVEX_DIR};

pub fn resolve_db_path() -> PathBuf {
    let details = resolve_db_location_details();
    enqueue_db_location_diagnostics(details.diagnostics);
    details.resolved_path
}

pub fn resolve_db_location_details() -> DbLocationDetails {
    let env = current_db_path_env_resolution();
    resolve_db_location_details_with_diagnostics(
        env.db_path.as_deref(),
        dirs::data_dir().as_deref(),
        dirs::home_dir().as_deref(),
        path_has_nonempty_db,
        env.diagnostics,
    )
}

pub fn take_db_location_diagnostics() -> Vec<DbLocationDiagnostic> {
    take_db_location_diagnostics_inner()
}

#[cfg(test)]
pub(super) fn resolve_db_location_details_with(
    db_path_env: Option<&str>,
    data_dir: Option<PathBuf>,
    home_dir: Option<PathBuf>,
    // Kept for legacy tests at this boundary; normal runtime resolution no
    // longer probes retired macOS App Store container paths.
    _db_exists_at: fn(&Path) -> bool,
) -> DbLocationDetails {
    resolve_db_location_details_with_diagnostics(
        db_path_env,
        data_dir.as_deref(),
        home_dir.as_deref(),
        _db_exists_at,
        Vec::new(),
    )
}

fn resolve_db_location_details_with_diagnostics(
    db_path_env: Option<&str>,
    data_dir: Option<&Path>,
    home_dir: Option<&Path>,
    _db_exists_at: fn(&Path) -> bool,
    mut diagnostics: Vec<DbLocationDiagnostic>,
) -> DbLocationDetails {
    // on Windows the DB lives at
    //   `%APPDATA%\Roaming\Lorvex\db.sqlite`
    // (this branch — `dirs::data_dir().join(LORVEX_DIR)`), whereas the
    // Tauri WebView2 user-data directory and most plugin storage live
    // under `%APPDATA%\Roaming\com.lorvex.planner\…` (the bundle id).
    // This is a deliberate split, NOT a bug:
    //
    //   1. The DB is the single source of truth and must outlive
    //      Tauri/WebView2 reinstalls — pinning it under the friendly
    //      `Lorvex` directory keeps it stable across Tauri version
    //      upgrades that have historically renamed the bundle-id dir.
    //   2. WebView2 storage is per-Tauri-config and can be wiped on
    //      schema migrations; the DB cannot.
    //   3. Folder Redirection (Group Policy) typically redirects
    //      `%APPDATA%\Roaming` as a whole, so both directories ride
    //      the same redirect target — the split does not strand state
    //      on a redirected system.
    //
    let platform_default_path = {
        let base: PathBuf = data_dir.map_or_else(
            || {
                home_dir
                    .map_or_else(|| PathBuf::from("."), Path::to_path_buf)
                    .join(".local")
                    .join("share")
            },
            Path::to_path_buf,
        );
        base.join(LORVEX_DIR).join(DB_FILE)
    };

    if let Some(path) = db_path_env.map(str::trim).filter(|path| !path.is_empty()) {
        // SQLite WAL mode is not supported on Windows
        // network shares — opening a WAL DB over SMB silently corrupts the
        // log and locks the file for every other client. Reject UNC paths
        // (forward- or back-slash form) at the locator boundary so a
        // misconfigured `DB_PATH` cannot point us at a share. We fall
        // through to the platform default rather than panicking, mirroring
        // the precedent for blank/empty `DB_PATH` overrides — that way a
        // managed-box user with a hostile shell init still gets a working
        // app instead of a wedged launch screen.
        if is_windows_unc_path(path) {
            diagnostics.push(
                DbLocationDiagnostic::warn(
                    DbLocationDiagnosticCode::DbPathOverrideRejectedUnc,
                    "DB_PATH override rejected; using platform default DB location",
                )
                .with_details(
                    "UNC / network share paths are not supported because SQLite WAL mode is unsafe over SMB.",
                ),
            );
        } else {
            return DbLocationDetails {
                resolved_path: PathBuf::from(path),
                source: DbPathSource::EnvOverride,
                platform_default_path,
                diagnostics,
            };
        }
    }

    let source = if data_dir.is_some() {
        DbPathSource::PlatformDataDir
    } else {
        DbPathSource::HomeFallback
    };

    DbLocationDetails {
        resolved_path: platform_default_path.clone(),
        source,
        platform_default_path,
        diagnostics,
    }
}

/// A symlink to a deleted path or an empty 0-byte DB should not trigger
/// DB adoption, so we require a positive file length.
fn path_has_nonempty_db(path: &Path) -> bool {
    if let Ok(meta) = std::fs::metadata(path) {
        if meta.is_file() && meta.len() > 0 {
            return true;
        }
    }
    // Also probe `<path>-wal` and `<path>-journal`. After a crash
    // with WAL mode (the default), the main DB file can legitimately
    // be 0 bytes while the WAL or journal carries a full committed
    // history that SQLite will recover on next open. Probing only the
    // main file's metadata would miss a valid SQLite DB and
    // fall through to `platform_default_path`.
    let probe_sidecar = |suffix: &str| -> bool {
        let mut sidecar = path.as_os_str().to_owned();
        sidecar.push(suffix);
        std::fs::metadata(Path::new(&sidecar)).is_ok_and(|meta| meta.is_file() && meta.len() > 0)
    };
    probe_sidecar("-wal") || probe_sidecar("-journal")
}
