//! Shared AI changelog read repository.
//!
//! `ai_changelog` is the audit surface for assistant-originated writes.
//! Keep the filtering SQL here so MCP and CLI diagnostics do not drift.

use std::num::NonZeroU32;

use crate::error::StoreError;
use crate::repositories::ai_changelog_actor_filter::{
    ai_changelog_assistant_actor_filter_sql, ai_changelog_assistant_actor_filter_sql_for_alias,
};
use lorvex_domain::naming::EntityKind;
use rusqlite::{params_from_iter, types::Value as SqlValue, Connection};

/// Query parameters for [`list_ai_changelog`].
///
/// derived `Default`, which built a
/// structurally-invalid `limit: 0`. Production callers used
/// `..AiChangelogQuery::default()` and silently received empty results
/// from `LIMIT 0` clauses. The struct now requires construction via
/// [`AiChangelogQuery::new`] which takes a `NonZeroU32` so a zero
/// limit is rejected at the type system. The new builder-style
/// `with_*` setters preserve the previous spread-update ergonomics
/// without permitting the structurally-invalid empty value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AiChangelogQuery {
    /// Required upper bound on returned rows. Carrying `NonZeroU32`
    /// (rather than `u32`) prevents the silent `LIMIT 0` regression
    /// that motivated dropping `Default`.
    pub limit: NonZeroU32,
    pub entity_type: Option<EntityKind>,
    pub operation: Option<String>,
    pub entity_id: Option<String>,
    pub since: Option<String>,
}

impl AiChangelogQuery {
    /// Construct a query with the required `limit`. Optional filters
    /// default to `None` and are layered on with the `with_*` setters.
    pub const fn new(limit: NonZeroU32) -> Self {
        Self {
            limit,
            entity_type: None,
            operation: None,
            entity_id: None,
            since: None,
        }
    }

    #[must_use]
    pub const fn with_entity_type(mut self, entity_type: EntityKind) -> Self {
        self.entity_type = Some(entity_type);
        self
    }

    #[must_use]
    pub fn with_operation(mut self, operation: impl Into<String>) -> Self {
        self.operation = Some(operation.into());
        self
    }

    #[must_use]
    pub fn with_entity_id(mut self, entity_id: impl Into<String>) -> Self {
        self.entity_id = Some(entity_id.into());
        self
    }

