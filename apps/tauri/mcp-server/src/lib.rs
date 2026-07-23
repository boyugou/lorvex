//! # `lorvex-mcp-server`
//!
//! Stdio-transport MCP server that is the **primary write interface**
//! for the Lorvex task graph. AI assistants (Claude Desktop, IDE
//! extensions, OpenClaw / ClawHub) drive the entire app through the
//! tools surface declared here; the desktop UI is read-mostly and
//! mirrors whatever the assistant has written.
//!
//! ## Tools surface
//!
//! Tools are grouped into per-domain subtrees (`tasks/`, `calendar/`,
//! `habits/`, `lists/`, `memory/`, `preferences/`, `query/`,
//! `reviews/`, `system/`, `workflow/`) — each with a
//! sibling `router.rs` that registers handlers against the
//! `rmcp::ServerHandler` dispatch (workflow further splits into
//! `workflow/router/<topic>.rs` per-area siblings, see #3370). The
//! flat-tree consolidation completed in #3370 means a domain folder
//! owns *all* of its tool surface; no cross-folder imports.
//!
//! ## Contract validation
//!
//! Every tool's argument shape and response shape is validated at the
//! crate boundary by a derive-macro-backed contract layer (see
//! [`contract`] and [`contract_validate`], implementation in
//! `lorvex-mcp-derive`). The macros generate exhaustive arg/response
//! validators at compile time so a runtime mismatch (handler returns
//! a field absent from the contract, or accepts a field the contract
//! doesn't declare) is impossible. This is the lever that lets the
//! tools surface evolve without silent contract drift to assistant
//! clients.
//!
//! ## `log_change` builder
//!
//! Every write tool MUST emit an `ai_changelog` row before its
//! response is returned. The canonical builder lives in
//! `runtime::change_tracking` and threads through the
//! per-tool router via the `LogChangeBuilder` helper. Per-tool tests
//! assert `log_change` rows materialize via `changelog_*` helpers in
//! their respective `tests.rs` modules (see `server/tests/calendar.rs`,
//! `tasks/lifecycle/writes/tests/*.rs`).
//!
//! ## Test patterns
//!
//! Tests live colocated as `tests.rs` inside per-area subfolders:
//! `tasks/{batch,mutations,query,lifecycle,support}/<area>/tests.rs`.
//! The harness convention is:
//!
//!   1. Spin up an in-memory SQLite via `lorvex_store::test_support::*`
//!      builders (see `mcp-server/src/tasks/validation.rs` for usage
//!      patterns: `ListBuilder`, `fixtures::TaskBuilder`, etc.).
//!   2. Build a `RouterCtx` against the test connection.
//!   3. Drive tools through `router.invoke(...)` so the contract layer
//!      runs identically to production.
//!   4. Assert the response shape *and* the `ai_changelog` row.
//!
//! Tests intentionally use `unwrap()` / `expect()` for assertion clarity —
//! panics in tests ARE the failure mode, hence the crate-level
//! `clippy::unwrap_used` allow below.
#![cfg_attr(test, allow(clippy::unwrap_used))]

mod calendar;
pub(crate) mod contract;
pub(crate) mod contract_validate;
pub mod db;
pub(crate) mod error;
pub(crate) mod json_row;
pub mod public_api;
pub(crate) mod server;
/// re-export the snapshot readers that the criterion
/// harness in `benches/router.rs` exercises. These are not stable
/// public API — they exist only so the bench can measure the
/// post-fix prepare_cached + batched-snapshot paths in isolation.
#[doc(hidden)]
pub mod bench_support {
    use crate::error::McpError;
    use rusqlite::Connection;
    use serde_json::Value;
    use std::collections::HashMap;

    /// single-row entity snapshot read,
    /// the canonical hot path the json_row + schema-pragma caching
    /// fixes target.
    pub fn read_current_entity_snapshot_for_bench(
        conn: &Connection,
        entity_type: &str,
        entity_id: &str,
    ) -> Result<Option<Value>, McpError> {
        crate::runtime::change_tracking::read_current_entity_snapshot_for_bench(
            conn,
            entity_type,
            entity_id,
        )
    }

