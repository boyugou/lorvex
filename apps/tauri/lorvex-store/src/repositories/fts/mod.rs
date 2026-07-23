//! FTS5 mutation helpers — single source of truth for every SQL
//! string that writes to the `tasks_fts_trigram` and
//! `calendar_events_fts` virtual tables.
//!
//! ## Why this module exists
//!
//! Both trigram tables are external-content FTS5 indexes, so
//! single-row mutations follow the canonical "tombstone then insert"
//! idiom:
//!
//! ```text
//! INSERT INTO <fts>(<fts>, rowid, ...) VALUES ('delete', ?, ...); -- tombstone
//! INSERT INTO <fts>(rowid, ...) VALUES (?, ...); -- repopulate
//! ```
//!
//! the trigger DDL embedded inside [`projection`](crate::projection)
//! and the schema's initial DDL in `001_schema.sql`, with admin
//! commands (`'rebuild'`, `'optimize'`) inlined inside
//! [`connection::run_periodic_maintenance`](crate::connection::run_periodic_maintenance)
//! and [`projection`](crate::projection). Issue #3281 consolidates
//! those mutation strings here so a future column addition
//! (e.g. extending `tasks_fts_trigram` with another searchable
//! column) only has to be applied in one Rust file.
//!
//! Read paths (`SELECT ... WHERE <fts> MATCH ?`) intentionally stay
//! in their query modules — the consolidation target is the *write*
//! surface, since that is where drift between trigger DDL and
//! ad-hoc Rust SQL would silently corrupt the index.
//!
//! ## Structure
//!
//! - [`tasks_trigram`] — `tasks_fts_trigram` mutations.
//! - [`calendar`] — `calendar_events_fts` mutations.
//!
//! Each submodule exposes:
//!
//! 1. SQL string constants (`*_UPSERT_INSERT_SQL`, `*_TOMBSTONE_SQL`,
//!    `*_TRIGGERS_SQL`, etc.) — used by both Rust callers and the
//!    trigger DDL installers.
//! 2. Single-row Rust helpers (`*_upsert`, `*_delete`).
//! 3. Trigger lifecycle helpers (`install_*_triggers`,
//!    `drop_*_triggers`).
//! 4. Bulk maintenance helpers (`rebuild_*`, `optimize_*`).

pub mod calendar;
pub mod tasks_trigram;

#[cfg(test)]
mod tests;
