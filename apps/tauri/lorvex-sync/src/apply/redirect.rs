//! Tombstone redirect-chain walker + payload identity-rewrite helpers.
//!
//! Both `apply_envelope` and `promote_one_shadow` chase the same
//! `sync_tombstones.redirect_entity_id` chain when resolving an
//! inbound envelope to its current target, and the per-hop payload-FK
//! rewrite uses the same field table for both call sites. Centralizing
//! the chain walker, the per-hop record, and the identity-remap
//! functions keeps the two callers in lockstep.

use rusqlite::Connection;

use lorvex_domain::naming;

use super::error::REDIRECT_CHAIN_CAP;
use super::ApplyError;

/// a single hop along a tombstone redirect chain.
///
/// Both `apply_envelope` and `promote_one_shadow` need the same
/// per-hop information when chasing a chain of merge tombstones —
/// the (from, to) ids to remap composite entity ids and payload FK
/// fields, the chain-spanning entity_type so a cross-type redirect
/// (task→habit) lands the apply on the correct table, and the
/// tombstone's HLC version so call sites can flag merges authored
/// by the local device for diagnostic attribution. Captured per hop
/// so each caller can apply its own per-hop work without
/// re-walking the chain.
#[derive(Debug, Clone)]
pub(crate) struct RedirectHop {
    /// The entity_type the hop departed from. The chain may cross
    /// types if `redirect_entity_type` differs from the prior hop's
    /// type, e.g. a task→habit merge.
    pub(crate) from_entity_type: String,
    pub(crate) from_entity_id: String,
    /// The entity id the hop landed on. The destination type is
    /// either the next hop's `from_entity_type` (intermediate hops)
    /// or the chase function's returned `final_type` (terminal hop) —
    /// the chase pre-validates every cross-type target via
    /// `EntityKind::is_syncable_kind()` before storing the hop, so
    /// no per-hop reader needs to re-derive it.
    pub(crate) to_entity_id: String,
    /// The tombstone's HLC version. Carried so callers that need to
    /// attribute downstream conflict-log / error-log rows to the
    /// local device when the merge was locally authored can inspect
    /// the suffix.
    pub(crate) version: String,
}

