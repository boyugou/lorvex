//! Data-management Tauri commands: full export / import snapshots
//! (round-trip ZIP archive of the SQLite store) and
//! the destructive reset paths (`reset_all_data`,
//! `reset_preferences`) that wipe local state without touching the
//! sync queue's tombstone bookkeeping.
//!
//! Source: refactor for #3277 — `data_snapshot.rs` / `data_snapshot/`
//! and `data_reset/` at the `commands/` root were folded under this
//! single `data/` namespace.

pub(crate) mod interchange;
pub(crate) mod reset;
pub(crate) mod snapshot;
