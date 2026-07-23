//! Shared repository modules for typed CRUD operations.
//!
//! Each sub-module owns the SQL for one entity type. Both the Tauri app and the
//! MCP server delegate to these functions instead of embedding their own SQL.
//!
//! ## Naming convention
//!
//! Function names encode shape AND result cardinality. Stick to this
//! vocabulary so callers can predict the signature from the name alone:
//!
//! | Prefix | Returns | Example |
//! | ------------ | ----------------------------------- | ------------------------------------ |
//! | `get_<x>` | `Result<Option<Row>, _>` for one | `list_repo::get_list` |
//! | `get_<x>s` | `Result<Vec<Row>, _>` (unbounded) | `list_repo::get_all_lists` |
//! | `count_<x>s` | `Result<i64, _>` row count | `read::count_archived_tasks` |
//! | `list_<x>s` | Paginated read returning a typed | `read::list_tasks` |
//! | | result envelope (`{rows, total}`) | |
//! | `search_<x>` | Read with a free-text predicate | `read::search_tasks_with_fallback` |
//! | `create_<x>` | Insert one row, return inserted | `list_repo::create_list` |
//! | | `Row` (M2 standardized) | `write::create_task` |
//! | `update_<x>` | LWW-gated UPDATE; returns | `list_repo::update_list_patched` |
//! | | `Result<(), StoreError>` and raises | |
//! | | `StaleVersion` when the gate rejects | |
//! | | the write (no rows changed). | |
//! | `delete_<x>` | DELETE; return rows-deleted `usize` | `list_repo::delete_list` |
//! | | (M1 standardized). | `preference_repo::clear_preference` |
//! | `apply_<x>` | Driven by a typed patch struct, | `write::apply_task_update` |
//! | | dynamic SET-clause builder. | |
//! | `insert_<x>` | UPSERT (`ON CONFLICT DO UPDATE`), | `calendar_links::insert_link` |
//! | | typically returns `(Row, applied)`. | |
//!
//! Avoid `fetch_*` and `find_*` here — the Tauri/MCP layers above use
//! `fetch_*` for the IPC adapters that read from a repository and shape
//! results into the IPC type, and the repos themselves stay in the
//! `get/list/count/search/create/update/delete/apply/insert` vocabulary.
//!
//! Rule of thumb: if a name contains `_*_with_conn` it is an
//! application-layer helper (Tauri command's testable entry point),
//! NOT a repository. Repositories take a `&Connection` already.

use lorvex_domain::time::SyncTimestamp;

/// Parse a TEXT column at index `idx` of `row` into [`SyncTimestamp`],
/// surfacing a typed `FromSqlConversionFailure` when the value is not
/// canonical.
///
/// redeclared byte-identically inside every
/// repository module that needed timestamp parsing
/// (`list_repo::parse_list_timestamp`, `tag_repo::parse_tag_timestamp`,
/// `calendar_links::parse_link_timestamp`, plus the
/// inline copies in `memory_repo::row_to_memory_entry` and
/// `memory_revision_repo::row_to_memory_revision`). One source of
/// truth keeps the error-message shape — `"<table>.<column> is not a
/// canonical sync timestamp: <raw>"` — consistent across every reader,
/// and extending the parse contract (e.g. permitting a wider canonical
/// form) lands in one file.
///
/// `table` and `column` are static labels so the resulting
/// `rusqlite::Error::FromSqlConversionFailure` carries enough context
/// to identify the offending row without re-reading the SQL or
/// re-deriving the column index.
///
/// a row that bypassed our write path (manual edit,
/// partial restore) and carries a non-canonical timestamp surfaces
/// here as a typed conversion error rather than silently mis-ordering.
pub(crate) fn parse_sync_timestamp_column(
    row: &rusqlite::Row<'_>,
    idx: usize,
    table: &'static str,
    column: &'static str,
) -> rusqlite::Result<SyncTimestamp> {
    let raw: String = row.get(idx)?;
    SyncTimestamp::parse(&raw).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            idx,
            rusqlite::types::Type::Text,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("{table}.{column} is not a canonical sync timestamp: {raw:?}"),
            )),
        )
    })
}

pub mod ai_changelog_actor_filter;
pub mod ai_changelog_query;
pub mod calendar_event_exceptions;
pub mod calendar_event_export;
pub mod calendar_event_write;
pub mod columns;
pub mod current_focus_items;
pub mod daily_review_ops;
pub mod entity_repo;
pub mod fts;
pub mod list_repo;
pub mod lww_delete;
pub(crate) mod lww_update;
pub mod memory_repo;
pub mod memory_revision_repo;
pub mod preference_repo;
pub mod provider_repo;
pub(crate) mod recurrence_exceptions_common;
pub mod tag_repo;
pub mod task;