/// shared redirect-chain chase used by both
/// `apply_envelope` and `promote_one_shadow`.
///
/// Walks the `sync_tombstones.redirect_entity_id` chain starting
/// from `(initial_entity_type, initial_entity_id)`, returning:
/// * the final `(entity_type, entity_id)` to apply against (the
///   chain terminus, or the initial pair when no tombstone
///   redirect existed);
/// * the per-hop log so callers can do per-hop work (payload
///   identity rewrites, local-attribution check, etc.).
///
/// Bounded by `REDIRECT_CHAIN_CAP`. After consuming the cap, does
/// ONE more `get_tombstone` probe — if the terminal id still has
/// a redirect, surface `TombstoneRedirectChainTooDeep` so the
/// apply never lands on an intermediate hop.
///
/// Cycles (a redirect chain looping back through an already-visited
/// id, e.g. a self-redirect or a mutual A→B/B→A pair) surface as
/// `TombstoneRedirectCycle` — semantically distinct from a
/// deep-but-acyclic chain.
///
/// Cross-type validation: every hop's `to_entity_type` must parse to
/// an `EntityKind` whose `is_syncable_kind()` is true. A tombstone
/// authored against a retired entity_type or a local-only kind would
/// otherwise silently route the apply to a table we no longer
/// recognize. We surface this as a `UnknownEntityType` error so the
/// apply path skips with a typed reason.
pub(crate) fn chase_redirect_chain(
    conn: &Connection,
    initial_entity_type: &str,
    initial_entity_id: &str,
) -> Result<(String, String, Vec<RedirectHop>), ApplyError> {
    // Defense-in-depth: the per-hop loop validates every cross-type
    // redirect destination via `EntityKind::is_syncable_kind()` (see
    // the match below), and the INITIAL `(entity_type, entity_id)`
    // gets the same guard here so a forgotten upstream check would
    // not silently walk the chain (or skip it entirely when the
    // initial id has no tombstone) against an unknown-type cursor.
    // The function stays self-contained.
    match naming::EntityKind::parse(initial_entity_type) {
        Some(kind) if kind.is_syncable_kind() => {}
        _ => {
            return Err(ApplyError::UnknownEntityType(
                initial_entity_type.to_string(),
            ))
        }
    }
    let mut current_type = initial_entity_type.to_string();
    let mut current_id = initial_entity_id.to_string();
    // perf: chain length is bounded by REDIRECT_CHAIN_CAP (8 today).
    // Pre-size both the hop log and the cycle-detection set so neither
    // grows during the walk.
    let mut hops = Vec::<RedirectHop>::with_capacity(REDIRECT_CHAIN_CAP);
    // visited set seeds with the INITIAL id so a
    // self-redirect in the very first hop is caught immediately
    // rather than slipping past the cycle check by virtue of being
    // the loop's first iteration.
    //
    // perf: at REDIRECT_CHAIN_CAP=8 a linear `iter().any()` over a Vec
    // of (type, id) pairs is cheaper than hashing two heap strings per
    // probe through HashSet. Keeps the visited check on the stack
    // without pulling in a smallvec dep.
    let mut visited: Vec<(String, String)> = Vec::with_capacity(REDIRECT_CHAIN_CAP + 1);
    visited.push((current_type.clone(), current_id.clone()));

    for _ in 0..REDIRECT_CHAIN_CAP {
        let Some(ts) = crate::tombstone::get_tombstone(conn, &current_type, &current_id)? else {
            return Ok((current_type, current_id, hops));
        };
        // perf: take ownership of `redirect_entity_id` rather than
        // cloning — the tombstone struct is dropped at the bottom of
        // the loop body anyway.
        let Some(redirect_id) = ts.redirect_entity_id else {
            // Absolute deletion at the current hop — no further
            // chase. Caller decides what to do with the terminus.
            return Ok((current_type, current_id, hops));
        };
        // Honor `redirect_entity_type`. A cross-type merge tombstone
        // changes the entity_type
        // the next hop reads from. Routing the next `get_tombstone`
        // probe against the SAME `current_type` would land the apply
        // on the wrong table whenever the tombstone explicitly named
        // a new type.
        // perf: take ownership and only clone `current_type` when we
        // actually need to fall back.
        let next_type = ts
            .redirect_entity_type
            .unwrap_or_else(|| current_type.clone());
        // `redirect_entity_type` is a string column on
        // `sync_tombstones` so it has not been through the typed wire
        // boundary; parse explicitly here. A row whose
        // `redirect_entity_type` does not name a known kind, or names
        // a local-only kind that cannot legally appear in sync, is
        // surfaced as `UnknownEntityType` so the apply path skips
        // with a typed reason instead of routing the apply against a
        // table we no longer recognize.
        match naming::EntityKind::parse(&next_type) {
            Some(kind) if kind.is_syncable_kind() => {}
            _ => return Err(ApplyError::UnknownEntityType(next_type)),
        }
        let next_id = remap_entity_id(
            &current_id,
            &ts.entity_id,
            &redirect_id,
            Some(&current_type),
        );
        if visited
            .iter()
            .any(|(t, i)| t == &next_type && i == &next_id)
        {
            return Err(ApplyError::TombstoneRedirectCycle {
                entity_type: current_type,
                entity_id: current_id,
            });
        }
        // perf: sequence the moves so each owned String allocates only
        // once per hop. `from_entity_*` consumes the prior current_*,
        // `to_entity_id` consumes next_id, and `current_*` then takes
        // fresh clones for the next iteration's owned cursor + visited
        // entry. `next_type` is consumed into `current_type` here —
        // the destination type is recoverable from the next hop's
        // `from_entity_type` (or the chase's returned `final_type` for
        // the terminal hop), so we don't carry it on the hop record.
        let from_type = std::mem::replace(&mut current_type, next_type);
        let from_id = std::mem::replace(&mut current_id, next_id.clone());
        visited.push((current_type.clone(), current_id.clone()));
        hops.push(RedirectHop {
            from_entity_type: from_type,
            from_entity_id: from_id,
            to_entity_id: next_id,
            version: ts.version,
        });
    }

    // Cap exhausted. Probe one more time so a chain longer than the
    // cap surfaces as a typed error rather than landing the apply on
    // an intermediate id.
    if let Some(ts) = crate::tombstone::get_tombstone(conn, &current_type, &current_id)? {
        if ts.redirect_entity_id.is_some() {
            return Err(ApplyError::TombstoneRedirectChainTooDeep {
                entity_type: initial_entity_type.to_string(),
                entity_id: initial_entity_id.to_string(),
                chain_length: hops.len(),
                terminal_id: current_id,
            });
        }
    }
    Ok((current_type, current_id, hops))
}

/// returns `true` for entity types whose `entity_id`
/// is a natural key (date string, NFC-normalized memory key, etc.)
/// rather than a UUIDv7. Natural-key entities never participate in
/// merge-redirect rewriting because their identity is content-derived
/// — two devices that observe the same natural key will already
/// converge on the same row without a redirect tombstone. Reaching
/// the redirect branch with a natural-key envelope indicates a logic
/// bug upstream (e.g. a future merger that mis-categorized natural
/// keys) and should trip the `debug_assert!` in `remap_entity_id`.
///
/// dispatches via [`naming::EntityKind`] so the
/// classification table is shared with every other sync helper that
/// asks the same "is this kind a natural key?" question. Unrecognized
/// strings return `false` (same fall-through as the prior `matches!`
/// block) so a forward-compat envelope from a newer peer doesn't
/// accidentally trip the assertion.
fn entity_type_is_natural_key(entity_type: &str) -> bool {
    naming::EntityKind::parse(entity_type).is_some_and(|k| k.is_natural_key())
}

