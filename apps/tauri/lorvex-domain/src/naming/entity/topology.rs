//! Sync-pipeline membership and FK-safe topological order.
//!
//! Two adjacent vocabularies live here because they share the same
//! shape (`&[&str]` of `ENTITY_*` / `EDGE_*` constants) and the same
//! audience (the apply pipeline, the export/import bulk path, the
//! outbox whitelisting code, and the entity-collector helpers):
//!
//! - [`ALL_SYNCABLE_TYPES`] + [`is_syncable_type`] — the single source
//!   of truth for "does this entity type cross devices?". Local-only
//!   kinds (`device_state`, `feedback`, `saved_query`, `import_session`)
//!   are deliberately absent.
//! - [`TOPOLOGICAL_ENTITY_ORDER`] — the FK-safe order in which a batch
//!   sync or import must apply rows so child references resolve before
//!   the SQLite FK check fires. Aggregate roots first, then
//!   content-addressed assets, then edges, then independent children.

use super::constants::{
    ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS,
    ENTITY_DAILY_REVIEW, ENTITY_FOCUS_SCHEDULE, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY,
    ENTITY_LIST, ENTITY_MEMORY, ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use crate::naming::edge::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
};

/// All entity and edge types that participate in the sync pipeline.
///
/// **This is the single source of truth.** Any code that needs to enumerate
/// syncable types (outbox whitelists, pull-side record parsing, entity
/// collectors, etc.) MUST derive from this constant — never maintain a
/// parallel list.
///
/// Note: `ai_changelog` IS synced (append-only, no LWW) so it is included.
/// Parent-owned collection tables (current_focus_items, focus_schedule_blocks,
/// calendar_event_attendees, daily_review links) are NOT independently synced;
/// they are embedded in their parent entity payloads.
pub const ALL_SYNCABLE_TYPES: &[&str] = &[
    // Aggregate roots
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
    // Independent children
    ENTITY_TASK_REMINDER,
    ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_HABIT_REMINDER_POLICY,
    // Audit stream
    ENTITY_AI_CHANGELOG,
    // Edges
    EDGE_TASK_TAG,
    EDGE_TASK_DEPENDENCY,
    EDGE_TASK_CALENDAR_EVENT_LINK,
    EDGE_HABIT_COMPLETION,
];

/// Returns true if the given type is in `ALL_SYNCABLE_TYPES`.
pub fn is_syncable_type(entity_type: &str) -> bool {
    ALL_SYNCABLE_TYPES.contains(&entity_type)
}

/// Fixed topological order for batch sync and import. Entities are applied in
/// this order to satisfy foreign key constraints without deferral.
///
/// Order: aggregate roots first (parents before children), then content-addressed
/// assets, then edges, then children.
pub const TOPOLOGICAL_ENTITY_ORDER: &[&str] = &[
    // Aggregate roots
    ENTITY_LIST,
    ENTITY_TASK,
    ENTITY_HABIT,
    ENTITY_TAG,
    ENTITY_CALENDAR_EVENT,
    ENTITY_CALENDAR_SUBSCRIPTION,
    ENTITY_PREFERENCE,
    ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION,
    ENTITY_DAILY_REVIEW,
    ENTITY_CURRENT_FOCUS,
    ENTITY_FOCUS_SCHEDULE,
    // Edges
    EDGE_TASK_TAG,
    EDGE_TASK_DEPENDENCY,
    EDGE_TASK_CALENDAR_EVENT_LINK,
    EDGE_HABIT_COMPLETION,
    // Independent children
    ENTITY_TASK_REMINDER,
    ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_HABIT_REMINDER_POLICY,
];
