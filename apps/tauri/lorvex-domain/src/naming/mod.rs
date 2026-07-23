//! Canonical naming registry — single source of truth for entity type
//! names, edge type names, sync-envelope operation names, task lifecycle
//! status, defer reasons, habit frequency vocabulary, conflict-log
//! resolution types, retention windows, calendar AI access mode, and
//! the topological entity order used across transport, UI, export, and
//! documentation.
//!
//! All code paths that produce or consume these strings reference the
//! constants below. No string literals for entity types, statuses, or
//! operation names live outside this subsystem.
//!
//! ## Module layout
//!
//! - [`entity`] — `ENTITY_*` constants, the typed [`EntityKind`] enum
//!   plus its parse / table / table_pk helpers, [`UnknownEntityKind`],
//!   [`ALL_ENTITY_TYPES`], [`ALL_SYNCABLE_TYPES`] (the single source
//!   of truth for sync-pipeline membership), [`is_syncable_type`], and
//!   [`TOPOLOGICAL_ENTITY_ORDER`] (FK-safe batch sync / import order).
//! - [`edge`] — `EDGE_*` constants and [`ALL_EDGE_TYPES`].
//! - [`status`] — typed [`TaskStatus`] enum + `STATUS_*` mirror
//!   constants, plus the `provider_scope_runtime_state.availability_state`
//!   vocabulary ([`AVAILABILITY_STATE_ENABLED`],
//!   [`AVAILABILITY_STATE_PERMISSION_DENIED`]).
//! - [`defer`] — typed [`DeferReason`] mirror of the TS literal union,
//!   `DEFER_REASON_*` constants, and [`is_valid_defer_reason`].
//! - [`habit`] — `HABIT_FREQUENCY_*` schema-CHECK wire constants used
//!   by `HabitCadence::to_fields()` for the canonical wire form.
//! - [`resolution`] — `RESOLUTION_*` conflict-log resolution types
//!   that Settings → Sync → Conflicts buckets by.
//! - [`calendar`] — [`CalendarAiAccessMode`] (off / busy-only /
//!   full-details tiers).
//!
//! ## Top-level constants
//!
//! Two small vocabularies live at this level rather than in their own
//! sub-modules — both are below the >5-item floor and a dedicated file
//! would add structure without information:
//!
//! - Sync-envelope operations: [`OP_UPSERT`] and [`OP_DELETE`].
//! - Retention windows: [`TOMBSTONE_MAX_RETENTION_DAYS`],
//!   [`DEVICE_INACTIVE_THRESHOLD_DAYS`], [`FULL_RESYNC_HORIZON_DAYS`],
//!   [`AUDIT_MAX_ENTRIES_SAFEGUARD`].

pub mod calendar;
pub mod defer;
pub mod edge;
pub mod entity;
pub mod habit;
pub mod resolution;
pub mod status;

#[cfg(test)]
mod tests;

// ---------------------------------------------------------------------------
// Re-export hub — every public symbol the old flat `naming.rs` exposed is
// re-exported here so external callers (lorvex-store, lorvex-sync,
// lorvex-runtime, lorvex-cli, mcp-server, app/src-tauri) keep importing
// `lorvex_domain::naming::*` without any change.
// ---------------------------------------------------------------------------

