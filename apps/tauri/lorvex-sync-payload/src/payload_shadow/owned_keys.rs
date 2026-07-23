//! Static allowlist of locally-known JSON keys per entity kind.
//!
//! Both [`super::merge::merge_payload_with_shadow`] (overlay path) and
//! the shadow-write path in [`super::crud`] consult this table to
//! decide which keys are owned by the local schema and which are
//! forward-compat unknowns that the shadow row preserves verbatim.
//! The parity test in `super::tests` locks the allowlist against the
//! SQL schema so a column add/remove that doesn't update the slice
//! fires a typed test failure rather than silently misclassifying
//! shadow data ( split this out of `merge.rs`
//! to keep that module focused on the merge algorithm).

use lorvex_domain::naming::EntityKind;

/// dispatch via [`EntityKind`] so a typo
/// in a runtime string surfaces as a typed `EntityKind::parse`
/// failure (the empty fallback) rather than silently producing an
/// empty-keys slice that would dump every shadow field into the
/// "unknown" forward-compat bucket.
pub(super) fn owned_keys_for_entity(entity_type: &str) -> &'static [&'static str] {
    let Some(kind) = EntityKind::parse(entity_type) else {
        return &[];
    };
    match kind {
        EntityKind::Task => &[
            "id",
            "title",
            "body",
            "raw_input",
            "ai_notes",
            "status",
            "list_id",
            "priority",
            "due_date",
            "due_time",
            "estimated_minutes",
            "recurrence",
            "recurrence_exceptions",
            "spawned_from",
            "recurrence_group_id",
            "canonical_occurrence_date",
            "created_at",
            "updated_at",
            "completed_at",
            "last_deferred_at",
            "planned_date",
            "defer_count",
            "last_defer_reason",
            "recurrence_instance_key",
            "archived_at",
            "available_from",
            "version",
        ],
        EntityKind::List => &[
            "id",
            "name",
            "color",
            "icon",
            "description",
            "ai_notes",
            "archived_at",
            "created_at",
            "updated_at",
            // Synced manual display order — the generic pragma enqueue
            // snapshot copies it, so it is an owned key.
            "position",
            "version",
        ],
        EntityKind::Habit => &[
            "id",
            "name",
            "icon",
            "color",
            "cue",
            "frequency_type",
            // `weekly` weekday set — a payload-only synthetic materialized
            // from the `habit_weekdays` child (not a `habits` column).
            "weekdays",
            "per_period_target",
            "day_of_month",
            "target_count",
            "milestone_target",
            "archived",
            // persisted dedup key derived from `name`.
            "lookup_key",
            "position",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::Tag => &[
            "id",
            "display_name",
            "lookup_key",
            "color",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::CalendarEvent => &[
            "id",
            "title",
            "description",
            "start_date",
            "start_time",
            "end_date",
            "end_time",
            "all_day",
            "location",
            "url",
            "color",
            "recurrence",
            "timezone",
            "recurrence_exceptions",
            "event_type",
            "person_name",
            "series_id",
            "recurrence_instance_date",
            "created_at",
            "updated_at",
            "attendees",
            "version",
        ],
        EntityKind::Preference => &["key", "value", "updated_at", "version"],
        EntityKind::Memory => &["id", "key", "content", "updated_at", "version"],
        EntityKind::MemoryRevision => &[
            "id",
            "memory_key",
            "content",
            "operation",
            "source_revision_id",
            "actor",
            "created_at",
            "version",
        ],
        EntityKind::DailyReview => &[
            "date",
            "summary",
            "mood",
            "energy_level",
            "wins",
            "blockers",
            "learnings",
            "ai_synthesis",
            "timezone",
            "created_at",
            "updated_at",
            "linked_task_ids",
            "linked_list_ids",
            "version",
        ],
        EntityKind::CurrentFocus => &[
            "date",
            "briefing",
            "timezone",
            "created_at",
            "updated_at",
            "task_ids",
            "version",
        ],
        EntityKind::FocusSchedule => &[
            "date",
            "rationale",
            "timezone",
            "created_at",
            "updated_at",
            "blocks",
            "version",
        ],
        EntityKind::CalendarSubscription => &[
            "id",
            "name",
            "url",
            "color",
            "enabled",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::TaskReminder => &[
            "id",
            "task_id",
            "reminder_at",
            "dismissed_at",
            "cancelled_at",
            "created_at",
            "original_local_time",
            "original_tz",
            "version",
        ],
        EntityKind::TaskChecklistItem => &[
            "id",
            "task_id",
            "position",
            "text",
            "completed_at",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::HabitReminderPolicy => &[
            "id",
            "habit_id",
            "reminder_time",
            "enabled",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::AiChangelog => &[
            "id",
            "timestamp",
            "operation",
            "entity_type",
            "entity_id",
            "entity_ids",
            "summary",
            "initiated_by",
            "mcp_tool",
            "source_device_id",
            "before_json",
            "after_json",
            // MCP revert-token cache. The payload loader emits it and the
            // apply handler reads + inserts it (see `apply/changelog`), so it
            // round-trips through sync; an owned key, not a forward-compat
            // unknown.
            "undo_token",
            // #3033-M4: typed preview discriminator. Stamped by the
            // dispatch_dry_run / write_preview_audit_entry path so
            // peers reading the audit feed can filter previews
            // structurally rather than via `mcp_tool LIKE '%_preview'`.
            "is_preview",
        ],
        EntityKind::TaskTag => &["task_id", "tag_id", "created_at", "version"],
        EntityKind::TaskDependency => &["task_id", "depends_on_task_id", "created_at", "version"],
        EntityKind::TaskCalendarEventLink => &[
            "task_id",
            "calendar_event_id",
            "created_at",
            "updated_at",
            "version",
        ],
        EntityKind::HabitCompletion => &[
            "habit_id",
            "completed_date",
            "value",
            "note",
            "created_at",
            "updated_at",
            "version",
        ],
        // Local-only kinds never participate in payload-shadow
        // forward-compat preservation — they are not synced.
        EntityKind::TaskProviderEventLink
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => &[],
    }
}
