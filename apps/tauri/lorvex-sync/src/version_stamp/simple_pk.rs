//! Simple-PK SQL dispatch table: maps each [`EntityKind`] with a
//! `(table, pk_col)` pair to its prepared LWW-guarded UPDATE and
//! `read_version` SELECT.

use lorvex_domain::naming::EntityKind;

use super::SYNCABLE_ENTITY_VERSION_IS_NOT_NULL;

/// Per-simple-PK-entity prepared SQL pair used by
/// `stamp_entity_version`. The shape is fixed — `?1` always binds
/// version, `?2` always binds the PK — so callers don't need to know
/// which column is the PK.
///
/// held two `&'static str` literals per
/// EntityKind arm (19 nearly-identical pairs spelling out
/// `"UPDATE <table> SET version = ?1 WHERE <pk> = ?2 AND …"` and
/// `"SELECT version FROM <table> WHERE <pk> = ?1"`). The strings now
/// derive from `EntityKind::table_pk()` via `format!`, with the
/// `assert_safe_sql_identifier` panic guards re-introduced to pin the
/// invariant that `table` and `pk_col` are bare SQL identifiers (true
/// today — every value comes from a `&'static str` constant in
/// [`lorvex_domain::naming`] — but the asserts protect against a
/// future contributor swapping in a dynamic source).
pub(super) struct SimplePkSql {
    /// LWW-guarded UPDATE (`?1 > version OR version IS NULL`).
    pub(super) update: String,
    /// reads the row's current `version` so a
    /// superseded stamp can populate the typed
    /// `VersionStampError::Superseded { existing_version }` instead
    /// of silently swallowing the race. `Option<Option<String>>`
    /// distinguishes all three cases simple-PK callers care about
    /// (row absent → `Err(QueryReturnedNoRows)`, row with NULL
    /// version → `Ok(None)`, row with version → `Ok(Some(s))`), so
    /// the previous `count` SELECT was always redundant and is
    /// removed.
    pub(super) read_version: String,
}

/// Returns the prepared SQL pair for a simple-PK entity, or `None`
/// for composite-PK / unsupported types.
///
/// Returns a `&'static SimplePkSql` from a process-wide cache so the
/// hot outbox-enqueue path (every upsert calls this once) skips the
/// per-call `format!` allocation that produced two ~80-byte Strings
/// per stamp. The cache is populated lazily on first lookup of each
/// `EntityKind` and lives for the process lifetime — every
/// subsequent stamp for the same entity returns the same `&str`
/// pair into `prepare_cached`.
///
/// The cache key is the `EntityKind` enum value, derived from the
/// `&str` argument via `EntityKind::parse`. Both `(table, pk_col)`
/// pairs come from `&'static str` constants in
/// [`lorvex_domain::naming`]; the `assert_safe_sql_identifier` guards
/// pin the bare-identifier invariant against a future contributor
/// swapping in a dynamic source.
///
/// A future maintainer who adds a new syncable kind without giving
/// it a `(table, pk_col)` mapping fails at the call site (returning
/// `None` from `table_pk()`) instead of silently falling through to
/// a missing UPDATE.
pub(super) fn simple_pk_sql(entity_type: &str) -> Option<&'static SimplePkSql> {
    use std::collections::HashMap;
    use std::sync::OnceLock;

    static CACHE: OnceLock<HashMap<EntityKind, SimplePkSql>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| {
        // `version` is `NOT NULL` on every syncable entity table per
        // `001_schema.sql`; the historical `OR version IS NULL` LWW
        // branch was unreachable. Pin the invariant via
        // [`SYNCABLE_ENTITY_VERSION_IS_NOT_NULL`] so a future column
        // nullability change surfaces here rather than silently
        // re-introducing the dead branch.
        const {
            assert!(
                SYNCABLE_ENTITY_VERSION_IS_NOT_NULL,
                "every syncable entity table must declare `version NOT NULL`; \
                 a `false` here means a new table was added without the constraint",
            );
        }
        let mut map = HashMap::new();
        for et in lorvex_domain::naming::ALL_SYNCABLE_TYPES {
            let Some(kind) = EntityKind::parse(et) else {
                continue;
            };
            let Some((table, pk_col)) = kind.table_pk() else {
                // Composite-PK kinds intentionally skipped here; they
                // route through `stamp_composite_entity_version`.
                continue;
            };
            lorvex_domain::assert_safe_sql_identifier(table);
            lorvex_domain::assert_safe_sql_identifier(pk_col);
            map.insert(
                kind,
                SimplePkSql {
                    update: format!(
                        "UPDATE {table} SET version = ?1 \
                         WHERE {pk_col} = ?2 AND ?1 > version"
                    ),
                    read_version: format!("SELECT version FROM {table} WHERE {pk_col} = ?1"),
                },
            );
        }
        map
    });
    let kind = EntityKind::parse(entity_type)?;
    cache.get(&kind)
}

/// Test-only helper: returns `true` if the entity_type maps to a
/// simple-PK SQL arm. Replaces the old `entity_type_to_table_pk`
/// helper used by tests to verify coverage.
#[cfg(test)]
pub(super) fn simple_pk_supported(entity_type: &str) -> bool {
    simple_pk_sql(entity_type).is_some()
}
