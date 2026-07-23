#[cfg(test)]
use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, ENTITY_PREFERENCE};
use lorvex_domain::naming::{
    ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW,
    ENTITY_FOCUS_SCHEDULE, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_TAG, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER,
};

/// Tables containing resettable user content. Order: children before parents
/// to respect FK constraints when SQLite cascades aren't relied on (this loop
/// runs with `foreign_keys = OFF`, so child rows are deleted before parents
/// for clarity, not necessity).
///
/// **What is NOT in this list — and why:**
/// * `sync_outbox`, `sync_tombstones`: the reset
///   pipeline emits an `OP_DELETE` envelope (and matching tombstone) per
///   syncable aggregate-root row BEFORE the bulk wipe. Those just-emitted
///   envelopes/tombstones MUST survive the wipe so the next sync cycle pushes
///   them to peers — without them, peers that hadn't observed the wipe still
///   hold the data and resurrect it on the next sync cycle (#2944-H4).
/// * `local_sync_owner`, `local_counters`, `mcp_host_authority`,
///   `schema_migrations`: local-only identity / runtime knobs preserved
///   across reset (see `RUNTIME_ONLY_TABLES`).
///
/// Drift between this list and `001_schema.sql` is enforced by the
/// `tests::content_tables_covers_every_user_data_table_in_schema` guard.
pub(super) const CONTENT_TABLES: &[&str] = &[
    // Edges and children (FK dependents first)
    "task_checklist_items",
    "task_calendar_event_links",
    "task_provider_event_links",
    "task_reminder_delivery_state",
    "task_reminders",
    "task_dependencies",
    "task_recurrence_exceptions",
    "task_tags",
    "daily_review_task_links",
    "daily_review_list_links",
    "habit_completions",
    "habit_reminder_delivery_state",
    "habit_reminder_policies",
    // Parent-owned weekday set for `weekly` habits, rebuilt from the
    // habit's own sync payload (like `calendar_event_attendees`). Not an
    // independently-synced entity, so it clears as habit content.
    "habit_weekdays",
    "focus_schedule_blocks",
    "focus_schedule",
    "current_focus_items",
    "current_focus",
    "daily_reviews",
    "ai_changelog_entities",
    "ai_changelog",
    "memory_revisions",
    "memories",
    "calendar_event_recurrence_exceptions",
    "calendar_event_attendee_shadow",
    "calendar_event_attendees",
    "calendar_subscriptions",
    "provider_calendar_events",
    "provider_scope_runtime_state",
    "calendar_events",
    "habits",
    "tasks",
    "lists",
    "tags",
    "preferences",
    "device_state",
    // Inbound-side sync state (nothing useful to peers — apply cycles, pending
    // FK-retry inbox, payload shadow LWW state, conflict audit, device cursors,
    // sync_checkpoints with the device id). The `sync_outbox` and
    // `sync_tombstones` tables are deliberately absent — see module doc.
    "sync_pending_inbox",
    "sync_quarantine_blocklist",
    "sync_conflict_log",
    "sync_device_cursors",
    "sync_payload_shadow",
    "sync_checkpoints",
    // MCP server state
    "mcp_idempotency",
    // Diagnostics
    "error_logs",
];

/// Sync infrastructure tables that the reset emits envelopes/tombstones into
/// and therefore deliberately preserves across the bulk wipe. Listed here so
/// the schema drift guard recognizes them as classified — they are neither
/// "content cleared on reset" nor "local-only runtime state."
///
/// This list is consumed at runtime so `reset_all_data_db` can
/// `debug_assert!` the listed tables exist before the wipe — catching the
/// case where a future schema rename silently drops one of these from the
/// live DB while the classification list still references it. The drift
/// guard also depends on this list, so it is a single source of truth.
pub(super) const SYNC_INFRASTRUCTURE_PRESERVED: &[&str] = &["sync_outbox", "sync_tombstones"];

