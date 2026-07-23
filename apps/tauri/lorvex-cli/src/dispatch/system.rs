//! `lorvex system …` + `lorvex sync …` + the unparented setup/TUI/MCP/completion
//! commands. This module owns every async helper used by the dispatcher
//! ([`handle_tui_watch`], [`handle_mcp_serve`]) plus the sync ones that
//! are tightly coupled to system-level state ([`handle_setup`],
//! [`handle_tui`], [`handle_mcp_install`], [`handle_completions`]). The
//! sync `SyncCommand` arms live here too because they read the same
//! shared sync state and there is no separate sync top-level module.

use crate::cli::{ClapCli, McpInstallTarget, OutputFormat, SyncCommand, SystemCommand};
use crate::commands::data::{run_export, run_import};
use crate::commands::mcp::{
    claim_cli_mcp_host_authority, install_mcp_configs, preflight_cli_mcp_host_authority_claim,
};
use crate::commands::mutate::run_setup_complete;
use crate::commands::query::{
    run_changelog, run_error_logs, run_setup_status, run_sync_outbox, run_sync_status,
};
use crate::commands::setup::{render_status_dashboard, run_doctor, run_setup};
use crate::error::CliError;
use crate::startup_maintenance::open_db_at_path;
use crate::tui::{load_dashboard_snapshot, render_tui_dashboard_for_snapshot};
use lorvex_runtime::{read_local_change_seq, resolve_db_path};

pub(super) async fn dispatch_system(command: SystemCommand) -> Result<(), CliError> {
    match command {
        SystemCommand::Setup { install_target } => handle_setup(install_target)?,
        SystemCommand::Doctor { format } => println!("{}", run_doctor(format)?),
        SystemCommand::Status { format } => println!("{}", render_status_dashboard(format)?),
        SystemCommand::Changelog {
            limit,
            entity_type,
            operation,
            entity_id,
            since,
            format,
        } => println!(
            "{}",
            run_changelog(limit, entity_type, operation, entity_id, since, format)?
        ),
        SystemCommand::ErrorLogs {
            source,
            limit,
            format,
        } => println!("{}", run_error_logs(source.as_deref(), limit, format)?),
        SystemCommand::SetupStatus { format } => println!("{}", run_setup_status(format)?),
        SystemCommand::SetupComplete { summary, format } => {
            println!("{}", run_setup_complete(&summary, format)?);
        }
        SystemCommand::Tui => handle_tui()?,
        SystemCommand::TuiWatch => handle_tui_watch().await?,
        SystemCommand::McpInstall { target } => handle_mcp_install(target)?,
        SystemCommand::McpServe => handle_mcp_serve().await?,
        SystemCommand::Completions { shell } => handle_completions(shell),
        SystemCommand::Export {
            output_path,
            format,
        } => println!("{}", run_export(&output_path, format)?),
        SystemCommand::Import { input_path, format } => {
            println!("{}", run_import(&input_path, format)?);
        }
    }
    Ok(())
}

pub(super) fn dispatch_sync(command: &SyncCommand) -> Result<(), CliError> {
    match *command {
        SyncCommand::Status { format } => println!("{}", run_sync_status(format)?),
        SyncCommand::Outbox { limit, format } => println!("{}", run_sync_outbox(limit, format)?),
    }
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────
// Substantive helpers — arms whose body is more than `println!(run_X(...)?)`
// ─────────────────────────────────────────────────────────────────────

fn handle_setup(install_target: Option<McpInstallTarget>) -> Result<(), CliError> {
    // `setup` is a common first-run automation target. The global
    // `--format json` is picked up here via the process-wide default, so
    // automation can parse the result without scraping text.
    let format = OutputFormat::default();
    println!("{}", run_setup(install_target, format)?);
    Ok(())
}

fn handle_tui() -> Result<(), CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let snapshot = load_dashboard_snapshot(&conn, &db_path)?;
    println!("{}", render_tui_dashboard_for_snapshot(&snapshot));
    Ok(())
}

