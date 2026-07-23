//! Tests for `db_locator`. Extracted from the parent file
//! to keep the production module focused.

use std::path::PathBuf;

use super::env::current_db_path_env_for_resolver;
#[cfg(not(debug_assertions))]
use super::env::ALLOW_DB_PATH_OVERRIDE_ENV;
use super::platform_windows::is_windows_unc_path;
use super::resolve::resolve_db_location_details_with;
use super::*;
use crate::with_db_path_env_for_test;

#[test]
fn db_path_env_override_wins() {
    let resolved = resolve_db_location_details_with(
        Some(" /tmp/lorvex-dev.sqlite "),
        Some(PathBuf::from("/ignored")),
        Some(PathBuf::from("/also-ignored")),
        |_| false,
    );

    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("/tmp/lorvex-dev.sqlite")
    );
    assert_eq!(resolved.source, DbPathSource::EnvOverride);
}

#[test]
fn blank_env_is_ignored() {
    let resolved = resolve_db_location_details_with(
        Some("   "),
        Some(PathBuf::from("/data")),
        Some(PathBuf::from("/home/tester")),
        |_| false,
    );

    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("/data/Lorvex/db.sqlite")
    );
    assert_eq!(resolved.source, DbPathSource::PlatformDataDir);
}

/// the resolver function under test
/// (`resolve_db_location_details_with`) takes the env value as a
/// parameter, so the gating logic lives in
/// `current_db_path_env_for_resolver`. In debug builds (which is
/// where `cargo test` runs) the helper must still surface
/// `DB_PATH` unconditionally — otherwise dev workflows break.
#[cfg(debug_assertions)]
#[test]
fn db_path_env_visible_in_debug_builds() {
    with_db_path_env_for_test(Some("/tmp/lorvex-debug.sqlite"), || {
        assert_eq!(
            current_db_path_env_for_resolver().as_deref(),
            Some("/tmp/lorvex-debug.sqlite"),
            "DB_PATH must be visible in debug/test builds"
        );
    });
}

/// Mirror of the debug-build test for release builds. Compiled
/// only on `cargo test --release` so a CI matrix can exercise the
/// gating path. The helper must reject DB_PATH unless the opt-in
/// env is also set.
#[cfg(not(debug_assertions))]
#[test]
fn db_path_env_requires_opt_in_in_release_builds() {
    with_db_path_env_for_test(Some("/tmp/lorvex-release.sqlite"), || {
        // Without opt-in: dropped on the floor.
        // Safety: env mutation serialized via `with_db_path_env_for_test`'s mutex.
        unsafe {
            std::env::remove_var(ALLOW_DB_PATH_OVERRIDE_ENV);
        }
        assert_eq!(
            current_db_path_env_for_resolver(),
            None,
            "DB_PATH must be ignored in release builds without opt-in"
        );

        // With opt-in: passes through.
        unsafe {
            std::env::set_var(ALLOW_DB_PATH_OVERRIDE_ENV, "1");
        }
        assert_eq!(
            current_db_path_env_for_resolver().as_deref(),
            Some("/tmp/lorvex-release.sqlite"),
            "DB_PATH must be honored with explicit opt-in"
        );

        // Empty / "0" / "false" do NOT opt in.
        for falsy in ["", "0", "false", "FALSE", "  "] {
            unsafe {
                std::env::set_var(ALLOW_DB_PATH_OVERRIDE_ENV, falsy);
            }
            assert_eq!(
                current_db_path_env_for_resolver(),
                None,
                "falsy opt-in value {falsy:?} must NOT enable DB_PATH"
            );
        }

        unsafe {
            std::env::remove_var(ALLOW_DB_PATH_OVERRIDE_ENV);
        }
    });
}

