//! Typed entity-handler struct + the static `ENTITY_HANDLERS`
//! registration table + the `lookup` helper that resolves an
//! `entity_type` string to its handler.
//!
//! The registration table is the single declarative source of truth
//! for which entity types flow through which dispatch shape. Each
//! row carries:
//!
//! * an [`HandlerKind`] discriminant — `Normal` for the bulk of the
//!   table; `Memory` / `AppendOnlyChangelog` for entity types whose
//!   fn-pointer shapes differ from the
//!   standard handler signature (device_id threading or an append-
//!   only contract with no `version` column);
//! * a [`HandlerGates`] flags struct with the two orthogonal axes
//!   that define the LWW + invariant behavior of `Normal` handlers;
//! * three optional fn-pointers — `standard_delete`,
//!   `lww_gated_delete`, `invariant_gated_delete` — exactly one of
//!   which is `Some` per `Normal` row (selected by `gates`).
//!
//! Replaces a prior shape that encoded the gate factoring as a
//! 7-variant enum with parallel match arms in the dispatcher; the
//! struct shape moves the (lww_gated, invariant_gated) decision into
//! data, so the dispatcher reads flags and picks the appropriate
//! optional fn-pointer rather than pattern-matching across five
//! near-identical variants.

use rusqlite::Connection;

use lorvex_domain::naming;

use super::super::{aggregate, child, day_scoped, edge, tag, ApplyError, LwwTieBreak};

/// Aggregate / child / edge delete signature with a `()` payload.
///
/// Every handler signature carries the once-per-envelope
/// `apply_ts: &str` so cascade-tombstone helpers / merge
/// conflict-log writes / pending-restore snapshots inside the
/// handler all share one captured moment of apply, instead of each
/// site rereading the wall clock.
///
/// Both standard aggregate roots (no in-handler gates — e.g.
/// `calendar_subscriptions`, `preferences`, day-scoped aggregates)
/// AND independent child / edge / tag / blob handlers (which take
/// the envelope's `version` so they can install a defense-in-depth
/// in-row LWW guard `:version >= row.version`) conform to this
/// shape — they were two named typedefs prior to #3375 but the
/// signatures were byte-identical.
pub(super) type StandardDelete = fn(&Connection, &str, &str, &str) -> Result<(), ApplyError>;

/// Standard aggregate-root upsert signature (also used by every child /
/// edge / tag / blob / day-scoped handler).
///
/// The LWW-tie-break parameter is the typed [`LwwTieBreak`] enum so
/// every handler in the dispatch table exhaustive-matches the two
/// modes; a bare `bool` flag would force the comparator and the
/// replay-vs-live distinction to be inferred from one bit per
/// caller.
pub(super) type StandardUpsert =
    fn(&Connection, &str, &str, &str, LwwTieBreak, &str) -> Result<(), ApplyError>;

/// Aggregate-root delete signature for the three LWW-gated
/// aggregates (tasks, habits, calendar_events) whose in-handler
/// LWW gate may refuse the SQL DELETE and surface the loss as
/// `LwwGatedDeleteOutcome::LwwRejected`.
pub(super) type LwwGatedAggregateDelete =
    fn(&Connection, &str, &str, &str) -> Result<aggregate::LwwGatedDeleteOutcome, ApplyError>;

/// Aggregate-root delete signature for aggregates gated by BOTH an
/// invariant and the in-handler LWW guard (currently only `lists`).
/// The handler returns `aggregate::InvariantGatedDeleteOutcome`.
pub(super) type InvariantGatedAggregateDelete =
    fn(&Connection, &str, &str, &str) -> Result<aggregate::InvariantGatedDeleteOutcome, ApplyError>;

/// Discriminant for the three entity types whose fn-pointer shapes
/// differ from the `Normal` handler signature pair
/// ([`StandardUpsert`] + one of the three delete signatures).
///
/// The bulk of the table is `Normal`; the three special cases each
/// have unique inline logic in `dispatch_impl::dispatch` because
/// they thread the envelope's `device_id` (Memory) or
/// implement an append-only contract with no `version` column
/// (AppendOnlyChangelog).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum HandlerKind {
    /// Aggregate / child / edge whose upsert + delete fit the
    /// fn-pointer signatures in this module. The dispatcher reads
    /// [`HandlerGates`] to pick which optional delete fn-pointer
    /// is `Some` for this row.
    Normal,
    /// Memory aggregate root: delete is standard, upsert needs the
    /// envelope's `device_id` for sync-conflict-log attribution.
    Memory,
    /// Append-only audit stream — the writer never produces Delete
    /// envelopes for it, and `apply_changelog_entry` has a unique
    /// 3-arg shape (no version, no allow_equal_versions). A peer-
    /// authored Delete is rejected with
    /// `ApplyError::InvalidOperation`.
    AppendOnlyChangelog,
}

