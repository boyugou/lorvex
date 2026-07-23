//! `DB_PATH` environment-variable resolution with a release-build
//! opt-in gate.
//!
//! In release builds the `DB_PATH` env var is a dangerous redirect
//! surface — a hostile shell init or a sloppy post-install script
//! could silently point Lorvex at a sibling DB (e.g. `/tmp/db.sqlite`)
//! and steal subsequent writes. Dev workflows (debug builds,
//! integration tests, the agent CLI) legitimately need `DB_PATH` so we
//! can't simply remove it — but we CAN require an explicit opt-in env
//! var in release. Setting `LORVEX_ALLOW_DB_PATH_OVERRIDE=1` activates
//! the override; anything else (unset, empty, "0", "false") makes the
//! resolver ignore `DB_PATH` and fall through to the platform default.

use super::types::DbLocationDiagnostic;
#[cfg(not(debug_assertions))]
use super::types::DbLocationDiagnosticCode;

/// The opt-in env name is intentionally long and prefixed so it
/// doesn't collide with anything a user might already have, and so
/// `printenv` makes the intent obvious to an auditor.
///
/// Only consulted in release builds; debug builds keep the historical
/// "always honor `DB_PATH`" behavior so engineers can point a local
/// copy at a fixture DB without ceremony. Tests on release-mode CI
/// runners are gated behind the explicit opt-in.
///
/// Gated `cfg(not(debug_assertions))` because every consumer
/// (the production read at the bottom of this file plus the
/// `db_locator/tests.rs` test imports) is itself gated on
/// `cfg(not(debug_assertions))`. Replaces the previous
/// `#[cfg_attr(debug_assertions, allow(dead_code))]` shield so we never
/// carry an `allow(dead_code)` attribute (CLAUDE.md rule 12).
#[cfg(not(debug_assertions))]
pub(super) const ALLOW_DB_PATH_OVERRIDE_ENV: &str = "LORVEX_ALLOW_DB_PATH_OVERRIDE";

pub(super) struct DbPathEnvResolution {
    pub(super) db_path: Option<String>,
    pub(super) diagnostics: Vec<DbLocationDiagnostic>,
}

/// read `DB_PATH` from the environment, but suppress
/// it in release builds unless the operator explicitly opts in via
/// [`ALLOW_DB_PATH_OVERRIDE_ENV`].
///
/// Debug builds see `DB_PATH` unconditionally — the gate is purely a
/// hardening rail for shipped binaries that should never read a
/// user-controlled DB location without a deliberate signal.
#[cfg(test)]
pub(super) fn current_db_path_env_for_resolver() -> Option<String> {
    current_db_path_env_resolution().db_path
}

pub(super) fn current_db_path_env_resolution() -> DbPathEnvResolution {
    let raw = std::env::var("DB_PATH").ok();

    // Debug builds (cargo test, cargo run, dev IDE workflows) keep the
    // historical behavior so engineers can point a local copy at a
    // fixture DB without ceremony. Tests on release-mode CI runners
    // are gated behind the explicit opt-in below.
    #[cfg(debug_assertions)]
    {
        DbPathEnvResolution {
            db_path: raw,
            diagnostics: Vec::new(),
        }
    }

    #[cfg(not(debug_assertions))]
    {
        let allowed = std::env::var(ALLOW_DB_PATH_OVERRIDE_ENV).is_ok_and(|v| {
            let trimmed = v.trim();
            !(trimmed.is_empty()
                || trimmed.eq_ignore_ascii_case("0")
                || trimmed.eq_ignore_ascii_case("false"))
        });

        if !allowed {
            let diagnostics = raw
                .as_deref()
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .map(|_| {
                    DbLocationDiagnostic::warn(
                        DbLocationDiagnosticCode::DbPathOverrideIgnoredRelease,
                        "DB_PATH override ignored in release build; using platform default DB location",
                    )
                    .with_details(format!(
                        "Set {ALLOW_DB_PATH_OVERRIDE_ENV}=1 to enable the DB_PATH override."
                    ))
                })
                .into_iter()
                .collect();
            return DbPathEnvResolution {
                db_path: None,
                diagnostics,
            };
        }

        DbPathEnvResolution {
            db_path: raw,
            diagnostics: Vec::new(),
        }
    }
}
