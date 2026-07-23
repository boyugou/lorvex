//! Tiny shared abstraction for repositories whose entities have a
//! single string `id` primary key.
//!
//! ## Scope
//!
//! This module captures the **only** read/delete pattern that is truly
//! identical across multiple repositories: `SELECT … FROM <table>
//! WHERE id = ?1` and `DELETE FROM <table> WHERE id = ?1`.
//!
//! A sweeping `EntityRepo<T>` covering `get_by_id` / `upsert` /
//! `delete` / `list_paginated` across `list_repo`, `tag_repo`,
//! `provider_repo`, `memory_revision_repo`, `preference_repo`, and
//! `task_calendar_event_link_repo` is intentionally not provided.
//! The shape of those repos diverges enough that a unified trait
//! buys nothing:
//!
//! - Only `list_repo` (and `memory_revision_repo::get_revision`) have a
//!   clean single-id `get_by_id` / `delete_by_id` shape.
//! - `tag_repo` is keyed by `lookup_key`, not `id`; it has no
//!   `get_by_id` and no `delete_*` at all.
//! - `provider_repo` and `task_calendar_event_link_repo` use **composite**
//!   primary keys — fundamentally a different signature.
//! - `preference_repo` is a key/value store with no `Row` struct.
//! - No repo currently has `list_paginated`.
//! - The upsert variants are all subtly different (LWW-gated,
//!   content-diff-gated, simple `INSERT OR IGNORE`, etc.) so unifying
//!   them under one trait would force every site to opt out via a
//!   parameterized hook anyway.
//!
//! Per the issue's explicit fallback ("If the abstraction grows messier
//! than the duplication it replaces, BACK OFF") this module ships only
//! the pieces that genuinely deduplicate without forcing call sites to
//! contort their semantics:
//!
//! - [`SingleIdEntity`] — the minimal trait: table name, column slice,
//!   row mapper. Implementations are tiny.
//! - [`get_by_id`] — shared `SELECT … WHERE id = ?1` returning
//!   `Result<Option<E>, StoreError>` with `prepare_cached` reuse.
//! - [`delete_by_id`] — shared `DELETE … WHERE id = ?1` returning
//!   `Result<usize, StoreError>` with `prepare_cached` reuse.
//!
//! Per-entity files keep all specialized SQL (LWW upserts, JOIN-with-
//! counts queries, by-name lookups, list-with-counts aggregates).
//! Future entities that grow a clean single-id shape (habits,
//! calendar_events, etc.) can opt in by adding one `impl
//! SingleIdEntity` block.

use rusqlite::{Connection, OptionalExtension};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use super::columns::Columns;
use crate::error::StoreError;

/// An entity whose row is keyed by a single string `id` column. The
/// SELECT / DELETE shapes are derived from the [`Columns`] descriptor.
pub trait SingleIdEntity: Sized {
    /// Column allowlist for this entity. Drives the `SELECT` projection
    /// and the `DELETE` table name. Always shared with the rest of the
    /// codebase via `repositories::columns`.
    const COLUMNS: &'static Columns;

    /// Map a row from `SELECT {COLUMNS.select_clause()}` into the
    /// owned entity type. Column indices must match `COLUMNS.all`.
    fn from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Self>;
}

/// Cache one rendered `SELECT` / `DELETE` SQL string per `(table,
/// kind)` so the prepare-cache key stays byte-stable across calls.
///
/// `prepare_cached` keys off the SQL string identity, so allocating a
/// fresh `format!` on every call would defeat the cache. Holding the
/// rendered strings in a process-wide map mirrors what each per-entity
/// repo does today via its own `OnceLock<String>`.
fn cached_sql(kind: SqlKind, columns: &Columns) -> &'static str {
    static CACHE: OnceLock<Mutex<HashMap<(SqlKind, &'static str), &'static str>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    let key = (kind, columns.table);
    if let Some(s) = cache
        .lock()
        .expect("entity_repo SQL cache poisoned")
        .get(&key)
    {
        return s;
    }
    let rendered: String = match kind {
        SqlKind::SelectById => format!(
            "SELECT {} FROM {} WHERE id = ?1",
            columns.select_clause(),
            columns.table
        ),
        SqlKind::DeleteById => format!("DELETE FROM {} WHERE id = ?1", columns.table),
    };
    // Leak so the SQL lives for the process lifetime — same cost
    // pattern the per-entity `OnceLock<String>` declarations had,
    // and `prepare_cached` needs a `&'static str` to remain a stable
    // cache key.
    let leaked: &'static str = Box::leak(rendered.into_boxed_str());
    cache
        .lock()
        .expect("entity_repo SQL cache poisoned")
        .insert(key, leaked);
    leaked
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum SqlKind {
    SelectById,
    DeleteById,
}

/// `SELECT … FROM <table> WHERE id = ?1` returning `None` when no row
/// matches. The SQL is rendered from `E::COLUMNS` and cached, so
/// `prepare_cached` reuses the parsed plan across calls.
pub fn get_by_id<E: SingleIdEntity>(conn: &Connection, id: &str) -> Result<Option<E>, StoreError> {
    let sql = cached_sql(SqlKind::SelectById, E::COLUMNS);
    Ok(conn
        .prepare_cached(sql)?
        .query_row([id], E::from_row)
        .optional()?)
}

/// `DELETE FROM <table> WHERE id = ?1`, returning the affected-row
/// count (0 when no matching row existed; otherwise 1 — the primary
/// key guarantees at most one match).
pub fn delete_by_id<E: SingleIdEntity>(conn: &Connection, id: &str) -> Result<usize, StoreError> {
    let sql = cached_sql(SqlKind::DeleteById, E::COLUMNS);
    Ok(conn.prepare_cached(sql)?.execute([id])?)
}
