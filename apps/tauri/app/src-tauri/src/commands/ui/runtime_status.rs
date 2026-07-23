use crate::db::{db_path, get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
// `mcp_runtime` is gated out on Android because the mobile sandbox forbids
// fork+exec of sidecar binaries. The renderer-facing
// `get_mcp_server_status` command still ships on Android for shape parity, but
// returns an `unresolved` payload with a platform-specific error message.
#[cfg(not(target_os = "android"))]
use crate::mcp_runtime::resolve_lorvex_mcp_server_config;
use serde::{Deserialize, Serialize};

const RUNTIME_STATUS_LOG_SOURCE: &str = "runtime.status";

fn append_runtime_status_log_with_conn(
    conn: &rusqlite::Connection,
    level: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    crate::commands::diagnostics::append_diagnostic_log_with_conn(
        conn,
        RUNTIME_STATUS_LOG_SOURCE,
        level,
        message,
        details,
    )
}

fn append_runtime_status_log(level: &str, message: &str, details: Option<String>) {
    let Ok(conn) = get_conn() else {
        return;
    };
    let _ = append_runtime_status_log_with_conn(&conn, level, message, details);
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct McpServerStatus {
    pub resolved: bool,
    pub command: Option<String>,
    pub args: Option<Vec<String>>,
    pub cwd: Option<String>,
    pub error: Option<String>,
    /// The shared MCP host authority from lorvex-runtime.
    /// "cli" = CLI is the canonical external MCP host.
    /// "app" = App is the canonical external MCP host.
    /// null = no authority has been set (first run or CLI never installed).
    pub mcp_host_authority: Option<String>,
    /// Whether the CLI binary is detected at a well-known path.
    pub cli_detected: bool,
}

/// Test-only counterpart to `get_runtime_paths`. See the helper's
/// doc-comment for why this stayed test-only.
#[cfg(test)]
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RuntimePaths {
    pub db_path: String,
}

pub type SetupStatus = lorvex_store::SetupStatus;

/// Test-only helper: regression tests pin the precedence of malformed
/// preferences vs. real prerequisite gating. The renderer-facing
/// `is_setup_complete` Tauri command was removed in #2940-H1 (no UI
/// caller); the test surface stays so the underlying setup-status
/// loader keeps regressions out.
#[cfg(test)]
fn is_setup_complete_with_conn(conn: &rusqlite::Connection) -> AppResult<bool> {
    lorvex_store::load_setup_status(conn)
        .map(|status| status.setup_completed)
        .map_err(AppError::from)
}

fn load_setup_status_with_conn(conn: &rusqlite::Connection) -> AppResult<SetupStatus> {
    lorvex_store::load_setup_status(conn).map_err(AppError::from)
}

fn reconcile_mcp_host_authority_with_conn(
    conn: &rusqlite::Connection,
    cli_detected: bool,
    app_mcp_resolved: bool,
) -> AppResult<Option<String>> {
    if app_mcp_resolved {
        lorvex_runtime::reclaim_app_mcp_host_authority_when_cli_missing(conn, cli_detected)?;
    }
    lorvex_runtime::get_mcp_host_authority(conn).map_err(AppError::from)
}

fn load_mcp_host_authority_for_status(
    cli_detected: bool,
    app_mcp_resolved: bool,
) -> Option<String> {
    let current = match get_read_conn() {
        Ok(conn) => {
            let result = lorvex_runtime::get_mcp_host_authority(&conn);
            drop(conn);
            result.unwrap_or_else(|e| {
                append_runtime_status_log(
                    "warn",
                    "MCP host authority read failed",
                    Some(format!("error={e}")),
                );
                None
            })
        }
        Err(e) => {
            append_runtime_status_log(
                "warn",
                "MCP host authority read connection unavailable",
                Some(format!("error={e}")),
            );
            None
        }
    };
    if !app_mcp_resolved || cli_detected || current.as_deref() == Some("app") {
        return current;
    }

    match get_conn() {
        Ok(conn) => reconcile_mcp_host_authority_with_conn(&conn, cli_detected, app_mcp_resolved)
            .unwrap_or_else(|e| {
                let _ = append_runtime_status_log_with_conn(
                    &conn,
                    "warn",
                    "MCP host authority reconcile failed",
                    Some(format!("error={e}")),
                );
                current
            }),
        Err(e) => {
            append_runtime_status_log(
                "warn",
                "MCP host authority writer connection unavailable",
                Some(format!("error={e}")),
            );
            current
        }
    }
}

#[tauri::command]
pub fn get_setup_status() -> Result<SetupStatus, String> {
    let conn = get_read_conn()?;
    load_setup_status_with_conn(&conn).map_err(String::from)
}

#[tauri::command]
pub fn get_mcp_server_status() -> Result<McpServerStatus, String> {
    let cli_detected = lorvex_runtime::detect_cli_installation().is_some();

    #[cfg(not(target_os = "android"))]
    {
        match resolve_lorvex_mcp_server_config() {
            Ok(config) => {
                let mcp_host_authority = load_mcp_host_authority_for_status(cli_detected, true);
                Ok(McpServerStatus {
                    resolved: true,
                    command: Some(config.command),
                    args: Some(config.args),
                    cwd: config.cwd,
                    error: None,
                    mcp_host_authority,
                    cli_detected,
                })
            }
            Err(error) => {
                let mcp_host_authority = load_mcp_host_authority_for_status(cli_detected, false);
                Ok(McpServerStatus {
                    resolved: false,
                    command: None,
                    args: None,
                    cwd: None,
                    error: Some(error),
                    mcp_host_authority,
                    cli_detected,
                })
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let mcp_host_authority = load_mcp_host_authority_for_status(cli_detected, false);
        // Mobile sandboxes forbid fork+exec of sidecar binaries. The MCP
        // server cannot launch on Android — surface that fact to the
        // renderer so Settings → Assistant MCP shows an explanatory note.
        Ok(McpServerStatus {
            resolved: false,
            command: None,
            args: None,
            cwd: None,
            error: Some(
                "MCP server is not supported on mobile platforms (sandbox forbids \
                 fork+exec of sidecar binaries)."
                    .to_string(),
            ),
            mcp_host_authority,
            cli_detected,
        })
    }
}

/// Test-only helper: the dedicated test asserts the `LORVEX_DB_PATH`
/// env override propagates through `db_path()`. The renderer-facing
/// `get_runtime_paths` Tauri command was removed in #2940-H1 (the UI
/// has its own About panel that reads this through other commands);
/// the test stays so the env-override path keeps regressions out.
#[cfg(test)]
pub(crate) fn get_runtime_paths() -> Result<RuntimePaths, String> {
    Ok(RuntimePaths {
        db_path: db_path().to_string_lossy().into_owned(),
    })
}

/// Reveal the local DB folder in the OS file manager (Finder / Explorer
/// / xdg-open). Used by the "Storage is full" toast's action button so
/// the user has an immediate path to free up space near the file that
/// triggered the ENOSPC. See #2386.
///
/// `tauri_plugin_opener::reveal_item_in_dir` is the cross-platform
/// shell-integrated entry point; it falls back to opening the parent
/// directory if the exact file cannot be selected on the current OS.
///
/// a buggy renderer or a click-jacked button could
/// invoke this many times in quick succession and cascade-launch
/// Finder/Explorer windows on the user's desktop. A 2-second debounce
/// at the IPC boundary collapses bursts to the first call; subsequent
/// invocations within the window return `Ok(())` silently — the user
/// already got the window they asked for. The throttle is process-wide
/// because there's exactly one OS file manager surface to reveal into.
#[tauri::command]
pub fn reveal_db_folder() -> Result<(), String> {
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    static LAST_REVEAL: Mutex<Option<Instant>> = Mutex::new(None);
    const THROTTLE: Duration = Duration::from_secs(2);

    // the throttle mutex
    // recovers from poison and clears the flag because the slot
    // holds nothing but an `Option<Instant>` — there is no
    // invariant a panic in a sibling reveal could have violated.
    // Refusing to recover would wedge the "Reveal DB folder"
    // Settings affordance permanently after any unrelated panic.
    // The throttle window resets to `now`, so a stale `Some(prev)`
    // observed across a poison boundary still satisfies the
    // intended "at most one reveal per 2 s" contract.
    let mut slot = LAST_REVEAL.lock().unwrap_or_else(|p| {
        LAST_REVEAL.clear_poison();
        p.into_inner()
    });
    let now = Instant::now();
    if let Some(prev) = *slot {
        if now.duration_since(prev) < THROTTLE {
            return Ok(());
        }
    }
    *slot = Some(now);
    drop(slot);

    let path = db_path();
    tauri_plugin_opener::reveal_item_in_dir(&path)
        .map_err(|error| format!("failed to reveal DB folder: {error}"))
}

/// Attempt to clear the DiskFull circuit breaker by running a tiny
/// probe write. The frontend wires this to the toast's "Try again"
/// affordance — if the user has freed space, the next click resumes
/// normal writes. Returns `Ok(true)` if the probe succeeded and the
/// breaker is now clear; `Ok(false)` if the probe itself hit DiskFull
/// (breaker stays tripped); `Err` for any other failure (e.g. DB is
/// offline entirely).
#[tauri::command]
pub fn retry_disk_full_probe() -> Result<bool, String> {
    let conn = get_conn().map_err(String::from)?;
    match lorvex_store::probe_disk_full(&conn) {
        Ok(()) => Ok(true),
        Err(error) => {
            if lorvex_store::is_disk_full_error(&error) {
                // Breaker re-trips inside `probe_disk_full`.
                return Ok(false);
            }
            Err(error.to_string())
        }
    }
}

/// Settings -> About surfaces the app + runtime + DB schema versions together
/// so bug reports let maintainers detect contract drift at a glance.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DiagnosticsVersions {
    pub app_version: String,
    pub mcp_server_version: String,
    pub schema_version: u32,
    pub payload_schema_version: u32,
}

/// parity with every other Tauri command in this
/// module — `Result<T, String>` so renderer error handling is uniform.
#[tauri::command]
pub fn get_diagnostics_versions() -> Result<DiagnosticsVersions, String> {
    Ok(DiagnosticsVersions {
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        mcp_server_version: env!("CARGO_PKG_VERSION").to_string(),
        schema_version: lorvex_domain::version::SCHEMA_VERSION,
        payload_schema_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
    })
}

#[cfg(test)]
mod tests {
    use super::{
        append_runtime_status_log_with_conn, get_diagnostics_versions, is_setup_complete_with_conn,
        load_setup_status_with_conn, reconcile_mcp_host_authority_with_conn,
        RUNTIME_STATUS_LOG_SOURCE,
    };

    use crate::test_support::test_conn;

    #[test]
    fn append_runtime_status_log_with_conn_persists_structured_diagnostic() {
        let conn = test_conn();

        append_runtime_status_log_with_conn(
            &conn,
            "Warning",
            "Runtime status diagnostic token=message-secret",
            Some("stage=test token=details-secret".to_string()),
        )
        .expect("append runtime status diagnostic");

        let row: (String, String, String, Option<String>) = conn
            .query_row(
                "SELECT source, level, message, details FROM error_logs",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read diagnostic row");

        assert_eq!(row.0, RUNTIME_STATUS_LOG_SOURCE);
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Runtime status diagnostic token=[REDACTED]");
        assert_eq!(row.3.as_deref(), Some("stage=test token=[REDACTED]"));
    }

    #[test]
    fn is_setup_complete_rejects_malformed_setup_completed_preference() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
                "\"definitely_not_a_bool\"",
                "0000000000000_0000_0000000000000000",
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert malformed setup_completed");

        let error =
            is_setup_complete_with_conn(&conn).expect_err("malformed setup_completed should fail");
        assert!(
            error.to_string().contains("setup_completed"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn is_setup_complete_returns_true_for_canonical_boolean_preference() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
                "true",
                "0000000000000_0000_0000000000000000",
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert setup_completed");

        assert!(is_setup_complete_with_conn(&conn).expect("read setup status"));
    }

    #[test]
    fn is_setup_complete_uses_real_setup_prereqs_not_task_existence() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES ('l1', 'Inboxless', '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
            [],
        )
        .expect("insert list");
        conn.execute(
            "INSERT OR REPLACE INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID,
                "\"l1\"",
                "0000000000000_0000_0000000000000000",
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert default list");

        assert!(!is_setup_complete_with_conn(&conn)
            .expect("working_hours should still gate setup completion"));

        conn.execute(
            "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                "{\"start\":\"09:00\",\"end\":\"17:00\"}",
                "0000000000000_0000_0000000000000000",
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert working hours");

        assert!(is_setup_complete_with_conn(&conn).expect("setup derived from prerequisites"));
    }

    #[test]
    fn get_setup_status_reports_default_list_and_normal_creation_readiness() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES ('l1', 'Inboxless', '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
            [],
        )
        .expect("insert list");
        conn.execute(
            "INSERT OR REPLACE INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID,
                "\"l1\"",
                "0000000000000_0000_0000000000000000",
                "2026-03-29T00:00:00Z"
            ],
        )
        .expect("insert default list");

        let status = load_setup_status_with_conn(&conn).expect("load setup status");
        assert_eq!(status.default_list_id.as_deref(), Some("l1"));
        assert!(status.lists_ready);
        assert!(status.default_list_ready);
        assert!(status.normal_task_creation_ready);
        assert!(!status.setup_completed);
    }

    #[test]
    fn app_mcp_status_reclaims_authority_when_cli_missing_and_app_mcp_resolves() {
        let conn = test_conn();
        let missing_cli_path = std::env::temp_dir().join("lorvex-missing-cli-for-app-status-test");
        conn.execute(
            "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at)
             VALUES (1, 'cli', 2, ?1, 1000)",
            rusqlite::params![missing_cli_path.to_string_lossy().as_ref()],
        )
        .expect("seed stale cli authority");

        let authority = reconcile_mcp_host_authority_with_conn(&conn, false, true)
            .expect("reconcile app authority");

        assert_eq!(authority.as_deref(), Some("app"));
    }

    #[test]
    fn app_mcp_status_preserves_cli_authority_when_cli_is_detected() {
        let conn = test_conn();
        lorvex_runtime::claim_mcp_host_authority(&conn, lorvex_runtime::McpHostAuthorityKind::Cli)
            .expect("seed cli authority");

        let authority = reconcile_mcp_host_authority_with_conn(&conn, true, true)
            .expect("reconcile app authority");

        assert_eq!(authority.as_deref(), Some("cli"));
    }

    #[test]
    fn app_mcp_status_does_not_reclaim_when_app_mcp_is_unresolved() {
        let conn = test_conn();
        let missing_cli_path =
            std::env::temp_dir().join("lorvex-missing-cli-for-unresolved-status-test");
        conn.execute(
            "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at)
             VALUES (1, 'cli', 2, ?1, 1000)",
            rusqlite::params![missing_cli_path.to_string_lossy().as_ref()],
        )
        .expect("seed stale cli authority");

        let authority = reconcile_mcp_host_authority_with_conn(&conn, false, false)
            .expect("reconcile app authority");

        assert_eq!(authority.as_deref(), Some("cli"));
    }

    #[test]
    fn app_mcp_status_preserves_cli_authority_when_recorded_cli_path_is_valid() {
        let conn = test_conn();
        lorvex_runtime::claim_mcp_host_authority(&conn, lorvex_runtime::McpHostAuthorityKind::Cli)
            .expect("seed cli authority");

        let authority = reconcile_mcp_host_authority_with_conn(&conn, false, true)
            .expect("reconcile app authority");

        assert_eq!(authority.as_deref(), Some("cli"));
    }

    #[test]
    fn diagnostics_versions_include_bundled_mcp_version() {
        let versions = get_diagnostics_versions().expect("diagnostics versions");

        assert_eq!(versions.app_version, env!("CARGO_PKG_VERSION"));
        assert_eq!(versions.mcp_server_version, env!("CARGO_PKG_VERSION"));
        assert!(versions.schema_version > 0);
        assert!(versions.payload_schema_version > 0);
    }
}