    /// batched IN-list snapshot read used by the
    /// MCP funnel's per-batch loop replacement.
    pub fn read_current_entity_snapshots_for_bench(
        conn: &Connection,
        entity_type: &str,
        entity_ids: &[String],
    ) -> Result<HashMap<String, Value>, McpError> {
        crate::runtime::change_tracking::read_current_entity_snapshots_for_bench(
            conn,
            entity_type,
            entity_ids,
        )
    }
}
mod focus;
mod habits;
mod lists;
mod memory;
mod preferences;
mod query;
mod reviews;
mod runtime;
mod shutdown;
mod system;
mod tasks;
pub(crate) mod time;
mod workflow;

use crate::shutdown::{
    cancel_and_drain_service, drain_application_work, force_exit_after_drain_timeout,
    ShutdownDrainOutcome, ShutdownTrigger, SERVICE_SHUTDOWN_DRAIN_GRACE_SECS,
};
use rmcp::{transport::stdio, ServiceExt};

/// Parent-process liveness polling interval. The MCP server is normally owned
/// by the assistant client that spawned it; if that client dies without closing
/// stdin, the Unix watchdog notices the parent PID change and routes shutdown
/// through the same graceful drain path as SIGINT/SIGTERM.
const ORPHAN_WATCHDOG_INTERVAL_SECS: u64 = 30;

