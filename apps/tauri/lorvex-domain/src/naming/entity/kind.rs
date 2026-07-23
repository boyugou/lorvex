//! The strongly-typed [`EntityKind`] enum and its associated helpers.
//!
//! `EntityKind` is the single closed-set classification used across the
//! sync pipeline, payload shadow, version stamping, outbox routing,
//! and the apply pipeline. The enum carries every aggregate root,
//! independent child, content-addressed asset, audit stream, edge,
//! and local-only kind that the codebase emits — so consumers can
//! exhaustive-match instead of dispatching on raw `entity_type: &str`.
//!
//! The wire format and SQLite TEXT columns continue to carry the
//! canonical string value (`as_str()`); peers and DB rows are
//! unaffected. Internal helpers accept `EntityKind` directly; callers
//! that hold a runtime string parse via [`EntityKind::parse`] (silent
//! `None`) or [`EntityKind::try_parse`] (typed error + debug_assert)
//! at the boundary.

use serde::{Deserialize, Serialize};

use super::constants::{
    ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS,
    ENTITY_DAILY_REVIEW, ENTITY_DEVICE_STATE, ENTITY_FOCUS_SCHEDULE, ENTITY_HABIT,
    ENTITY_HABIT_REMINDER_POLICY, ENTITY_IMPORT_SESSION, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_SAVED_QUERY, ENTITY_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use super::error::UnknownEntityKind;
use crate::naming::edge::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY,
    EDGE_TASK_PROVIDER_EVENT_LINK, EDGE_TASK_TAG,
};

/// Strongly-typed entity / edge classification used across the sync
/// pipeline, payload shadow, version stamping, and outbox routing.
///
/// The classification lives as a single enum so every consumer
/// exhaustive-matches against the closed set instead of dispatching
/// on raw `entity_type: &str`. Threading the string through ~112
/// sites with parallel `match entity_type` tables in
/// `outbox_enqueue::entity_type_to_table`,
/// `payload_shadow::owned_keys_for_entity`,
/// `aggregate_payload::kind_is_aggregate_root_with_embedded_children`,
/// and three independent matches in `version_stamp.rs` would let
/// the duplicated tables drift and let unrecognized strings
/// silently fall through `_ =>` arms.
/// with serde rename eliminates the duplicates and makes "unknown
/// entity kind" a typed error at the parse seam.
///
/// The wire format and SQLite TEXT columns continue to carry the
/// canonical string value (`as_str()`); peers and DB rows are
/// unaffected. Internal helpers accept `EntityKind` directly; callers
/// that hold a runtime string parse via [`EntityKind::parse`] at the
/// boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EntityKind {
    // Aggregate roots
    #[serde(rename = "task")]
    Task,
    #[serde(rename = "list")]
    List,
    #[serde(rename = "habit")]
    Habit,
    #[serde(rename = "tag")]
    Tag,
    #[serde(rename = "calendar_event")]
    CalendarEvent,
    #[serde(rename = "preference")]
    Preference,
    #[serde(rename = "memory")]
    Memory,
    #[serde(rename = "memory_revision")]
    MemoryRevision,
    #[serde(rename = "daily_review")]
    DailyReview,
    #[serde(rename = "current_focus")]
    CurrentFocus,
    #[serde(rename = "focus_schedule")]
    FocusSchedule,
    #[serde(rename = "calendar_subscription")]
    CalendarSubscription,
    // Independent children
    #[serde(rename = "task_reminder")]
    TaskReminder,
    #[serde(rename = "task_checklist_item")]
    TaskChecklistItem,
    #[serde(rename = "habit_reminder_policy")]
    HabitReminderPolicy,
    // Audit stream
    #[serde(rename = "ai_changelog")]
    AiChangelog,
    // Edges
    #[serde(rename = "task_tag")]
    TaskTag,
    #[serde(rename = "task_dependency")]
    TaskDependency,
    #[serde(rename = "task_calendar_event_link")]
    TaskCalendarEventLink,
    #[serde(rename = "habit_completion")]
    HabitCompletion,
    #[serde(rename = "task_provider_event_link")]
    TaskProviderEventLink,
    // Local-only (not in `ALL_SYNCABLE_TYPES` / `TOPOLOGICAL_ENTITY_ORDER`).
    // Tracked here so the enum can round-trip the entire string vocabulary
    // emitted by the codebase (audit rows, device-state, saved queries).
    #[serde(rename = "device_state")]
    DeviceState,
    #[serde(rename = "saved_query")]
    SavedQuery,
    #[serde(rename = "import_session")]
    ImportSession,
}