/// Aggregate-root tables walked in `enqueue_aggregate_root_tombstones` to emit
/// `OP_DELETE` envelopes for every row before the bulk DELETE wipes the
/// content tables. The receiver's apply pipeline cascade-tombstones edges and
/// child collections (task_tags, task_reminders, task_checklist_items,
/// task_dependencies, calendar_event_attendees, current_focus_items,
/// focus_schedule_blocks, daily_review links, habit_completions,
/// habit_reminder_policies) — matching the contract of every other
/// aggregate-root delete in the app (see `commands/lists.rs::delete_list`,
/// `commands/calendar_events/mutations/delete.rs`, etc).
///
/// Order is irrelevant for envelopes (each row is enqueued independently),
/// but mirrors topological dependency for readability.
///
/// Local-only entity types intentionally absent: `device_state` (per-device UI state),
/// `error_logs`, `provider_*` tables, `mcp_idempotency`, all
/// `sync_*` tables. Syncable-but-special entities are handled by the reset
/// special pass below instead of this aggregate-root walker.
pub(super) const SYNCABLE_AGGREGATE_TABLES: &[(&str, &str, &str)] = &[
    // (table, pk_column, entity_type)
    ("tasks", "id", ENTITY_TASK),
    ("lists", "id", ENTITY_LIST),
    ("tags", "id", ENTITY_TAG),
    ("calendar_events", "id", ENTITY_CALENDAR_EVENT),
    ("habits", "id", ENTITY_HABIT),
    ("memories", "key", ENTITY_MEMORY),
    ("daily_reviews", "date", ENTITY_DAILY_REVIEW),
    ("focus_schedule", "date", ENTITY_FOCUS_SCHEDULE),
    ("current_focus", "date", ENTITY_CURRENT_FOCUS),
    ("calendar_subscriptions", "id", ENTITY_CALENDAR_SUBSCRIPTION),
];

/// Syncable entities that need reset tombstones but cannot use the generic
/// aggregate-root walker above:
///
/// * `preference` delete payloads need the canonical pre-delete snapshot and
///   must skip local-only keys.
/// * `ai_changelog` is append-only in normal operation; reset emits a marked
///   delete envelope so peers can purge audit rows without accepting ordinary
///   changelog deletes.
#[cfg(test)]
pub(super) const SYNCABLE_RESET_SPECIAL_ENTITY_TYPES: &[&str] =
    &[ENTITY_PREFERENCE, ENTITY_AI_CHANGELOG];

/// independent-child sync entities — children that
/// have their own sync identity in `naming::ALL_SYNCABLE_TYPES` (their
/// own envelopes flow through the outbox/apply pipeline) AND
/// cascade-delete from a parent aggregate via SQLite FK rules. The
/// parent-tombstone cascade in the apply pipeline correctly removes
/// these rows on a peer that has already received the parent delete,
/// but a peer that receives a late-arriving child upsert envelope AFTER
/// the parent delete has applied gets the child upsert preflight-
/// deferred (`MissingDependency`) into `sync_pending_inbox`, where it
/// ages out — leaving stale child state if the upsert ever resurfaces
/// from a third device.
///
/// The second-pass walk emits per-row `OP_DELETE` envelopes for each
/// independent-child row BEFORE the bulk wipe so peers receive an
/// authoritative tombstone keyed on the child's own sync identity. The
/// payload carries the parent-id field used for FK preflight on the
/// receiver, matching the contract of the per-child delete sites
/// elsewhere in the app (e.g. `task_reminders::dismiss_reminder`,
/// `checklist::delete_task_checklist_item`).
///
/// (table, pk_column, parent_fk_column, entity_type, parent_entity_type)
pub(super) const SYNCABLE_INDEPENDENT_CHILD_TABLES: &[(&str, &str, &str, &str, &str)] = &[
    (
        "task_reminders",
        "id",
        "task_id",
        ENTITY_TASK_REMINDER,
        ENTITY_TASK,
    ),
    (
        "task_checklist_items",
        "id",
        "task_id",
        ENTITY_TASK_CHECKLIST_ITEM,
        ENTITY_TASK,
    ),
    (
        "habit_reminder_policies",
        "id",
        "habit_id",
        ENTITY_HABIT_REMINDER_POLICY,
        ENTITY_HABIT,
    ),
    (
        "memory_revisions",
        "id",
        "memory_key",
        ENTITY_MEMORY_REVISION,
        ENTITY_MEMORY,
    ),
];

/// Tables that intentionally survive a `reset_all_data` call.
///
/// "Reset all data" wipes user content and sync state but preserves
/// local-only identity / runtime-managed state — re-creating these
/// rows would force a re-handshake that's strictly worse than the
/// reset experience. Anything user-visible belongs in `CONTENT_TABLES`,
/// not here.
#[cfg(test)]
pub(super) const RUNTIME_ONLY_TABLES: &[&str] = &[
    "schema_migrations",  // Migration ledger
    "local_sync_owner",   // Per-device sync ownership lease
    "local_counters",     // Typed counter store (issue #2982-RT-H7)
    "mcp_host_authority", // Active MCP host (issue #2982-RT-H4)
];
