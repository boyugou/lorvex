//! Compute the next non-excluded recurrence anchor + due_date for
//! the successor task. The walk loops over EXDATE entries
//! (`recurrence_exceptions` JSON) so an exception in the cadence
//! anchor's slot is skipped to the next occurrence rather than
//! producing a successor on the excluded date.
//!
//! Bounded by `MAX_EXDATE_SKIP_ITERATIONS` so a malformed rule
//! that produces a constant cadence cannot trap the spawn loop.

use rusqlite::{params, Connection};

use lorvex_store::calendar_timeline::recurrence::{
    decrement_recurrence_count, inject_bymonthday, next_occurrence_strictly_after,
};
use lorvex_store::StoreError;

use super::super::snapshot::TaskSnapshot;
use super::timezone::today_ymd_in_user_timezone;

/// Outcome of [`compute_next_due_date`]. `None` ⇒ no spawn (rule
/// missing, anchor missing, EXDATE walk exhausted, COUNT exhausted,
/// or an instance with the same composite key already exists from a
/// peer that beat us to the spawn — all of which mean the lifecycle
/// orchestrator returns `None` upstream).
pub(super) struct NextDueDecision {
    pub(super) next_due_date: String,
    /// The recurrence rule the successor row should carry. May be
    /// `decrement_recurrence_count`-modified if the original rule
    /// had a finite `COUNT`.
    pub(super) spawned_recurrence: String,
    /// Today's date in the user's configured timezone. Reused by
    /// the focus-plan rewire so we don't re-resolve the preference.
    pub(super) today_ymd: String,
}

pub(super) fn compute_next_due_date(
    conn: &Connection,
    snap: &TaskSnapshot,
    now: &str,
) -> Result<Option<NextDueDecision>, StoreError> {
    let Some(rule) = snap.recurrence.as_deref() else {
        return Ok(None);
    };
    let group_id = snap.recurrence_group_id.as_deref();

    // Use canonical_occurrence_date as the sole cadence anchor.
    // All write surfaces enforce this is non-null for recurring tasks.
    let Some(cadence_anchor_typed) = snap.canonical_occurrence_date else {
        return Ok(None);
    };
    // Re-render as `String` once so the legacy `&str`-shaped recurrence
    // helpers below (`inject_bymonthday`,
    // `next_occurrence_strictly_after`, `generate_instance_key`) keep
    // their existing string-domain signatures. The typed wrapper
    // guarantees this re-render is exactly the canonical
    // `YYYY-MM-DD` form the column was stored in.
    let cadence_anchor = cadence_anchor_typed.to_string();

    // Inject BYMONTHDAY for MONTHLY/YEARLY rules that lack it,
    // anchored to the canonical occurrence date (not the potentially-deferred due_date).
    let enriched_rule =
        inject_bymonthday(rule, &cadence_anchor)?.unwrap_or_else(|| rule.to_string());

    // Compute timezone-aware "today" from the user's preference (audit S4
    // — delegates to the canonical domain helper rather than the historical
    // local fallback that silently substituted UTC).
    let today_ymd = today_ymd_in_user_timezone(conn, now)?;

    // Parse recurrence exceptions (EXDATE) into a set for O(1) lookup.
    // canonical parser at the crate level — see
    // `lorvex_store::recurrence_exceptions` for the rationale and
    // the two sibling call sites.
    let exclusion_set = lorvex_store::recurrence_exceptions::parse_exception_dates_as_set(
        snap.recurrence_exceptions.as_deref(),
    )
    .map_err(|e| StoreError::Serialization(format!("malformed recurrence_exceptions JSON: {e}")))?;

    // Find the next non-excluded occurrence. Loop to skip EXDATE dates.
    let mut candidate_anchor = cadence_anchor;
    let mut next_due_date: Option<String> = None;
    const MAX_EXDATE_SKIP_ITERATIONS: usize = 1000;
    for _ in 0..MAX_EXDATE_SKIP_ITERATIONS {
        let Some(candidate) =
            next_occurrence_strictly_after(&enriched_rule, &candidate_anchor, &today_ymd)?
        else {
            break;
        };
        if !exclusion_set.contains(&candidate) {
            next_due_date = Some(candidate);
            break;
        }
        // Advance the anchor to the excluded date so the next iteration
        // looks strictly after it.
        candidate_anchor = candidate;
    }

    let Some(next_due_date) = next_due_date else {
        return Ok(None);
    };

    let instance_key = group_id
        .and_then(|gid| lorvex_domain::recurrence::generate_instance_key(gid, &next_due_date));

    // Check for existing instance with this key (cross-device spawn dedup).
    if let Some(ref key) = instance_key {
        let exists: bool = conn
            .prepare_cached(
                "SELECT EXISTS(SELECT 1 FROM tasks WHERE recurrence_instance_key = ?1)",
            )?
            .query_row(params![key], |row| row.get(0))?;
        if exists {
            return Ok(None);
        }
    }

    // Compute spawned recurrence (decrement COUNT if applicable).
    let spawned_recurrence = decrement_recurrence_count(&enriched_rule)?;

    // COUNT exhausted — this was the last occurrence, no successor should be spawned.
    let Some(spawned_recurrence) = spawned_recurrence else {
        return Ok(None);
    };

    Ok(Some(NextDueDecision {
        next_due_date,
        spawned_recurrence,
        today_ymd,
    }))
}