async fn handle_tui_watch() -> Result<(), CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    // Periodic retention sweep, gated on the shared 6-hour watermark
    // checkpoint so a re-spawned tui-watch session does not redo the work
    // every reconnect. One-shot CLI commands (`add task`, etc.) do NOT
    // call this — they would pay the cost on every invocation; the
    // watermark would skip the body but the watermark check itself is
    // still a query. Long-running surfaces are the natural cadence
    // because they sit on the DB long enough that one sweep per session
    // converges with the desktop renderer's 6-hour cron.
    crate::startup_maintenance::run_retention_sweep_if_due(&conn);

    // Audit round-2 (#2752): bound the watch loop against a wedged DB. If
    // `read_local_change_seq` / snapshot loading fails 10 times in a row,
    // break out of the loop with the last error so the user gets a useful
    // exit code instead of an infinite silent spinner. Transient failures
    // under this threshold still continue, so a single SQLITE_BUSY tick
    // doesn't terminate the session.
    //
    // M3. The previous failure path slept a flat 250ms between each retry,
    // so N tui-watch processes that started simultaneously (a multi-pane
    // tmux layout, a shell wrapper that fanned out to several DBs, …) all
    // re-hit the wedged DB at the same offset and stayed in lockstep until
    // they tripped the consecutive-failure ceiling together. Routing the
    // failure backoff through `lorvex-runtime::JitterRng` adds ±jitter that
    // de-correlates the schedules across siblings.
    const MAX_CONSECUTIVE_FAILURES: u32 = 10;
    const BACKOFF_BASE_MS: u64 = 250;
    const BACKOFF_CAP_MS: u64 = 5_000;
    const POLL_INTERVAL_MS: u64 = 250;
    let mut backoff_rng = lorvex_runtime::JitterRng::from_entropy();
    let backoff_for = |attempt: u32, rng: &mut lorvex_runtime::JitterRng| {
        // Exponential schedule capped at BACKOFF_CAP_MS, then ±25% jitter.
        // The cap lands at attempt 5 (250 → 500 → 1000 → 2000 → 4000 →
        // 5000) so a wedged DB gives the watch loop a humane recovery
        // window before the failure ceiling fires.
        let exp = BACKOFF_BASE_MS.saturating_mul(1u64 << attempt.min(5));
        let bounded = exp.min(BACKOFF_CAP_MS);
        let jitter_window = bounded / 2;
        let jitter = rng.jitter_ms(jitter_window.max(1));
        // Center the jitter on `bounded` by subtracting half the window:
        // result lands in [bounded - window/2, bounded + window/2). Clamp
        // the floor so a tiny bounded value doesn't underflow.
        let centered = bounded
            .saturating_add(jitter)
            .saturating_sub(jitter_window / 2);
        std::time::Duration::from_millis(centered.max(50))
    };
    let mut consecutive_failures: u32 = 0;
    let mut last_seq = None;
    loop {
        let current_seq = match read_local_change_seq(&conn) {
            Ok(seq) => {
                consecutive_failures = 0;
                seq
            }
            Err(err) => {
                consecutive_failures += 1;
                if consecutive_failures >= MAX_CONSECUTIVE_FAILURES {
                    return Err(CliError::Internal(format!(
                        "tui-watch: {MAX_CONSECUTIVE_FAILURES} consecutive DB read failures, giving up: {err}"
                    )));
                }
                tokio::time::sleep(backoff_for(consecutive_failures, &mut backoff_rng)).await;
                continue;
            }
        };
        if last_seq != Some(current_seq) {
            let snapshot = match load_dashboard_snapshot(&conn, &db_path) {
                Ok(s) => {
                    consecutive_failures = 0;
                    s
                }
                Err(err) => {
                    consecutive_failures += 1;
                    if consecutive_failures >= MAX_CONSECUTIVE_FAILURES {
                        return Err(CliError::Internal(format!(
                            "tui-watch: {MAX_CONSECUTIVE_FAILURES} consecutive snapshot failures, giving up: {err}"
                        )));
                    }
                    tokio::time::sleep(backoff_for(consecutive_failures, &mut backoff_rng)).await;
                    continue;
                }
            };
            print!(
                "\x1B[2J\x1B[H{}",
                render_tui_dashboard_for_snapshot(&snapshot)
            );
            last_seq = Some(current_seq);
        }
        // success-path poll keeps the prior fixed cadence so the live
        // dashboard refresh latency stays predictable. The jitter helper
        // above only fires on the failure path where decorrelation across
        // sibling watchers matters.
        tokio::time::sleep(std::time::Duration::from_millis(POLL_INTERVAL_MS)).await;
    }
}

fn handle_mcp_install(target: McpInstallTarget) -> Result<(), CliError> {
    // Verify the DB authority claim path before touching client config,
    // then store the authority only after config installation succeeds.
    // This keeps a failed install from advertising a CLI endpoint that was
    // never written, while still catching DB write failures before config IO.
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    preflight_cli_mcp_host_authority_claim(&conn)?;
    // install_mcp_configs handles All expansion (unlike install_mcp_config
    // which rejects All). honor process-wide `--format json` by rendering
    // a minimal `{installed: [...]}` summary when requested. Text mode
    // preserves the prior free-form output.
    let format = OutputFormat::default();
    let result = install_mcp_configs(target)?;
    claim_cli_mcp_host_authority(&conn)?;
    match format {
        OutputFormat::Text => println!("{result}"),
        OutputFormat::Json => {
            // allocating one fresh `String` per line solely to feed
            // `serde_json::json!`. `serde_json` accepts any `Serialize`
            // slice, so a borrowed `Vec<&str>` (or even a slice) round-trips
            // through the same wire bytes without the per-line copy.
            let installed: Vec<&str> = result.lines().collect();
            let empty_errors: [&str; 0] = [];
            let payload = serde_json::json!({
                "installed": installed,
                "errors": empty_errors,
            });
            println!("{}", serde_json::to_string_pretty(&payload)?);
        }
    }
    Ok(())
}

async fn handle_mcp_serve() -> Result<(), CliError> {
    // the prior `mcp-serve` cfg-gate was a no-op with default features and
    // CI never built the no-default variant, so the conditional only added
    // maintenance burden. The MCP server is now an unconditional dep and
    // this arm runs straight through.
    //
    // `run_stdio_server` returns `Box<dyn std::error::Error>` (the
    // mcp-server entry point hasn't been migrated to a typed error yet —
    // tracked separately). Wrap into `CliError::Internal` so the CLI's
    // exit-code classifier still produces EX_SOFTWARE for stdio-runtime
    // failures instead of the generic exit-1 fallback the previous
    // `Box<dyn Error>` round-trip land on.
    lorvex_mcp_server::run_stdio_server()
        .await
        .map_err(|err| CliError::Internal(format!("mcp-server stdio runtime failed: {err}")))?;
    Ok(())
}

fn handle_completions(shell: clap_complete::Shell) {
    // `lorvex completions <shell>` writes a shell completion script to
    // stdout and exits. No DB is opened and no side effects occur — this
    // is purely a render of the clap command tree, safe to pipe into a
    // completion load path.
    let mut cmd = ClapCli::command();
    clap_complete::generate(shell, &mut cmd, "lorvex", &mut std::io::stdout());
}