pub use calendar::CalendarAiAccessMode;
pub use defer::{
    is_valid_defer_reason, DeferReason, ALL_DEFER_REASONS, DEFER_REASON_BLOCKED,
    DEFER_REASON_LOW_ENERGY, DEFER_REASON_NEEDS_BREAKDOWN, DEFER_REASON_NEEDS_INFO,
    DEFER_REASON_NOT_TODAY,
};
pub use edge::{
    ALL_EDGE_TYPES, EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY,
    EDGE_TASK_PROVIDER_EVENT_LINK, EDGE_TASK_TAG,
};
pub use entity::{
    is_syncable_type, EntityKind, UnknownEntityKind, ALL_ENTITY_TYPES, ALL_SYNCABLE_TYPES,
    ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS,
    ENTITY_DAILY_REVIEW, ENTITY_DEVICE_STATE, ENTITY_FOCUS_SCHEDULE, ENTITY_HABIT,
    ENTITY_HABIT_REMINDER_POLICY, ENTITY_IMPORT_SESSION, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_SAVED_QUERY, ENTITY_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER, TOPOLOGICAL_ENTITY_ORDER,
};
pub use habit::{
    HABIT_FREQUENCY_DAILY, HABIT_FREQUENCY_MONTHLY, HABIT_FREQUENCY_TIMES_PER_WEEK,
    HABIT_FREQUENCY_WEEKLY,
};
pub use resolution::{
    RESOLUTION_ATTENDEE_EMAIL_COLLISION, RESOLUTION_CONTENT_TRUNCATED,
    RESOLUTION_CROSS_TYPE_REDIRECT_DROP, RESOLUTION_CYCLE_BREAK, RESOLUTION_FK_STALLED,
    RESOLUTION_FK_UNRESOLVED, RESOLUTION_LWW, RESOLUTION_PENDING_INBOX_EXHAUSTED,
    RESOLUTION_RECURRENCE_DEDUP, RESOLUTION_REDIRECTED_DELETE_DROPPED, RESOLUTION_RESEED_REQUIRED,
    RESOLUTION_SHADOW_OBSOLETE, RESOLUTION_TAG_MERGE, RESOLUTION_TOMBSTONE_WINS,
    RESOLUTION_UPSERT_WINS_OVER_DELETE,
};
pub use status::{
    TaskStatus, ACTIVE_STATUS_SQL_LIST, AVAILABILITY_STATE_AUTHORIZATION_ERROR,
    AVAILABILITY_STATE_ENABLED, AVAILABILITY_STATE_ERROR_SQL_LIST, AVAILABILITY_STATE_FETCH_ERROR,
    AVAILABILITY_STATE_PARSE_ERROR, AVAILABILITY_STATE_PERMISSION_DENIED, STATUS_CANCELLED,
    STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY,
};

// ---------------------------------------------------------------------------
// Sync-envelope operation names
// ---------------------------------------------------------------------------

pub const OP_UPSERT: &str = "upsert";
pub const OP_DELETE: &str = "delete";

// ---------------------------------------------------------------------------
// Retention windows
// ---------------------------------------------------------------------------
//
// Tombstone retention is modeled with watermark-based GC as the primary
// mechanism; `TOMBSTONE_MAX_RETENTION_DAYS` is the absolute safety-net
// fallback. Audit retention itself is modeled at the preference layer as
// `Option<u32>` days (None = forever / keep all entries, Some(n) = delete
// entries older than n days). The legacy `AuditRetentionPolicy` enum was
// removed because it only supported 7/14/30/90-day buckets while the
// Settings UI offers 7/14/30/60/90/180/365 — mismatching values caused MCP
// mutations to fail with "unsupported day count" errors. Read the preference
// via `parse_positive_i64_preference(raw, PREF_AI_CHANGELOG_RETENTION_POLICY)`.

/// Absolute maximum tombstone retention (safety net). Watermark-based GC is
/// the primary mechanism; this is the fallback that defines the maximum
/// offline window before a full re-sync is required.
pub const TOMBSTONE_MAX_RETENTION_DAYS: u32 = 365;

/// Device is marked inactive after this many days without sync. Inactive
/// devices are excluded from tombstone watermark checks.
pub const DEVICE_INACTIVE_THRESHOLD_DAYS: u32 = 90;

/// Pending inbox envelopes older than this trigger reseed_required. Separate
/// from tombstone GC (which uses version-domain watermark).
pub const FULL_RESYNC_HORIZON_DAYS: u32 = 90;

/// Hard safeguard: maximum ai_changelog entries before forced cleanup. This
/// is NOT a primary retention rule — the time window is primary.
pub const AUDIT_MAX_ENTRIES_SAFEGUARD: u32 = 10_000;
