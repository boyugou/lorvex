//! Test-support utilities for `lorvex-store`.
//!
//! This module is feature-gated behind `test-support` so production builds
//! don't pay any cost (and can't accidentally depend on it). Tests inside
//! `lorvex-store` pick it up via `#[cfg(test)]`; downstream crates (the
//! Tauri backend, MCP server) enable the `test-support` feature in their
//! `[dev-dependencies]` block.
//!
//! The headline helper is [`diag::open_test_db_with_diag`]. It wraps the
//! temp-DB creation path used by the store/sync/widget tests and, when
//! anything goes wrong, returns a [`diag::TestSetupError`] that contains
//! the full path attempted, free-space remaining, a writability probe
//! result, and the underlying `io::Error` / `rusqlite::Error`. The goal
//! is to replace the opaque `rusqlite::Error("disk I/O error")` surface
//! that CI runners hit when /tmp is under pressure with a report that
//! tells a human (or a log-scraper) exactly why the test couldn't start.
//!
//! See `docs/execution/TEST_FLAKINESS.md` for the playbook.

#![cfg(any(test, feature = "test-support"))]

pub mod diag;
pub mod fixtures;
pub mod hlc_fixture;

pub use fixtures::{ListBuilder, TaskBuilder};
pub use hlc_fixture::{seed_test_row_check, TEST_VERSION};

/// Canonical in-memory test connection helper.
///
/// previously redeclared byte-identically in 12+
/// `#[cfg(test)] mod tests` blocks across `lorvex-store` (and once
/// more in `lorvex-sync/src/lib.rs`) with three different
/// panic-message variants (`"failed to open in-memory DB"`,
/// `"open in-memory DB"`, `"open in-memory db"`). Lifted here so
/// every site uses the same connection-opening path AND the same
/// panic message, which makes a startup-failure trace immediately
/// recognisable in CI logs.
pub fn test_conn() -> rusqlite::Connection {
    crate::open_db_in_memory().expect("open in-memory test DB")
}
