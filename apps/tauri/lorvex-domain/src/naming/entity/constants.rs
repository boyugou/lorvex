//! Wire-format string constants for every entity type.
//!
//! Each `ENTITY_*` value is the canonical form that flows across the
//! sync envelope, the SQLite TEXT columns (`entity_type`,
//! `tombstones.entity_type`, `ai_changelog.entity_type`, etc.), the
//! export ZIP manifests, and the MCP server's payload shapes. The
//! [`super::EntityKind`] enum is the typed mirror — the strings here
//! and the variants there must stay in lockstep, and the
//! `entity_kind_round_trips_*` test suites enforce the invariant.

// ---------------------------------------------------------------------------
// Entity type names (used in sync envelopes, export, tombstones)
// ---------------------------------------------------------------------------

pub const ENTITY_TASK: &str = "task";
pub const ENTITY_LIST: &str = "list";
pub const ENTITY_HABIT: &str = "habit";
pub const ENTITY_TAG: &str = "tag";
pub const ENTITY_CALENDAR_EVENT: &str = "calendar_event";
pub const ENTITY_PREFERENCE: &str = "preference";
pub const ENTITY_MEMORY: &str = "memory";
pub const ENTITY_DAILY_REVIEW: &str = "daily_review";
pub const ENTITY_CURRENT_FOCUS: &str = "current_focus";
pub const ENTITY_FOCUS_SCHEDULE: &str = "focus_schedule";
pub const ENTITY_CALENDAR_SUBSCRIPTION: &str = "calendar_subscription";
pub const ENTITY_TASK_REMINDER: &str = "task_reminder";
pub const ENTITY_TASK_CHECKLIST_ITEM: &str = "task_checklist_item";
pub const ENTITY_HABIT_REMINDER_POLICY: &str = "habit_reminder_policy";
pub const ENTITY_MEMORY_REVISION: &str = "memory_revision";
pub const ENTITY_AI_CHANGELOG: &str = "ai_changelog";

// Local-only entity type names (not synced, not in TOPOLOGICAL_ENTITY_ORDER)
pub const ENTITY_DEVICE_STATE: &str = "device_state";
pub const ENTITY_SAVED_QUERY: &str = "saved_query";
/// Synthetic entity classification for the `import_data` audit row.
/// The import operation is not a mutation of any single aggregate
/// root — it bulk-restores a ZIP archive across every domain table —
/// so classifying the audit row as e.g. `ENTITY_TASK` would make the
/// diagnostics view treat the import session as if it had touched a
/// single task. This constant is intentionally NOT in
/// `ALL_SYNCABLE_TYPES`: import-session records are local audit
/// metadata, not replicated state.
pub const ENTITY_IMPORT_SESSION: &str = "import_session";

/// All entity type names in declaration order.
pub const ALL_ENTITY_TYPES: &[&str] = &[
    ENTITY_TASK,
    ENTITY_LIST,
    ENTITY_HABIT,
    ENTITY_TAG,
    ENTITY_CALENDAR_EVENT,
    ENTITY_PREFERENCE,
    ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION,
    ENTITY_DAILY_REVIEW,
    ENTITY_CURRENT_FOCUS,
    ENTITY_FOCUS_SCHEDULE,
    ENTITY_CALENDAR_SUBSCRIPTION,
    ENTITY_TASK_REMINDER,
    ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_HABIT_REMINDER_POLICY,
    ENTITY_AI_CHANGELOG,
];
