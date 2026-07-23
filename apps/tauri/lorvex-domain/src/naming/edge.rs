//! Edge type vocabulary — composite-key relationship rows that flow
//! through the sync envelope alongside aggregate roots and independent
//! children. This file lists edge tables only; the parent-owned-collection
//! exclusion (e.g. `current_focus_items`, `focus_schedule_blocks` — which
//! ride embedded inside their parent payload, not as independent sync
//! entities) is enforced at the entity layer in
//! [`super::entity::ALL_SYNCABLE_TYPES`].

pub const EDGE_TASK_TAG: &str = "task_tag";
pub const EDGE_TASK_DEPENDENCY: &str = "task_dependency";
pub const EDGE_TASK_CALENDAR_EVENT_LINK: &str = "task_calendar_event_link";
pub const EDGE_HABIT_COMPLETION: &str = "habit_completion";

/// Local-only edge: task ↔ external calendar provider event link.
/// Not synced, but included in device snapshot/export for backup portability.
pub const EDGE_TASK_PROVIDER_EVENT_LINK: &str = "task_provider_event_link";

/// All edge type names in declaration order.
/// Parent-owned collection tables are excluded — they are not independent
/// sync entities.
pub const ALL_EDGE_TYPES: &[&str] = &[
    EDGE_TASK_TAG,
    EDGE_TASK_DEPENDENCY,
    EDGE_TASK_CALENDAR_EVENT_LINK,
    EDGE_HABIT_COMPLETION,
];