/// UNC paths in `DB_PATH` must be rejected so
/// SQLite cannot open WAL mode on a network share. The resolver
/// falls back to the platform default, mirroring the
/// blank-DB_PATH-is-ignored precedent.
///
/// #3051 M5: backslash UNC `\\server\share` is rejected on every
/// platform (the form is unambiguously Windows-only on input).
/// Forward-slash `//server/share` is rejected only on Windows —
/// on Unix that shape is a valid POSIX path with a (collapsing)
/// double-slash root, not a UNC reference, so blocking it would
/// reject legitimate Unix overrides like `//Volumes/Data/db.sqlite`.
#[test]
fn unc_db_path_override_rejected_and_falls_back_to_platform_default() {
    let resolved = resolve_db_location_details_with(
        Some("\\\\fileserver\\share\\db.sqlite"),
        Some(PathBuf::from("/data")),
        Some(PathBuf::from("/Users/tester")),
        |_| false,
    );
    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("/data/Lorvex/db.sqlite"),
        "backslash UNC override must be rejected on every platform",
    );
    assert_eq!(resolved.source, DbPathSource::PlatformDataDir);
    assert_eq!(resolved.diagnostics.len(), 1);
    assert_eq!(
        resolved.diagnostics[0].code,
        DbLocationDiagnosticCode::DbPathOverrideRejectedUnc
    );
    assert!(
        resolved.diagnostics[0]
            .details
            .as_deref()
            .unwrap_or_default()
            .contains("UNC / network share paths"),
        "rejected UNC diagnostic must explain the rejection"
    );
    assert!(
        !resolved.diagnostics[0]
            .details
            .as_deref()
            .unwrap_or_default()
            .contains("fileserver"),
        "rejected UNC diagnostic must not persist raw network host/share names"
    );
}

#[test]
fn resolve_db_path_queues_structured_diagnostics_for_follow_up_persistence() {
    with_db_path_env_for_test(Some("\\\\fileserver\\share\\db.sqlite"), || {
        let _ = take_db_location_diagnostics();

        let _ = resolve_db_path();
        let diagnostics = take_db_location_diagnostics();

        assert_eq!(diagnostics.len(), 1);
        assert_eq!(
            diagnostics[0].code,
            DbLocationDiagnosticCode::DbPathOverrideRejectedUnc
        );
        assert!(diagnostics[0]
            .details
            .as_deref()
            .unwrap_or_default()
            .contains("UNC / network share paths"));
        assert!(!diagnostics[0]
            .details
            .as_deref()
            .unwrap_or_default()
            .contains("fileserver"));
    });
}

/// #3051 M5: forward-slash double-leading-separator paths are
/// rejected only on Windows.
#[test]
#[cfg(target_os = "windows")]
fn forward_slash_unc_db_path_override_rejected_on_windows() {
    let resolved = resolve_db_location_details_with(
        Some("//fileserver/share/db.sqlite"),
        Some(PathBuf::from("/data")),
        Some(PathBuf::from("/Users/tester")),
        |_| false,
    );
    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("/data/Lorvex/db.sqlite"),
        "forward-slash UNC override must be rejected on Windows",
    );
    assert_eq!(resolved.source, DbPathSource::PlatformDataDir);
}

/// #3051 M5: on non-Windows platforms a `//`-leading path is a
/// valid POSIX file path (with a collapsing double-slash root), NOT
/// a UNC reference. Pre-fix the cross-platform reject would surface
/// `DbPathSource::PlatformDataDir` for a legitimate local override.
#[test]
#[cfg(not(target_os = "windows"))]
fn forward_slash_path_is_not_treated_as_unc_on_unix() {
    let resolved = resolve_db_location_details_with(
        Some("//Volumes/Data/db.sqlite"),
        Some(PathBuf::from("/data")),
        Some(PathBuf::from("/Users/tester")),
        |_| false,
    );
    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("//Volumes/Data/db.sqlite"),
        "forward-slash override on Unix must NOT be misclassified as UNC",
    );
}

#[test]
fn is_windows_unc_path_classifies_back_and_forward_slash_forms() {
    assert!(is_windows_unc_path("\\\\server\\share"));
    // #3051 M5: forward-slash `//` is UNC only on Windows.
    #[cfg(target_os = "windows")]
    assert!(is_windows_unc_path("//server/share"));
    #[cfg(not(target_os = "windows"))]
    assert!(!is_windows_unc_path("//server/share"));
    assert!(!is_windows_unc_path("C:\\Users\\me\\db.sqlite"));
    assert!(!is_windows_unc_path("/home/me/db.sqlite"));
    assert!(!is_windows_unc_path(""));
    assert!(!is_windows_unc_path("\\"));
}

#[test]
fn falls_back_to_platform_data_dir() {
    let resolved = resolve_db_location_details_with(
        None,
        Some(PathBuf::from("/var/data")),
        Some(PathBuf::from("/Users/tester")),
        |_| false,
    );

    assert_eq!(
        resolved.resolved_path,
        PathBuf::from("/var/data/Lorvex/db.sqlite")
    );
    assert_eq!(
        resolved.platform_default_path,
        PathBuf::from("/var/data/Lorvex/db.sqlite")
    );
}
