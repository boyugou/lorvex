//! List repository — shared query implementations for the `lists` table.
//!
//! Used by both the Tauri app and the MCP server. All list queries go through
//! these functions so the SQL logic exists in exactly one place.

use lorvex_domain::time::SyncTimestamp;
use lorvex_domain::{ListId, Patch};
use rusqlite::{params, Connection};

use super::entity_repo::{self, SingleIdEntity};
use super::parse_sync_timestamp_column;

use crate::error::StoreError;

// ---------------------------------------------------------------------------
// Row type
// ---------------------------------------------------------------------------

/// A row read from the `lists` table. Mirrors the full column set.
///
/// `created_at` and `updated_at` are now [`SyncTimestamp`]
/// rather than bare `String`. Same rationale as `MemoryEntry::updated_at`
/// and
/// `lorvex_store::repositories::ai_changelog_query::AiChangelogEntry::timestamp`:
/// every consumer that ordered or compared list rows lex-compared strings,
/// which silently
/// misorders when one device emits 3-fractional-digit timestamps and
/// another emits 6. `SyncTimestamp` flips ordering onto the underlying
/// `DateTime<Utc>` while keeping the JSON wire shape byte-identical
/// (custom `Serialize` round-trips through the canonical millisecond-Z
/// form).
#[derive(Debug, Clone)]
pub struct ListRow {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub ai_notes: Option<String>,
    pub created_at: SyncTimestamp,
    pub updated_at: SyncTimestamp,
    pub version: String,
    pub archived_at: Option<SyncTimestamp>,
    pub position: i64,
}

/// Column list for SELECT queries. Matches the field order in `<ListRow as SingleIdEntity>::from_row`.
///
/// promoted to a single declaration in
/// [`crate::repositories::columns::LISTS`] so the Tauri `LIST_COLS`
/// shadow can reference the same source.
const LIST_COLUMNS: &str = crate::repositories::columns::LISTS.select_clause;

/// Table-qualified column list for JOIN queries. Same order as `LIST_COLUMNS`.
///
/// rendered at construction-time from the same
/// canonical list. The qualified rendering allocates once at function
/// scope (the `LazyLock` keeps it cached for the process lifetime) so
/// callers can keep substituting it into format strings.
static LIST_COLUMNS_QUALIFIED: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| crate::repositories::columns::LISTS.select_clause_qualified("l"));

impl SingleIdEntity for ListRow {
    const COLUMNS: &'static crate::repositories::columns::Columns =
        &crate::repositories::columns::LISTS;

    fn from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Self> {
        Ok(ListRow {
            id: row.get(0)?,
            name: row.get(1)?,
            color: row.get(2)?,
            icon: row.get(3)?,
            description: row.get(4)?,
            ai_notes: row.get(5)?,
            created_at: parse_sync_timestamp_column(row, 6, "lists", "created_at")?,
            updated_at: parse_sync_timestamp_column(row, 7, "lists", "updated_at")?,
            version: row.get(8)?,
            archived_at: parse_optional_sync_timestamp_column(row, 9, "lists", "archived_at")?,
            position: row.get(10)?,
        })
    }
}

fn parse_optional_sync_timestamp_column(
    row: &rusqlite::Row<'_>,
    idx: usize,
    table: &'static str,
    column: &'static str,
) -> rusqlite::Result<Option<SyncTimestamp>> {
    let raw: Option<String> = row.get(idx)?;
    raw.map(|value| {
        SyncTimestamp::parse(&value).ok_or_else(|| {
            rusqlite::Error::FromSqlConversionFailure(
                idx,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("{table}.{column} is not a canonical sync timestamp: {value:?}"),
                )),
            )
        })
    })
    .transpose()
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

/// Get all lists, ordered by name.
pub fn get_all_lists(conn: &Connection) -> Result<Vec<ListRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql =
        SQL.get_or_init(|| format!("SELECT {LIST_COLUMNS} FROM lists ORDER BY name ASC, id ASC"));
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map([], ListRow::from_row)?;
    Ok(rows.collect::<Result<_, rusqlite::Error>>()?)
}

