//! Process-startup primitives: panic hook installation and the
//! migration-progress gate raised before the Tauri builder runs.
//!
//! Both are split out of `lib.rs` so the boot pipeline reads as a
//! short, auditable orchestrator instead of inline setup code. The
//! [`install_panic_hook`] step has to run before *any* `db` access;
//! [`ensure_database_ready`] must run before
//! `tauri::Builder::default()` so a slow migration can raise the
//! native progress dialog without contending with the WebView startup
//! lock.
//!
//! Folder layout:
//!
//! - `mod.rs` (this file) — re-exports the two public entry points
//!   plus `catch_unwind_without_default_panic_hook` (used by the
//!   macOS notification-action delegate).
//! - `panic_hook.rs` — `install_panic_hook` + suppression flag +
//!   `catch_unwind_without_default_panic_hook`.
//! - `migration_gate.rs` — the threshold constant, the
//!   `MigrationGate` outcome enum, the wait helper, and the native
//!   "Migrating…" dialog raise.
//! - `migration_progress.rs` — `MigrationProgressEvent` + the
//!   recorder / persist / format helpers.
//! - `database_ready.rs` — `ensure_database_ready` orchestrator
//!   (worker thread + result-slot mutex + threshold gate).
//! - `startup_failure.rs` — `ensure_database_ready_fail` (marker
//!   file + redacted body + actionable panic message).

mod database_ready;
mod migration_gate;
mod migration_progress;
mod panic_hook;
mod startup_failure;

#[cfg(test)]
mod tests;

pub(crate) use database_ready::ensure_database_ready;
pub(crate) use panic_hook::{catch_unwind_without_default_panic_hook, install_panic_hook};
