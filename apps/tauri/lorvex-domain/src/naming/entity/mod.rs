//! Entity type vocabulary — the canonical string and typed-enum
//! identifiers for every aggregate root, independent child, content-
//! addressed asset, audit stream, edge, and local-only kind that
//! flows across the sync envelope, payload shadow, version stamp,
//! and outbox routing layers.
//!
//! The wire format and SQLite TEXT columns continue to carry the
//! canonical string value (`as_str()`); this module is the single
//! source of truth for the closed set, the [`EntityKind`] enum, and
//! the topological order used by batch sync / import.
//!
//! ## Per-concern siblings
//!
//! - [`constants`] — `ENTITY_*` wire-format strings + [`ALL_ENTITY_TYPES`].
//! - [`kind`] — the typed [`EntityKind`] enum + parse / table / table_pk
//!   helpers, plus the `Display` / `FromStr` impls.
//! - [`error`] — [`UnknownEntityKind`] (typed `FromStr` / `try_parse` error).
//! - [`topology`] — sync-pipeline membership ([`ALL_SYNCABLE_TYPES`],
//!   [`is_syncable_type`]) and the FK-safe [`TOPOLOGICAL_ENTITY_ORDER`].

pub mod constants;
pub mod error;
pub mod kind;
pub mod topology;

pub use constants::{
    ALL_ENTITY_TYPES, ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION,
    ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW, ENTITY_DEVICE_STATE, ENTITY_FOCUS_SCHEDULE,
    ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, ENTITY_IMPORT_SESSION, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_SAVED_QUERY, ENTITY_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
pub use error::UnknownEntityKind;
pub use kind::EntityKind;
pub use topology::{is_syncable_type, ALL_SYNCABLE_TYPES, TOPOLOGICAL_ENTITY_ORDER};