/// Get a single list by ID.
///
/// Returns `None` if no list with the given ID exists.
///
/// Delegates to [`entity_repo::get_by_id`] — the SELECT shape is the
/// generic single-id pattern shared with every other entity that
/// implements [`SingleIdEntity`].
pub fn get_list(conn: &Connection, list_id: &ListId) -> Result<Option<ListRow>, StoreError> {
    entity_repo::get_by_id::<ListRow>(conn, list_id.as_str())
}

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/// Create a new list and return the inserted row.
///
/// `ai_notes` is optional; when `None` the column is stored as NULL.
pub fn create_list(
    conn: &Connection,
    id: &ListId,
    name: &str,
    color: Option<&str>,
    icon: Option<&str>,
    description: Option<&str>,
    version: &str,
) -> Result<ListRow, StoreError> {
    create_list_with_ai_notes(
        conn,
        ListCreateParams {
            id,
            name,
            color,
            icon,
            description,
            ai_notes: None,
            version,
        },
    )
}

pub struct ListCreateParams<'a> {
    pub id: &'a ListId,
    pub name: &'a str,
    pub color: Option<&'a str>,
    pub icon: Option<&'a str>,
    pub description: Option<&'a str>,
    pub ai_notes: Option<&'a str>,
    pub version: &'a str,
}

/// Create a new list with an optional `ai_notes` field and return the inserted row.
pub fn create_list_with_ai_notes(
    conn: &Connection,
    params: ListCreateParams<'_>,
) -> Result<ListRow, StoreError> {
    // Canonical millisecond `Z` form via `sync_timestamp_now()`. `created_at`
    // is lex-sorted by `get_all_lists_with_counts` (`ORDER BY
    // l.created_at ASC`), and sync apply writes the same column in
    // canonical format from other devices. Mixed precision would
    // flip the sort at the fractional-second boundary — same lex
    // drift class as R11/R12/R13.
    let now = lorvex_domain::sync_timestamp_now();
    // RETURNING the inserted row in a single round-trip avoids the
    // separate `get_list()` SELECT this function pay.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "INSERT INTO lists ({LIST_COLUMNS}) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, ?8, NULL, 0) \
             RETURNING {LIST_COLUMNS}"
        )
    });
    conn.prepare_cached(sql)?
        .query_row(
            params![
                params.id.as_str(),
                params.name,
                params.color,
                params.icon,
                params.description,
                params.ai_notes,
                now,
                params.version
            ],
            ListRow::from_row,
        )
        .map_err(StoreError::from)
}

pub struct ListUpdateParams<'a> {
    pub id: &'a ListId,
    pub name: Option<&'a str>,
    pub color: Option<&'a str>,
    pub icon: Option<&'a str>,
    pub description: Option<&'a str>,
    pub now: &'a str,
    pub version: &'a str,
}

/// Update a list. Only non-`None` fields are modified.
///
/// Delegates to [`update_list_patched`] — no SQL of its own.
pub fn update_list(conn: &Connection, params: ListUpdateParams<'_>) -> Result<(), StoreError> {
    let patch = ListUpdatePatch {
        name: params.name,
        color: params.color.map_or(Patch::Unset, Patch::Set),
        icon: params.icon.map_or(Patch::Unset, Patch::Set),
        description: params.description.map_or(Patch::Unset, Patch::Set),
        ai_notes: Patch::Unset,
    };
    update_list_patched(conn, params.id, &patch, params.version, params.now)
}

/// Patch for updating a list. All fields are optional.
/// Each nullable field uses [`Patch<&str>`] — `Patch::Unset` skips,
/// `Patch::Clear` writes SQL NULL, `Patch::Set(v)` writes the value.
#[derive(Debug, Clone, Default)]
pub struct ListUpdatePatch<'a> {
    pub name: Option<&'a str>,
    pub color: Patch<&'a str>,
    pub icon: Patch<&'a str>,
    pub description: Patch<&'a str>,
    pub ai_notes: Patch<&'a str>,
}

