//! Cascading-tombstone helpers — every aggregate whose delete
//! cascades to synced child / edge rows MUST tombstone those rows
//! BEFORE SQLite's `ON DELETE CASCADE` removes them, or peers
//! running an older build never re-push the edges they hadn't
//! themselves modified and the cluster diverges permanently on
//! edge state.
//!
//! `tombstone_composite_edges` covers child rows whose entity_id is
//! the canonical `{parent_id}:{other_id}` composite shape (task_tag,
//! task_dependency, task_calendar_event_link, habit_completion).
//! The `compose_id` closure lets the caller flip the order — task
//! delete fans out task_dependency in BOTH directions, so the
//! predecessor side composes `{other}:{task_id}`.
//!
//! `tombstone_child_rows` covers child entities with their own
//! UUIDv7 PKs (task_reminder, task_checklist_item,
//! habit_reminder_policy).
//!
//! cascade tombstones intentionally do NOT write a per-row
//! `ai_changelog` entry capturing each child / edge row's
//! `before_json`. The audit invariant (#3 in CLAUDE.md) is "every
//! MCP WRITE operation logs to `ai_changelog`" — a sync-side
//! cascade is not an MCP write. The originating peer authored a
//! single `ai_changelog` row at MCP-write time describing the
//! parent delete, and that row is itself synced via the standard
//! `ai_changelog` envelope path (`apply/changelog.rs`). Recording
//! cascade child rows again on every receiving device would (a)
//! duplicate the audit signal, (b) burn retention budget on rows
//! whose intent is already explained by the parent entry, and (c)
//! leak the receiver's local state shape into a log meant to record
//! user / AI intent.

use rusqlite::Connection;

use super::super::ApplyError;

/// pick the larger of two HLC strings (parent's
/// cascade version vs. the child row's own version). On parse
/// failure the parent version wins — the caller already validated
/// `parent_version` upstream, and any local row whose `version`
/// column is malformed is itself corrupt; we'd rather still emit
/// the cascade tombstone than fail the apply batch.
fn max_cascade_version(parent_version: &str, row_version: &str) -> String {
    let Ok(parent_hlc) = lorvex_domain::hlc::Hlc::parse(parent_version) else {
        return parent_version.to_string();
    };
    let Ok(row_hlc) = lorvex_domain::hlc::Hlc::parse(row_version) else {
        return parent_version.to_string();
    };
    if row_hlc > parent_hlc {
        row_version.to_string()
    } else {
        parent_version.to_string()
    }
}

/// each helper SELECTs the row's own `version`
/// column alongside the identity field and stamps the cascade
/// tombstone at `max(parent_version, row_version)`. The previous
/// shape unconditionally stamped at `parent_delete_version` — a
/// concurrent edge upsert at HLC `Vx > Vp` would have its tombstone
/// created at the lower `Vp`, and the next replay of the `Vx`
/// upsert would lift the tombstone (`Vx > Vp`) and silently revive
/// an edge the parent's cascade was supposed to claim. Sourcing the
/// floor from the row's own version closes that gap without
/// forcing every caller to pre-compute a cascade max.
pub(in crate::apply::aggregate) fn tombstone_composite_edges<F>(
    conn: &Connection,
    select_sql: &str,
    parent_id: &str,
    entity_type: &str,
    compose_id: F,
    version: &str,
    deleted_at: &str,
) -> Result<(), ApplyError>
where
    F: Fn(&str) -> String,
{
    // cascade SELECT comes from a small set of `&'static`
    // strings (one per child entity_type), so `prepare_cached` collapses
    // re-preparation across cascades.
    //
    // the `Vec` materialization here is intentional —
    // `create_tombstone` writes back to the same connection inside the
    // loop, and SQLite cannot interleave a write through `conn.execute`
    // while an open `query_map` iterator still holds the read cursor on
    // a parent row. The realistic upper bound is "child rows of one
    // aggregate", which never approaches 10K in practice (a task's
    // dependency / tag / link / reminder count is in the dozens). If a
    // future schema lets a single aggregate own 10K+ children, switch
    // to a chunked SELECT (LIMIT / OFFSET keyed on the child id) so the
    // peak Vec size stays bounded; do NOT keep the read cursor open
    // across the write.
    let mut stmt = conn.prepare_cached(select_sql)?;
    let rows: Vec<(String, String)> = stmt
        .query_map([parent_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    for (other, row_version) in rows {
        let edge_id = compose_id(&other);
        let cascade_version = max_cascade_version(version, &row_version);
        crate::tombstone::create_tombstone(
            conn,
            entity_type,
            &edge_id,
            &cascade_version,
            deleted_at,
            None,
            None,
        )?;
    }
    Ok(())
}

pub(in crate::apply::aggregate) fn tombstone_child_rows(
    conn: &Connection,
    select_sql: &str,
    parent_id: &str,
    entity_type: &str,
    version: &str,
    deleted_at: &str,
) -> Result<(), ApplyError> {
    // same caching rationale as `tombstone_composite_edges`.
    let mut stmt = conn.prepare_cached(select_sql)?;
    let rows: Vec<(String, String)> = stmt
        .query_map([parent_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    for (id, row_version) in rows {
        let cascade_version = max_cascade_version(version, &row_version);
        crate::tombstone::create_tombstone(
            conn,
            entity_type,
            &id,
            &cascade_version,
            deleted_at,
            None,
            None,
        )?;
    }
    Ok(())
}