    #[must_use]
    pub fn with_since(mut self, since: impl Into<String>) -> Self {
        self.since = Some(since.into());
        self
    }
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub struct AiChangelogEntry {
    pub id: String,
    pub timestamp: String,
    pub operation: String,
    pub entity_type: EntityKind,
    pub entity_id: Option<String>,
    pub summary: String,
    pub mcp_tool: Option<String>,
    /// Typed preview discriminator. `true` for rows written by
    /// `write_preview_audit_entry` (dispatch_dry_run surfaces) and
    /// the `import_data` dry-run audit row. `false` for the
    /// canonical mutation path. The typed flag is the authoritative
    /// test; substring-matching `mcp_tool LIKE '%_preview'` would be
    /// fragile to a future tool rename.
    pub is_preview: bool,
}

pub fn list_ai_changelog(
    conn: &Connection,
    query: &AiChangelogQuery,
) -> Result<Vec<AiChangelogEntry>, StoreError> {
    // when callers filter by `entity_id`, two row sets must merge:
    //
    //   * Branch A: indexed lookup on `entity_id = ?` (the
    //     single-entity-row case).
    //   * Branch B: rows whose `ai_changelog_entities` registry
    //     carries the target id (the batch / bulk-op case). The
    //     join through `ai_changelog_entities` resolves through
    //     the `(entity_id, changelog_id)` PK so it stays an
    //     indexed seek even on installs with thousands of batch
    //     rows.
    //
    // Non-id filters (entity_type, operation, since, initiated_by)
    // are applied to BOTH branches so the row set matches the
    // single-WHERE semantics exactly. The two branches union via
    // `UNION` (DISTINCT) so a row that matches both surfaces
    // once. ORDER BY + LIMIT live outside the union so the limit
    // bounds the merged set.
    //
    // When `entity_id` is absent we keep a single SELECT — the
    // query already used `idx_changelog_timestamp` correctly.

    let shared = build_shared_filter_clauses(query);

    query.entity_id.as_deref().map_or_else(
        || list_without_entity_id(conn, query, &shared),
        |entity_id| list_with_entity_id(conn, query, entity_id, &shared),
    )
}

/// Branch shared filter set — fragments that apply identically to
/// both UNION arms when filtering by `entity_id`, or to the single
/// SELECT when not. Placeholders use `?` (positional) so the
/// caller binds in fragment order.
struct SharedFilterClauses {
    /// Filter fragment WITHOUT the `WHERE` keyword. Always
    /// includes the literal `initiated_by` predicate; appends
    /// each optional filter.
    bare: String,
    /// Same fragment with column references prefixed `ac.` for use
    /// inside a `FROM ai_changelog ac, json_each(...)` branch.
    aliased: String,
    /// Bindable values, one per `?` in the fragments.
    values: Vec<SqlValue>,
}

fn build_shared_filter_clauses(query: &AiChangelogQuery) -> SharedFilterClauses {
    // Track the bare and aliased forms in lockstep so column
    // prefixes never drift between the two SQL surfaces. The
    // alternative — string-replace at render time — would silently
    // miss any future column reference whose name is a substring
    // of another (`status`/`status_filter`, etc.).
    let mut bare = vec![ai_changelog_assistant_actor_filter_sql()];
    let mut aliased = vec![ai_changelog_assistant_actor_filter_sql_for_alias("ac")];
    let mut values: Vec<SqlValue> = Vec::new();

    if let Some(entity_type) = query.entity_type {
        bare.push("entity_type = ?".to_string());
        aliased.push("ac.entity_type = ?".to_string());
        // Bind the static `&str` from `EntityKind::as_str()` directly —
        // the column stores the canonical wire form so a typed
        // EntityKind is the right shape and avoids the prior
        // `.as_deref().to_owned()` round-trip.
        values.push(SqlValue::Text(entity_type.as_str().to_owned()));
    }
    if let Some(operation) = query.operation.as_deref() {
        bare.push("operation = ?".to_string());
        aliased.push("ac.operation = ?".to_string());
        values.push(SqlValue::Text(operation.to_owned()));
    }
    if let Some(since) = query.since.as_deref() {
        bare.push("timestamp > ?".to_string());
        aliased.push("ac.timestamp > ?".to_string());
        values.push(SqlValue::Text(since.to_owned()));
    }

    SharedFilterClauses {
        bare: bare.join(" AND "),
        aliased: aliased.join(" AND "),
        values,
    }
}

fn list_with_entity_id(
    conn: &Connection,
    query: &AiChangelogQuery,
    entity_id: &str,
    shared: &SharedFilterClauses,
) -> Result<Vec<AiChangelogEntry>, StoreError> {
    // stable tiebreaker on `id DESC` so that
    // same-millisecond timestamps don't ride a non-deterministic
    // table-walk order — the cap on `LIMIT ?` would otherwise
    // randomly drop a row from a multi-write cluster.
    // #3033-M4: project the typed `is_preview` column so consumers
    // can filter previews structurally without depending on the
    // operation-suffix string convention.
    let sql = format!(
        "SELECT id, timestamp, operation, entity_type, entity_id, summary, mcp_tool, is_preview \
         FROM ( \
            SELECT id, timestamp, operation, entity_type, entity_id, summary, mcp_tool, is_preview \
            FROM ai_changelog \
            WHERE entity_id = ? AND {shared_bare} \
            UNION \
            SELECT ac.id, ac.timestamp, ac.operation, ac.entity_type, ac.entity_id, \
                   ac.summary, ac.mcp_tool, ac.is_preview \
            FROM ai_changelog ac \
            JOIN ai_changelog_entities ace ON ace.changelog_id = ac.id \
            WHERE ace.entity_id = ? AND {shared_aliased} \
         ) \
         ORDER BY timestamp DESC, id DESC \
         LIMIT ?",
        shared_bare = shared.bare,
        shared_aliased = shared.aliased,
    );

    let mut params: Vec<SqlValue> = Vec::with_capacity(2 + 2 * shared.values.len() + 1);
    // Branch A bindings.
    params.push(SqlValue::Text(entity_id.to_owned()));
    params.extend(shared.values.iter().cloned());
    // Branch B bindings.
    params.push(SqlValue::Text(entity_id.to_owned()));
    params.extend(shared.values.iter().cloned());
    // Outer LIMIT.
    params.push(SqlValue::Integer(i64::from(query.limit.get())));

    run_changelog_query(conn, &sql, &params)
}

fn list_without_entity_id(
    conn: &Connection,
    query: &AiChangelogQuery,
    shared: &SharedFilterClauses,
) -> Result<Vec<AiChangelogEntry>, StoreError> {
    // see sibling branch — `id DESC` tiebreaker.
    // #3033-M4: project the typed `is_preview` column.
    let sql = format!(
        "SELECT id, timestamp, operation, entity_type, entity_id, summary, mcp_tool, is_preview \
         FROM ai_changelog \
         WHERE {shared_bare} \
         ORDER BY timestamp DESC, id DESC \
         LIMIT ?",
        shared_bare = shared.bare,
    );

    let mut params: Vec<SqlValue> = Vec::with_capacity(shared.values.len() + 1);
    params.extend(shared.values.iter().cloned());
    params.push(SqlValue::Integer(i64::from(query.limit.get())));

    run_changelog_query(conn, &sql, &params)
}

fn run_changelog_query(
    conn: &Connection,
    sql: &str,
    params: &[SqlValue],
) -> Result<Vec<AiChangelogEntry>, StoreError> {
    let mut stmt = conn.prepare_cached(sql)?;
    let entries = stmt
        .query_map(params_from_iter(params.iter()), |row| {
            // #3033-M4: read the typed `is_preview` column. SQLite
            // INTEGER → bool via the standard pattern (any non-zero
            // value → true); the column is `INTEGER NOT NULL DEFAULT
            // 0 CHECK (is_preview IN (0, 1))` so this is safe.
            let is_preview: i64 = row.get(7)?;
            // `entity_type` lands in the row as TEXT. Parse via
            // `try_parse` at the boundary; an unknown value becomes a
            // typed `StoreError::Invariant` carrying the offending
            // string for diagnostics. Closure returns `rusqlite::Error`
            // so wrap the typed error in the rusqlite-compatible shape.
            let entity_type_raw: String = row.get(3)?;
            let entity_type = EntityKind::try_parse(&entity_type_raw).map_err(|err| {
                rusqlite::Error::FromSqlConversionFailure(
                    3,
                    rusqlite::types::Type::Text,
                    Box::new(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!(
                            "ai_changelog.entity_type contains unknown entity kind \
                             {entity_type_raw:?}: {err}"
                        ),
                    )),
                )
            })?;
            Ok(AiChangelogEntry {
                id: row.get(0)?,
                timestamp: row.get(1)?,
                operation: row.get(2)?,
                entity_type,
                entity_id: row.get(4)?,
                summary: row.get(5)?,
                mcp_tool: row.get(6)?,
                is_preview: is_preview != 0,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

#[cfg(test)]
mod tests;