/// Remap an entity_id by replacing the tombstoned part with the redirect target.
///
/// For composite keys like "task_id:tag_id" (used by edges), replaces the
/// matching part with the redirect target. For simple keys, returns the
/// redirect target directly.
///
/// takes the envelope's `entity_type` so the helper
/// can debug_assert that natural-key entity types never reach the
/// redirect branch. Future work that normalizes natural keys (NFC
/// memory keys, lowercase dates) will need a payload-field rewrite
/// alongside the entity_id rewrite — until then, the assertion makes
/// the gap visible if a redirect ever lands for a natural-key entity.
fn remap_entity_id(
    original_id: &str,
    old_part: &str,
    new_part: &str,
    entity_type: Option<&str>,
) -> String {
    if let Some(et) = entity_type {
        debug_assert!(
            !entity_type_is_natural_key(et),
            "remap_entity_id called for natural-key entity_type {et} (original={original_id}, \
             old_part={old_part}, new_part={new_part}) — natural keys must not enter the \
             redirect branch; see M6"
        );
    }
    if let Some((left, right)) = original_id.split_once(':') {
        // Composite key — replace only exact-match segments to avoid
        // substring corruption (e.g., if old_part is a prefix of another part).
        let left = if left == old_part { new_part } else { left };
        let right = if right == old_part { new_part } else { right };
        format!("{left}:{right}")
    } else {
        // Simple key — redirect target replaces the whole ID.
        new_part.to_string()
    }
}

/// payload-FK fields that name the loser identity
/// must be rewritten alongside the envelope's `entity_id` when a
/// redirect chase fires. Without this, the apply pipeline previously
/// wrote a payload shadow keyed by the winner-id but containing the
/// loser's `id` / FK columns; a subsequent `promote_payload_shadows`
/// pass would then replay those loser fields onto the winner row.
///
/// Returns `true` when at least one field actually changed. The
/// single match table here is the source of truth for both the
/// `apply_envelope` redirect chase and
/// `pending_inbox::remap_missing_dependency`; both surfaces deal
/// with the identical "loser → winner" identity rewrite.
///
/// `payload` is mutated in place. The caller is responsible for any
/// re-serialization to a JSON string.
pub(crate) fn remap_payload_identity_fields(
    entity_type: &str,
    payload: &mut serde_json::Value,
    original_id: &str,
    target_id: &str,
) -> bool {
    let Some(object) = payload.as_object_mut() else {
        return false;
    };

    // Per entity_type, the keys we touch. Aggregate roots additionally
    // carry an `id` field that mirrors `entity_id`. Edges + child
    // entities carry typed FK columns.
    // dispatch on `EntityKind` so the payload
    // identity-rewrite table is enumerated against the authoritative
    // variant set. A future kind without an arm will fail to compile,
    // and unrecognized strings still resolve to `false`.
    let Some(kind) = naming::EntityKind::parse(entity_type) else {
        return false;
    };
    let fields: &[&str] = match kind {
        // Aggregate roots: payload `id` field must move from loser
        // to winner so a forward-compat shadow promoted later does
        // not replay the loser's id onto the winner row.
        naming::EntityKind::Task
        | naming::EntityKind::Tag
        | naming::EntityKind::List
        | naming::EntityKind::Habit
        | naming::EntityKind::CalendarEvent
        | naming::EntityKind::CalendarSubscription
        | naming::EntityKind::Memory
        | naming::EntityKind::MemoryRevision
        | naming::EntityKind::DailyReview
        | naming::EntityKind::CurrentFocus
        | naming::EntityKind::FocusSchedule
        | naming::EntityKind::Preference => &["id"],

        // Edges: composite identity. The same rewrite handles either
        // side of the pair — only the `original_id`-matching field
        // actually changes.
        naming::EntityKind::TaskTag => &["task_id", "tag_id"],
        naming::EntityKind::TaskDependency => &["task_id", "depends_on_task_id"],
        naming::EntityKind::TaskCalendarEventLink => &["task_id", "calendar_event_id"],
        naming::EntityKind::HabitCompletion => &["habit_id", "completed_date"],

        // Independent children whose own `id` is UUIDv7 but whose
        // parent FK can move under a redirect.
        naming::EntityKind::TaskReminder | naming::EntityKind::TaskChecklistItem => &["task_id"],
        naming::EntityKind::HabitReminderPolicy => &["habit_id"],

        // Audit stream + local-only kinds: nothing to remap.
        naming::EntityKind::AiChangelog
        | naming::EntityKind::TaskProviderEventLink
        | naming::EntityKind::DeviceState
        | naming::EntityKind::SavedQuery
        | naming::EntityKind::ImportSession => return false,
    };

    let mut changed = false;
    for field in fields {
        if let Some(current) = object.get_mut(*field) {
            if current.as_str() == Some(original_id) {
                *current = serde_json::Value::String(target_id.to_string());
                changed = true;
            }
        }
    }
    changed
}