/// Update a list using the patch struct. All nullable fields use
/// [`Patch<&str>`] for explicit three-state PATCH semantics.
///
/// Returns `Ok(())` when the LWW gate accepted the write (or the patch
/// was empty so nothing was attempted), and [`StoreError::StaleVersion`]
/// when the gate rejected the write because the patch's `version` was
/// not strictly newer than the row's current `version`.
///
/// - `Patch::Unset` = skip field
/// - `Patch::Clear` = set to NULL
/// - `Patch::Set(v)` = set to value
///
/// `name` uses `Option<&str>` because it is NOT NULL in the schema.
///
/// `version` is always written alongside `updated_at` so that sync LWW
/// semantics are preserved on every update.
pub fn update_list_patched(
    conn: &Connection,
    list_id: &ListId,
    patch: &ListUpdatePatch<'_>,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    // build SET clause and parameters using **named**
    // SQLite binds (`:list_id`, `:version`, etc.) rather than the
    // previous arithmetic-derived numbered placeholders. The previous
    // shape computed `version_idx = id_idx - 2` to reuse the appended
    // version bind in the WHERE clause; one push reordering or one
    // new optional SET column inserted between two existing ones
    // would silently shift the LWW comparison to bind against the
    // wrong column. Named binds lock each comparison to its column
    // name regardless of how the SET clause is built.
    // 5 patch columns + 3 always-bound (`list_id`, `version`, `now`).
    // Pre-sizing skips the 4 → 8 reallocs Vec would do for fully
    // populated patches.
    let mut set_clauses: Vec<&str> = Vec::with_capacity(5);
    let mut params: Vec<(&str, &dyn rusqlite::types::ToSql)> = Vec::with_capacity(8);
    params.push((":list_id", list_id));
    params.push((":version", &version));
    params.push((":now", &now));

    if let Some(ref name) = patch.name {
        set_clauses.push("name = :name");
        params.push((":name", name));
    }
    // `Option<&str>: ToSql` maps `None` → SQL NULL; `Patch::as_bind_value()`
    // collapses `Set(v)` → `Some(v)` and `Clear` → `None` so we route
    // both states through the same bind. `Unset` skips entirely.
    let color_bind: Option<&str> = patch.color.as_bind_value().copied();
    if patch.color.is_set_or_clear() {
        set_clauses.push("color = :color");
        params.push((":color", &color_bind));
    }
    let icon_bind: Option<&str> = patch.icon.as_bind_value().copied();
    if patch.icon.is_set_or_clear() {
        set_clauses.push("icon = :icon");
        params.push((":icon", &icon_bind));
    }
    let description_bind: Option<&str> = patch.description.as_bind_value().copied();
    if patch.description.is_set_or_clear() {
        set_clauses.push("description = :description");
        params.push((":description", &description_bind));
    }
    let ai_notes_bind: Option<&str> = patch.ai_notes.as_bind_value().copied();
    if patch.ai_notes.is_set_or_clear() {
        set_clauses.push("ai_notes = :ai_notes");
        params.push((":ai_notes", &ai_notes_bind));
    }

    if set_clauses.is_empty() {
        // Empty patch: no SET clauses to write. Treat as a successful
        // no-op rather than running an UPDATE that would always match
        // zero rows (which would be indistinguishable from a stale-
        // version miss). Callers that need a "did anything change"
        // signal should branch on the patch shape themselves before
        // calling — every existing caller already does, because the
        // changelog / outbox enqueue is also gated on the patch carrying
        // at least one field.
        return Ok(());
    }

    set_clauses.push("version = :version");
    set_clauses.push("updated_at = :now");

    // gate the UPDATE by `:version > lists.version` so a
    // stale local update can't clobber a newer remote one.
    // `RETURNING 1` + `query_row` lets `execute_lww_update`
    // translate the LWW miss (`QueryReturnedNoRows`) into
    // `StaleVersion`, retiring the duplicated `if changed == 0 { … }`
    // branches every caller carry.
    let sql = format!(
        "UPDATE lists SET {} WHERE id = :list_id AND :version > lists.version RETURNING 1",
        set_clauses.join(", ")
    );

    crate::repositories::lww_update::execute_lww_update(
        conn,
        &sql,
        params.as_slice(),
        lorvex_domain::naming::ENTITY_LIST,
        list_id.as_str(),
    )
}

/// Delete a list by ID. Returns the affected-row count (0 when no
/// matching row existed; otherwise 1).
///
/// Delegates to [`entity_repo::delete_by_id`] — the DELETE shape is
/// the generic single-id pattern shared with every other entity that
/// implements [`SingleIdEntity`].
pub fn delete_list(conn: &Connection, id: &ListId) -> Result<usize, StoreError> {
    entity_repo::delete_by_id::<ListRow>(conn, id.as_str())
}

pub fn delete_list_lww(conn: &Connection, id: &ListId, version: &str) -> Result<usize, StoreError> {
    crate::repositories::lww_delete::execute_lww_delete_by_id(
        conn,
        "lists",
        "id",
        lorvex_domain::naming::ENTITY_LIST,
        id.as_str(),
        version,
    )
}