pub async fn run_stdio_server() -> Result<(), Box<dyn std::error::Error>> {
    // install a structured tracing subscriber that
    // emits JSON to stderr BEFORE any other startup work runs. The
    // mcp-server is spawned by the Tauri parent; without the JSON
    // layer, unstructured stderr (rate-limit misses, snapshot-read
    // failures, and other diagnostic signals) would be invisible to
    // the user because the parent only captures parseable streams it
    // can route into `error_logs`. `EnvFilter` honors `RUST_LOG` so a
    // developer can dial verbosity without recompiling.
    //
    // `try_init` is intentional — repeat calls (test harnesses,
    // re-entry from `cargo test --bins`) must not panic. The first
    // installer wins for the rest of the process lifetime.
    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));
    let _ = tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .json()
        .with_env_filter(env_filter)
        .try_init();

    let server = server::LorvexMcpServer::new().map_err(std::io::Error::other)?;
    let in_flight = server.in_flight_tracker();
    let service = server.serve(stdio()).await?;
    tracing::info!(
        version = env!("CARGO_PKG_VERSION"),
        "MCP server running on stdio"
    );

    // capture rmcp's cancellation tokens *before* moving
    // `service` into `waiting()` so the watchdog and shutdown futures
    // can signal a graceful drain. `service.waiting()` consumes the
    // service, so each shutdown branch gets its own wrapper over the
    // same underlying `CancellationToken`.
    let watchdog_cancel = service.cancellation_token();
    let shutdown_cancel = service.cancellation_token();

    // Orphan detection watchdog: periodically check if the parent process died.
    // On Unix, when the parent dies, the child is reparented to PID 1 (launchd/init).
    // We detect this by comparing the current ppid against the original.
    let watchdog = async {
        #[cfg(not(unix))]
        {
            // Non-Unix: just wait forever, relying on stdin EOF.
            std::future::pending::<ShutdownTrigger>().await
        }

        #[cfg(unix)]
        {
            // SAFETY: `getppid` is a POSIX
            // syscall that takes no arguments and is documented to
            // be both signal-safe and thread-safe. It cannot fail
            // (always returns the parent pid as `pid_t`). No Rust
            // invariant is at risk.
            let original_ppid = unsafe { libc::getppid() };
            tracing::info!(parent_pid = original_ppid, "MCP orphan watchdog started");

            let interval = std::time::Duration::from_secs(ORPHAN_WATCHDOG_INTERVAL_SECS);
            loop {
                tokio::time::sleep(interval).await;
                // SAFETY: same contract as the
                // initial `getppid` above.
                let current_ppid = unsafe { libc::getppid() };
                if shutdown::parent_process_changed(original_ppid, current_ppid) {
                    tracing::warn!(
                        original_parent_pid = original_ppid,
                        current_parent_pid = current_ppid,
                        "MCP orphan watchdog detected parent process change"
                    );
                    return ShutdownTrigger::ParentProcessChanged;
                }
            }
        }
    };

    // Install process-signal handling into the select.
    // awoke on stdin EOF or the
    // orphan watchdog, so an assistant (or pkill-by-pid operator)
    // that sent SIGINT during a long tool call dropped the
    // in-flight future at an arbitrary point — leaving the
    // rusqlite transaction / savepoint for WAL recovery to clean
    // up on the NEXT process start instead of a clean ROLLBACK.
    // Exiting the select! now cancels the service token and keeps awaiting
    // `service.waiting()` for a bounded drain window.
    //
    // `ctrl_c` on Unix handles SIGINT only; that's the shape most
    // process managers and terminals send on quit. SIGTERM is the
    // next level up (init systems, container orchestrators). Wire
    // both on Unix; Windows gets only Ctrl+C via `ctrl_c`.
    let shutdown = async {
        #[cfg(unix)]
        {
            use tokio::signal::unix::{signal, SignalKind};
            let mut sigint = match signal(SignalKind::interrupt()) {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!(
                        signal = "SIGINT",
                        error = %e,
                        "MCP failed to install signal handler"
                    );
                    return std::future::pending::<ShutdownTrigger>().await;
                }
            };
            let mut sigterm = match signal(SignalKind::terminate()) {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!(
                        signal = "SIGTERM",
                        error = %e,
                        "MCP failed to install signal handler"
                    );
                    return std::future::pending::<ShutdownTrigger>().await;
                }
            };
            tokio::select! {
                _ = sigint.recv() => tracing::info!(signal = "SIGINT", "MCP shutdown signal received"),
                _ = sigterm.recv() => tracing::info!(signal = "SIGTERM", "MCP shutdown signal received"),
            }
            ShutdownTrigger::Signal
        }
        #[cfg(not(unix))]
        {
            match tokio::signal::ctrl_c().await {
                Ok(()) => tracing::info!(signal = "Ctrl+C", "MCP shutdown signal received"),
                Err(e) => {
                    tracing::error!(
                        signal = "Ctrl+C",
                        error = %e,
                        "MCP failed to install signal handler"
                    );
                    return std::future::pending::<ShutdownTrigger>().await;
                }
            }
            ShutdownTrigger::Signal
        }
    };

    let service_done = service.waiting();
    tokio::pin!(service_done);

    // Wait for the MCP service to end (stdin closed), the watchdog
    // to trigger, or a signal to arrive. When shutdown is initiated by
    // watchdog/signal, cancel the rmcp service and then keep awaiting
    // the same `waiting()` future for a bounded grace window. Dropping
    // that future immediately would cancel without guaranteeing
    // transport cleanup or task drain.
    tokio::select! {
        result = service_done.as_mut() => {
            let service_result = result.map(|_| ());
            let trigger = ShutdownTrigger::ServiceCompleted;
            let outcome = drain_application_work(
                trigger,
                in_flight.clone().wait_for_idle(),
                std::time::Duration::from_secs(SERVICE_SHUTDOWN_DRAIN_GRACE_SECS),
            )
            .await;
            if outcome == ShutdownDrainOutcome::TimedOut {
                force_exit_after_drain_timeout(trigger);
            }
            service_result?;
        }
        trigger = watchdog => {
            let outcome = cancel_and_drain_service(
                trigger,
                || watchdog_cancel.cancel(),
                service_done.as_mut(),
                in_flight.clone().wait_for_idle(),
                std::time::Duration::from_secs(SERVICE_SHUTDOWN_DRAIN_GRACE_SECS),
            )
            .await?;
            if outcome == ShutdownDrainOutcome::TimedOut {
                force_exit_after_drain_timeout(trigger);
            }
        }
        trigger = shutdown => {
            let outcome = cancel_and_drain_service(
                trigger,
                || shutdown_cancel.cancel(),
                service_done.as_mut(),
                in_flight.clone().wait_for_idle(),
                std::time::Duration::from_secs(SERVICE_SHUTDOWN_DRAIN_GRACE_SECS),
            )
            .await?;
            if outcome == ShutdownDrainOutcome::TimedOut {
                force_exit_after_drain_timeout(trigger);
            }
        }
    }
    Ok(())
}