impl EntityKind {
    /// Canonical string form. Identical to the matching `ENTITY_*` /
    /// `EDGE_*` constant — wire format and SQL TEXT columns continue
    /// to use this representation.
    pub const fn as_str(&self) -> &'static str {
        match self {
            EntityKind::Task => ENTITY_TASK,
            EntityKind::List => ENTITY_LIST,
            EntityKind::Habit => ENTITY_HABIT,
            EntityKind::Tag => ENTITY_TAG,
            EntityKind::CalendarEvent => ENTITY_CALENDAR_EVENT,
            EntityKind::Preference => ENTITY_PREFERENCE,
            EntityKind::Memory => ENTITY_MEMORY,
            EntityKind::MemoryRevision => ENTITY_MEMORY_REVISION,
            EntityKind::DailyReview => ENTITY_DAILY_REVIEW,
            EntityKind::CurrentFocus => ENTITY_CURRENT_FOCUS,
            EntityKind::FocusSchedule => ENTITY_FOCUS_SCHEDULE,
            EntityKind::CalendarSubscription => ENTITY_CALENDAR_SUBSCRIPTION,
            EntityKind::TaskReminder => ENTITY_TASK_REMINDER,
            EntityKind::TaskChecklistItem => ENTITY_TASK_CHECKLIST_ITEM,
            EntityKind::HabitReminderPolicy => ENTITY_HABIT_REMINDER_POLICY,
            EntityKind::AiChangelog => ENTITY_AI_CHANGELOG,
            EntityKind::TaskTag => EDGE_TASK_TAG,
            EntityKind::TaskDependency => EDGE_TASK_DEPENDENCY,
            EntityKind::TaskCalendarEventLink => EDGE_TASK_CALENDAR_EVENT_LINK,
            EntityKind::HabitCompletion => EDGE_HABIT_COMPLETION,
            EntityKind::TaskProviderEventLink => EDGE_TASK_PROVIDER_EVENT_LINK,
            EntityKind::DeviceState => ENTITY_DEVICE_STATE,
            EntityKind::SavedQuery => ENTITY_SAVED_QUERY,
            EntityKind::ImportSession => ENTITY_IMPORT_SESSION,
        }
    }

    /// Parse a runtime string back into an `EntityKind`. Returns `None`
    /// for any value not listed in [`super::ALL_ENTITY_TYPES`] /
    /// [`crate::naming::edge::ALL_EDGE_TYPES`] / the local-only set;
    /// the caller is responsible for surfacing a typed error
    /// (`UnknownEntityType`, `Skipped`, etc.) at its own layer.
    ///
    /// Callers that *know* the input must be a member of the closed set
    /// (e.g. iteration over [`super::ALL_SYNCABLE_TYPES`]) should prefer
    /// [`EntityKind::try_parse`], which returns a typed
    /// [`UnknownEntityKind`] error and a structured diagnostic in
    /// release builds — and a `debug_assert!` in debug — instead of
    /// the silent `None` that this function returns by contract.
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            ENTITY_TASK => EntityKind::Task,
            ENTITY_LIST => EntityKind::List,
            ENTITY_HABIT => EntityKind::Habit,
            ENTITY_TAG => EntityKind::Tag,
            ENTITY_CALENDAR_EVENT => EntityKind::CalendarEvent,
            ENTITY_PREFERENCE => EntityKind::Preference,
            ENTITY_MEMORY => EntityKind::Memory,
            ENTITY_MEMORY_REVISION => EntityKind::MemoryRevision,
            ENTITY_DAILY_REVIEW => EntityKind::DailyReview,
            ENTITY_CURRENT_FOCUS => EntityKind::CurrentFocus,
            ENTITY_FOCUS_SCHEDULE => EntityKind::FocusSchedule,
            ENTITY_CALENDAR_SUBSCRIPTION => EntityKind::CalendarSubscription,
            ENTITY_TASK_REMINDER => EntityKind::TaskReminder,
            ENTITY_TASK_CHECKLIST_ITEM => EntityKind::TaskChecklistItem,
            ENTITY_HABIT_REMINDER_POLICY => EntityKind::HabitReminderPolicy,
            ENTITY_AI_CHANGELOG => EntityKind::AiChangelog,
            EDGE_TASK_TAG => EntityKind::TaskTag,
            EDGE_TASK_DEPENDENCY => EntityKind::TaskDependency,
            EDGE_TASK_CALENDAR_EVENT_LINK => EntityKind::TaskCalendarEventLink,
            EDGE_HABIT_COMPLETION => EntityKind::HabitCompletion,
            EDGE_TASK_PROVIDER_EVENT_LINK => EntityKind::TaskProviderEventLink,
            ENTITY_DEVICE_STATE => EntityKind::DeviceState,
            ENTITY_SAVED_QUERY => EntityKind::SavedQuery,
            ENTITY_IMPORT_SESSION => EntityKind::ImportSession,
            _ => return None,
        })
    }

    /// Parse a runtime string back into an `EntityKind`, returning a
    /// typed error for unknown values.
    ///
    /// the `entity_kind_round_trips_*` test suites
    /// called [`EntityKind::parse`] and `panic!`-ed on the
    /// `None` arm. That panic is functionally equivalent to a
    /// `debug_assert!` in test code, but the message lacked a typed
    /// reason and the same coverage gap (an `ALL_ENTITY_TYPES` entry
    /// added without extending `EntityKind::parse`) was *only* visible
    /// to test runners. `try_parse` lifts the typed error to the
    /// public surface so non-test boundaries (sync apply, IPC
    /// validators, future migration probes) can choose to log via
    /// `tracing::error!` and recover, while debug builds escalate the
    /// drift to a `debug_assert!` that fires loudly on the developer
    /// machine.
    pub fn try_parse(value: &str) -> Result<Self, UnknownEntityKind> {
        if let Some(kind) = Self::parse(value) {
            return Ok(kind);
        }
        debug_assert!(
            false,
            "EntityKind::try_parse: unknown entity kind {value:?}; if a new \
             ALL_ENTITY_TYPES entry was added, extend EntityKind::parse \
             and the EntityKind enum to match."
        );
        Err(UnknownEntityKind(value.to_string()))
    }

    /// Filter used by the apply/sync pipeline: returns `true` iff this
    /// kind participates in cross-device sync (i.e. is not a local-only
    /// kind such as `device_state`, `saved_query`, `import_session`).
    /// Mirrors [`super::ALL_SYNCABLE_TYPES`].
    pub const fn is_syncable_kind(self) -> bool {
        !matches!(
            self,
            EntityKind::TaskProviderEventLink
                | EntityKind::DeviceState
                | EntityKind::SavedQuery
                | EntityKind::ImportSession
        )
    }

    /// `true` for composite-PK relationship rows, including the
    /// local-only provider link edge.
    pub const fn is_edge(&self) -> bool {
        matches!(
            self,
            EntityKind::TaskTag
                | EntityKind::TaskDependency
                | EntityKind::TaskCalendarEventLink
                | EntityKind::TaskProviderEventLink
                | EntityKind::HabitCompletion
        )
    }

    /// `true` for entity kinds whose `entity_id` is a natural key
    /// (date string, NFC-normalized memory key, etc.) rather than a
    /// UUIDv7. Natural-key entities never participate in
    /// merge-redirect rewriting because their identity is content-derived
    /// — two devices that observe the same natural key will already
    /// converge on the same row without a redirect tombstone.
    ///
    /// replaces the literal-string `matches!` block
    /// in `lorvex_sync::apply::entity_type_is_natural_key` so the
    /// "natural-key kind" classification has a single source of truth.
    pub const fn is_natural_key(&self) -> bool {
        matches!(
            self,
            EntityKind::DailyReview
                | EntityKind::CurrentFocus
                | EntityKind::FocusSchedule
                | EntityKind::Preference
                | EntityKind::Memory
        )
    }

    /// Map an entity kind to the SQL table that stores its rows, or
    /// `None` for kinds that are not persisted as a single SQL table
    /// (the `ai_changelog` audit stream is append-only and the four
    /// edge kinds use composite-key tables that are also reachable
    /// via [`EntityKind::table_pk`]).
    ///
    /// This method is the single source of truth for the
    /// `entity_type -> table_name` mapping. Without it every caller
    /// (the test fixtures in `lorvex-sync/src/apply/tests`, and the
    /// blob-hash extractor in `outbox_enqueue`) would copy-paste a
    /// `match` against the `ENTITY_*` constants and the duplicated
    /// tables would drift whenever a new entity type landed.
    /// Callers that already have `EntityKind` use it directly,
    /// callers that hold a runtime string parse via
    /// [`EntityKind::parse`] then call this method.
    pub const fn table_name(&self) -> Option<&'static str> {
        Some(match self {
            EntityKind::Task => "tasks",
            EntityKind::List => "lists",
            EntityKind::Habit => "habits",
            EntityKind::Tag => "tags",
            EntityKind::CalendarEvent => "calendar_events",
            EntityKind::Preference => "preferences",
            EntityKind::Memory => "memories",
            EntityKind::MemoryRevision => "memory_revisions",
            EntityKind::DailyReview => "daily_reviews",
            EntityKind::CurrentFocus => "current_focus",
            EntityKind::FocusSchedule => "focus_schedule",
            EntityKind::CalendarSubscription => "calendar_subscriptions",
            EntityKind::TaskReminder => "task_reminders",
            EntityKind::TaskChecklistItem => "task_checklist_items",
            EntityKind::HabitReminderPolicy => "habit_reminder_policies",
            EntityKind::TaskTag => "task_tags",
            EntityKind::TaskDependency => "task_dependencies",
            EntityKind::TaskCalendarEventLink => "task_calendar_event_links",
            EntityKind::HabitCompletion => "habit_completions",
            EntityKind::TaskProviderEventLink => "task_provider_event_links",
            EntityKind::DeviceState => "device_state",
            EntityKind::AiChangelog => "ai_changelog",
            // These classifications have no persistent SQL table in the
            // shared schema.
            EntityKind::SavedQuery | EntityKind::ImportSession => return None,
        })
    }

    /// Map a syncable simple-PK kind to its `(table, pk_column)` pair.
    /// Returns `None` for edges (composite PK), audit stream
    /// (`ai_changelog` is append-only with no upsert table), and
    /// local-only kinds.
    ///
    /// this is the single source of truth that
    /// lived in duplicated `entity_type_to_table` maps. Callers now
    /// route through here.
    pub const fn table_pk(&self) -> Option<(&'static str, &'static str)> {
        Some(match self {
            EntityKind::Task => ("tasks", "id"),
            EntityKind::List => ("lists", "id"),
            EntityKind::Habit => ("habits", "id"),
            EntityKind::Tag => ("tags", "id"),
            EntityKind::CalendarEvent => ("calendar_events", "id"),
            EntityKind::Preference => ("preferences", "key"),
            EntityKind::Memory => ("memories", "key"),
            EntityKind::MemoryRevision => ("memory_revisions", "id"),
            EntityKind::DailyReview => ("daily_reviews", "date"),
            EntityKind::CurrentFocus => ("current_focus", "date"),
            EntityKind::FocusSchedule => ("focus_schedule", "date"),
            EntityKind::CalendarSubscription => ("calendar_subscriptions", "id"),
            EntityKind::TaskReminder => ("task_reminders", "id"),
            EntityKind::TaskChecklistItem => ("task_checklist_items", "id"),
            EntityKind::HabitReminderPolicy => ("habit_reminder_policies", "id"),
            // Edges, audit stream, and local-only kinds: no simple-PK upsert table.
            EntityKind::AiChangelog
            | EntityKind::TaskTag
            | EntityKind::TaskDependency
            | EntityKind::TaskCalendarEventLink
            | EntityKind::HabitCompletion
            | EntityKind::TaskProviderEventLink
            | EntityKind::DeviceState
            | EntityKind::SavedQuery
            | EntityKind::ImportSession => return None,
        })
    }
}

impl std::fmt::Display for EntityKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl std::str::FromStr for EntityKind {
    type Err = UnknownEntityKind;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s).ok_or_else(|| UnknownEntityKind(s.to_string()))
    }
}