/// Two orthogonal capability flags that classify a `Normal` handler's
/// delete-time gating behavior.
///
/// * `lww_gated` — the delete handler carries an in-handler LWW
///   guard (`:version >= row.version`) that may refuse the SQL
///   DELETE and surface the loss as
///   `LwwGatedDeleteOutcome::LwwRejected` (or, when combined with
///   `invariant_gated`, `InvariantGatedDeleteOutcome::LwwRejected`).
///   The dispatcher consumes the typed `LwwRejected` arm so
///   `apply_envelope` suppresses tombstone creation — a tombstone
///   minted at the envelope's older HLC over the surviving local
///   row would corrupt cluster-converged state on re-sync.
/// * `invariant_gated` — the delete handler additionally checks an
///   aggregate-level invariant (e.g. "at least one list,"
///   "tasks-reference-list," blob inbound-FK pin); a hit surfaces
///   as `InvariantGatedDeleteOutcome::SkippedByInvariant`, and the
///   dispatcher defers the envelope to `sync_pending_inbox`.
///
/// `(false, false)` → `standard_delete` is `Some`.
/// `(true, false)`  → `lww_gated_delete` is `Some`.
/// `(true, true)`   → `invariant_gated_delete` is `Some`.
/// `(false, true)`  is unreachable — every invariant-gated handler
/// in the workspace also carries the in-handler LWW guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct HandlerGates {
    pub lww_gated: bool,
    pub invariant_gated: bool,
}

impl HandlerGates {
    pub(super) const NONE: Self = Self {
        lww_gated: false,
        invariant_gated: false,
    };
    pub(super) const LWW: Self = Self {
        lww_gated: true,
        invariant_gated: false,
    };
    pub(super) const LWW_AND_INVARIANT: Self = Self {
        lww_gated: true,
        invariant_gated: true,
    };
}

/// Typed dispatch shape for one entity type. The `kind` discriminant
/// distinguishes the four broad fn-pointer shapes; for `Normal` rows
/// the `gates` flags and the three optional delete fn-pointers
/// describe which delete signature is in force.
#[derive(Debug, Clone, Copy)]
pub(super) struct EntityHandler {
    pub kind: HandlerKind,
    pub gates: HandlerGates,
    /// Some for `Normal` rows; None for special-cased kinds whose
    /// upsert is inlined in the dispatcher (Memory)
    /// or doesn't exist as an [`StandardUpsert`] (AppendOnlyChangelog
    /// uses the bespoke `apply_changelog_entry`).
    pub upsert: Option<StandardUpsert>,
    /// Some when `kind == Normal && gates == HandlerGates::NONE`.
    pub standard_delete: Option<StandardDelete>,
    /// Some when `kind == Normal && gates == HandlerGates::LWW`.
    pub lww_gated_delete: Option<LwwGatedAggregateDelete>,
    /// Some when `kind == Normal && gates == HandlerGates::LWW_AND_INVARIANT`.
    pub invariant_gated_delete: Option<InvariantGatedAggregateDelete>,
}

impl EntityHandler {
    /// `Normal` row with no in-handler gates — `standard_delete` runs
    /// unconditionally and the dispatcher uses the post-handler
    /// LWW re-check to detect SQL-level rejection.
    const fn standard(delete: StandardDelete, upsert: StandardUpsert) -> Self {
        Self {
            kind: HandlerKind::Normal,
            gates: HandlerGates::NONE,
            upsert: Some(upsert),
            standard_delete: Some(delete),
            lww_gated_delete: None,
            invariant_gated_delete: None,
        }
    }

    /// `Normal` row with `gates.lww_gated` — used by `tasks`,
    /// `habits`, and `calendar_events`.
    const fn lww_gated(delete: LwwGatedAggregateDelete, upsert: StandardUpsert) -> Self {
        Self {
            kind: HandlerKind::Normal,
            gates: HandlerGates::LWW,
            upsert: Some(upsert),
            standard_delete: None,
            lww_gated_delete: Some(delete),
            invariant_gated_delete: None,
        }
    }

    /// `Normal` row with `gates.lww_gated && gates.invariant_gated`
    /// — used by `lists`.
    const fn invariant_gated(
        delete: InvariantGatedAggregateDelete,
        upsert: StandardUpsert,
    ) -> Self {
        Self {
            kind: HandlerKind::Normal,
            gates: HandlerGates::LWW_AND_INVARIANT,
            upsert: Some(upsert),
            standard_delete: None,
            lww_gated_delete: None,
            invariant_gated_delete: Some(delete),
        }
    }