/// Count active (non-trashed) tasks still assigned to a list, regardless of status.
///
/// The filter excludes `archived_at IS NOT NULL` rows so the "cannot
/// delete list while N task(s) are still assigned" gate at every
/// caller (MCP `delete_list`, CLI `delete-list`, Tauri `delete_list`)
/// ignores rows in Trash. Without this the user would be stuck unable
/// to delete a list whose only remaining "tasks" have been moved to
/// Trash — a `restore_task_from_trash` round-trip would put them back
/// in the (still-existing) list, but if the user has already moved on
/// the list would be permanent garbage. Active tasks (status
/// independent: open/completed/cancelled/someday) still block
/// deletion.
pub fn count_assigned_tasks_in_list(
    conn: &Connection,
    list_id: &ListId,
) -> Result<i64, StoreError> {
    Ok(conn
        .prepare_cached("SELECT COUNT(*) FROM tasks WHERE list_id = ?1 AND archived_at IS NULL")?
        .query_row([list_id.as_str()], |row| row.get(0))?)
}

// ---------------------------------------------------------------------------
// Aggregate row types
// ---------------------------------------------------------------------------

/// A list row enriched with task counts. Used by the list-listing endpoints
/// in both the Tauri app and the MCP server.
#[derive(Debug, Clone)]
pub struct ListWithCounts {
    pub list: ListRow,
    /// Number of open tasks assigned to this list.
    pub open_count: i64,
    /// Number of task rows still assigned to this list, regardless of status.
    pub total_count: i64,
}

#[derive(Debug, Clone)]
pub struct ListsWithCountsPage {
    pub rows: Vec<ListWithCounts>,
    pub total_matching: i64,
}

/// Get all lists with their task counts, ordered by `created_at ASC`.
///
/// This is the canonical query for "list all lists with counts" used by
/// both the Tauri sidebar and the MCP `list_lists` tool.
///
/// The counts use correlated subqueries so each one binds to the
/// `idx_tasks_list_status_priority_due` index (leading columns
/// `(list_id, status)`) and stays index-bound rather than scanning
/// the tasks table the way a `LEFT JOIN tasks + GROUP BY` would.
pub fn get_all_lists_with_counts(conn: &Connection) -> Result<Vec<ListWithCounts>, StoreError> {
    Ok(get_lists_with_counts_page(conn, None)?.rows)
}

/// Get lists with task counts and optional row cap.
pub fn get_lists_with_counts_page(
    conn: &Connection,
    limit: Option<usize>,
) -> Result<ListsWithCountsPage, StoreError> {
    let total_matching: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM lists")?
        .query_row([], |row| row.get(0))?;

    // The SQL is fully static once the `LIST_COLUMNS_QUALIFIED`
    // projection is folded in, and this helper backs sidebar bootstrap
    // plus every Tauri/MCP/CLI list-listing call. Cache the rendered
    // string in a `OnceLock` so the planner cost AND the per-call
    // format! allocation both stay off the hot path.
    static ALL_SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    static CAPPED_SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let base_sql = || {
        let qualified = LIST_COLUMNS_QUALIFIED.as_str();
        format!(
            "SELECT {qualified}, \
             (SELECT COUNT(*) FROM tasks t \
              WHERE t.list_id = l.id AND t.status = 'open' AND t.archived_at IS NULL) AS open_count, \
             (SELECT COUNT(*) FROM tasks t \
              WHERE t.list_id = l.id AND t.archived_at IS NULL) AS total_count \
             FROM lists l \
             ORDER BY l.created_at ASC, l.id ASC",
        )
    };
    let sql = match limit {
        Some(_) => CAPPED_SQL.get_or_init(|| format!("{} LIMIT ?1", base_sql())),
        None => ALL_SQL.get_or_init(base_sql),
    };
    let mut stmt = conn.prepare_cached(sql)?;
    let map_row = |row: &rusqlite::Row<'_>| {
        Ok(ListWithCounts {
            list: ListRow::from_row(row)?,
            open_count: row.get(11)?,
            total_count: row.get(12)?,
        })
    };
    let rows = match limit {
        Some(limit) => stmt
            .query_map([limit as i64], map_row)?
            .collect::<Result<_, rusqlite::Error>>()?,
        None => stmt
            .query_map([], map_row)?
            .collect::<Result<_, rusqlite::Error>>()?,
    };

    Ok(ListsWithCountsPage {
        rows,
        total_matching,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
