//! Public entry point: stamp a fresh `version` on the entity row,
//! routing simple-PK entities through [`simple_pk_sql`] and
//! composite-PK edges through [`stamp_composite_entity_version`].

use rusqlite::Connection;

use super::composite::stamp_composite_entity_version;
use super::error::VersionStampError;
use super::predicates::classify_post_update_existing;
use super::simple_pk::simple_pk_sql;

/// Stamp a fresh `version` value on the entity row in the database.
///
/// For simple-PK entities (tasks, lists, etc.) this is a direct UPDATE.
/// For composite-PK entities (edges like task_tag), the `entity_id` uses
/// the `a:b` convention and is split accordingly.
///
/// Known no-version entities are explicitly exempted.
/// All other failures surface so callers do not enqueue sync envelopes with
/// stale local versions.
///
/// when the UPDATE affects 0 rows AND the row exists,
/// returns `VersionStampError::Superseded` (instead of silently
/// returning `Ok(())`) so the caller can re-read the row's current
/// version and re-enqueue at the latest stamp. The previous shape
/// surfaced concurrent-writer races as a silent stale envelope —
/// the outbox row carried an HLC that did not match the row state,
/// peers either rejected it as LWW-stale or applied it on top of a
/// newer in-flight envelope, and the cluster diverged silently.
pub fn stamp_entity_version(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> Result<(), VersionStampError> {
    if let Some(sql) = simple_pk_sql(entity_type) {
        // guard against version regression under
        // concurrent writers. Without the `?1 > version` predicate a
        // slower transaction with an older HLC could overwrite a
        // faster concurrent writer's newer version, causing local
        // LWW to silently accept stale remote envelopes. HLC strings
        // lex-compare correctly; `version IS NULL` handles legacy
        // rows written before this column was populated.
        //
        // route through `prepare_cached`. The
        // `simple_pk_sql` table has ~15 entity types, so the cache
        // hits at perfect rate on the second call onward — every
        // outbox enqueue traverses exactly this path.
        let rows = {
            let mut stmt = conn.prepare_cached(&sql.update)?;
            stmt.execute(rusqlite::params![version, entity_id])?
        };
        if rows == 0 {
            // distinguish three cases:
            //   1. row missing → `EntityNotFound`
            //   2. row present + existing version is strictly newer
            //      → `Superseded { existing_version }` (typed race)
            //   3. row present + existing version is NULL or equal
            //      to the stamp → defensive `Ok(())` (the UPDATE
            //      predicate `?1 > version` excludes equality;
            //      reaching this branch with a non-newer existing
            //      version implies another writer raced us at the
            //      *same* version, which is harmless).
            // First read the existing version. The column is `NOT
            // NULL` per `SYNCABLE_ENTITY_VERSION_IS_NOT_NULL` so the
            // inner `Option<String>` is structurally always `Some` —
            // the wrapping is retained as defense-in-depth for
            // replays against externally-truncated DBs.
            // `QueryReturnedNoRows` means the row is gone.
            //
            // mirror the cached-prepare on the
            // UPDATE path above: the read SQL is one of ~15 fixed
            // strings keyed by entity type, so caching keeps the
            // prepare cost amortized across every Superseded fallback.
            let existing: Option<Option<String>> = {
                let mut stmt = conn.prepare_cached(&sql.read_version)?;
                match stmt.query_row(rusqlite::params![entity_id], |row| {
                    row.get::<_, Option<String>>(0)
                }) {
                    Ok(v) => Some(v),
                    Err(rusqlite::Error::QueryReturnedNoRows) => None,
                    Err(other) => return Err(other.into()),
                }
            };
            return classify_post_update_existing(existing, entity_type, entity_id, version);
        }
        Ok(())
    } else {
        stamp_composite_entity_version(conn, entity_type, entity_id, version)
    }
}