    /// Special-cased `kind` with no fn-pointers in the table — the
    /// dispatcher inlines the call to thread `device_id` or to
    /// implement the append-only contract.
    const fn special(kind: HandlerKind) -> Self {
        Self {
            kind,
            gates: HandlerGates::NONE,
            upsert: None,
            standard_delete: None,
            lww_gated_delete: None,
            invariant_gated_delete: None,
        }
    }
}

/// Static registration of every syncable entity type. Lookup is a
/// linear scan, but the table is ~22 entries and the dispatcher runs
/// inside an already-acquired DB transaction, so a HashMap would just
/// add allocation pressure. The slice is `const` so the compiler can
/// turn the `find` into a static jump table at the call site for
/// release builds.
pub(super) const ENTITY_HANDLERS: &[(&str, EntityHandler)] = &[
    // ---- Aggregate roots ----
    (
        naming::ENTITY_TASK,
        EntityHandler::lww_gated(aggregate::apply_task_delete, aggregate::apply_task_upsert),
    ),
    (
        naming::ENTITY_LIST,
        EntityHandler::invariant_gated(aggregate::apply_list_delete, aggregate::apply_list_upsert),
    ),
    (
        naming::ENTITY_HABIT,
        EntityHandler::lww_gated(aggregate::apply_habit_delete, aggregate::apply_habit_upsert),
    ),
    (
        naming::ENTITY_CALENDAR_EVENT,
        EntityHandler::lww_gated(
            aggregate::apply_calendar_event_delete,
            aggregate::apply_calendar_event_upsert,
        ),
    ),
    (
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        EntityHandler::standard(
            aggregate::apply_calendar_subscription_delete,
            aggregate::apply_calendar_subscription_upsert,
        ),
    ),
    (
        naming::ENTITY_PREFERENCE,
        EntityHandler::standard(
            aggregate::apply_preference_delete,
            aggregate::apply_preference_upsert,
        ),
    ),
    // ---- Day-scoped aggregates ----
    (
        naming::ENTITY_CURRENT_FOCUS,
        EntityHandler::standard(
            day_scoped::apply_current_focus_delete,
            day_scoped::apply_current_focus_upsert,
        ),
    ),
    (
        naming::ENTITY_FOCUS_SCHEDULE,
        EntityHandler::standard(
            day_scoped::apply_focus_schedule_delete,
            day_scoped::apply_focus_schedule_upsert,
        ),
    ),
    (
        naming::ENTITY_DAILY_REVIEW,
        EntityHandler::standard(
            day_scoped::apply_daily_review_delete,
            day_scoped::apply_daily_review_upsert,
        ),
    ),
    // ---- Independent children ----
    (
        naming::ENTITY_TAG,
        EntityHandler::standard(tag::apply_tag_delete, tag::apply_tag_upsert),
    ),
    (
        naming::ENTITY_TASK_REMINDER,
        EntityHandler::standard(
            child::apply_task_reminder_delete,
            child::apply_task_reminder_upsert,
        ),
    ),
    (
        naming::ENTITY_TASK_CHECKLIST_ITEM,
        EntityHandler::standard(
            child::apply_task_checklist_item_delete,
            child::apply_task_checklist_item_upsert,
        ),
    ),
    (
        naming::ENTITY_HABIT_REMINDER_POLICY,
        EntityHandler::standard(
            child::apply_habit_reminder_policy_delete,
            child::apply_habit_reminder_policy_upsert,
        ),
    ),
    (
        naming::ENTITY_MEMORY_REVISION,
        EntityHandler::standard(
            child::apply_memory_revision_delete,
            child::apply_memory_revision_upsert,
        ),
    ),
    // ---- Edges ----
    (
        naming::EDGE_TASK_TAG,
        EntityHandler::standard(edge::apply_task_tag_delete, edge::apply_task_tag_upsert),
    ),
    (
        naming::EDGE_TASK_DEPENDENCY,
        EntityHandler::standard(
            edge::apply_task_dependency_delete,
            edge::apply_task_dependency_upsert,
        ),
    ),
    (
        naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        EntityHandler::standard(
            edge::apply_task_calendar_event_link_delete,
            edge::apply_task_calendar_event_link_upsert,
        ),
    ),
    (
        naming::EDGE_HABIT_COMPLETION,
        EntityHandler::standard(
            edge::apply_habit_completion_delete,
            edge::apply_habit_completion_upsert,
        ),
    ),
    // ---- Special cases (need device_id or append-only semantics) ----
    (
        naming::ENTITY_MEMORY,
        EntityHandler::special(HandlerKind::Memory),
    ),
    (
        naming::ENTITY_AI_CHANGELOG,
        EntityHandler::special(HandlerKind::AppendOnlyChangelog),
    ),
];

pub(super) fn lookup(entity_type: &str) -> Option<EntityHandler> {
    ENTITY_HANDLERS
        .iter()
        .find(|(et, _)| *et == entity_type)
        .map(|(_, handler)| *handler)
}
