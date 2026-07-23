//! Tests for the `naming` registry — covers `EntityKind` round-trips,
//! topological-order invariants, the `ALL_SYNCABLE_TYPES` superset
//! relationship, and `CalendarAiAccessMode` parsing.

use super::*;

#[test]
fn all_entity_types_has_correct_count() {
    assert_eq!(ALL_ENTITY_TYPES.len(), 16);
}

#[test]
fn all_edge_types_has_correct_count() {
    assert_eq!(ALL_EDGE_TYPES.len(), 4);
}

#[test]
fn all_syncable_types_is_superset_of_entities_and_edges() {
    for entity in ALL_ENTITY_TYPES {
        assert!(
            ALL_SYNCABLE_TYPES.contains(entity),
            "ALL_SYNCABLE_TYPES missing entity: {entity}"
        );
    }
    for edge in ALL_EDGE_TYPES {
        assert!(
            ALL_SYNCABLE_TYPES.contains(edge),
            "ALL_SYNCABLE_TYPES missing edge: {edge}"
        );
    }
    assert_eq!(
        ALL_SYNCABLE_TYPES.len(),
        ALL_ENTITY_TYPES.len() + ALL_EDGE_TYPES.len(),
        "ALL_SYNCABLE_TYPES should contain exactly ALL_ENTITY_TYPES + ALL_EDGE_TYPES"
    );
}

#[test]
fn all_syncable_types_has_no_duplicates() {
    let mut seen = std::collections::HashSet::new();
    for entry in ALL_SYNCABLE_TYPES {
        assert!(
            seen.insert(*entry),
            "Duplicate in ALL_SYNCABLE_TYPES: {entry}"
        );
    }
}

#[test]
fn topological_order_contains_all_entities_and_edges() {
    // Every entity type (except ai_changelog which is audit-only) and every
    // edge type should appear in the topological order.
    for entity in ALL_ENTITY_TYPES {
        if *entity == ENTITY_AI_CHANGELOG {
            continue; // ai_changelog is audit stream, not sync-applied via topo order
        }
        assert!(
            TOPOLOGICAL_ENTITY_ORDER.contains(entity),
            "Missing entity in topological order: {entity}"
        );
    }
    for edge in ALL_EDGE_TYPES {
        assert!(
            TOPOLOGICAL_ENTITY_ORDER.contains(edge),
            "Missing edge in topological order: {edge}"
        );
    }
}

#[test]
fn topological_order_has_no_duplicates() {
    let mut seen = std::collections::HashSet::new();
    for entry in TOPOLOGICAL_ENTITY_ORDER {
        assert!(
            seen.insert(*entry),
            "Duplicate in topological order: {entry}"
        );
    }
}

#[test]
fn list_before_task_in_topological_order() {
    let list_pos = TOPOLOGICAL_ENTITY_ORDER
        .iter()
        .position(|e| *e == ENTITY_LIST)
        .unwrap();
    let task_pos = TOPOLOGICAL_ENTITY_ORDER
        .iter()
        .position(|e| *e == ENTITY_TASK)
        .unwrap();
    assert!(
        list_pos < task_pos,
        "list must appear before task in topological order"
    );
}

#[test]
fn edges_after_all_aggregate_roots() {
    let first_edge_pos = TOPOLOGICAL_ENTITY_ORDER
        .iter()
        .position(|e| *e == EDGE_TASK_TAG)
        .unwrap();
    let last_root_pos = TOPOLOGICAL_ENTITY_ORDER
        .iter()
        .position(|e| *e == ENTITY_FOCUS_SCHEDULE)
        .unwrap();
    assert!(
        last_root_pos < first_edge_pos,
        "edges must appear after all aggregate roots"
    );
}

// -----------------------------------------------------------------------
// CalendarAiAccessMode tests
// -----------------------------------------------------------------------

#[test]
fn calendar_access_mode_parse_strict_roundtrip() {
    let variants = [
        CalendarAiAccessMode::Off,
        CalendarAiAccessMode::BusyOnly,
        CalendarAiAccessMode::FullDetails,
    ];
    for v in &variants {
        let s = v.as_str();
        let parsed = CalendarAiAccessMode::parse_strict(s).expect("known mode parses");
        assert_eq!(parsed, *v, "roundtrip failed for {s}");
    }
}

#[test]
fn calendar_access_mode_parse_strict_rejects_unknown() {
    assert_eq!(CalendarAiAccessMode::parse_strict("unknown"), None);
    assert_eq!(CalendarAiAccessMode::parse_strict(""), None);
}

#[test]
fn calendar_access_mode_includes_provider() {
    assert!(!CalendarAiAccessMode::Off.includes_provider());
    assert!(CalendarAiAccessMode::BusyOnly.includes_provider());
    assert!(CalendarAiAccessMode::FullDetails.includes_provider());
}

#[test]
fn calendar_access_mode_includes_details() {
    assert!(!CalendarAiAccessMode::Off.includes_details());
    assert!(!CalendarAiAccessMode::BusyOnly.includes_details());
    assert!(CalendarAiAccessMode::FullDetails.includes_details());
}

#[test]
fn calendar_access_mode_default_is_busy_only() {
    assert_eq!(
        CalendarAiAccessMode::default_mode(),
        CalendarAiAccessMode::BusyOnly
    );
}

#[test]
fn calendar_access_mode_as_str_values() {
    assert_eq!(CalendarAiAccessMode::Off.as_str(), "off");
    assert_eq!(CalendarAiAccessMode::BusyOnly.as_str(), "busy_only");
    assert_eq!(CalendarAiAccessMode::FullDetails.as_str(), "full_details");
}

// -----------------------------------------------------------------------
// EntityKind tests (#2985 RF-H6)
// -----------------------------------------------------------------------

#[test]
fn entity_kind_round_trips_every_syncable_string() {
    // prefer the typed `try_parse` constructor over
    // `parse().unwrap_or_else(|| panic!(...))`. The former carries
    // a typed `UnknownEntityKind` reason for the diagnostic, fires
    // a `debug_assert!` so a future ALL_SYNCABLE_TYPES extension
    // without an `EntityKind` extension fails loudly during dev,
    // and is the same surface non-test callers should reach for.
    for raw in ALL_SYNCABLE_TYPES {
        let kind = EntityKind::try_parse(raw)
            .unwrap_or_else(|err| panic!("missing EntityKind for {raw}: {err}"));
        assert_eq!(kind.as_str(), *raw, "EntityKind::as_str must match input");
        assert!(kind.is_syncable_kind(), "{raw} should be syncable");
    }
}

#[test]
fn entity_kind_try_parse_round_trips_every_known_entity_string() {
    // lock in that `try_parse` covers every
    // `ALL_ENTITY_TYPES` / `ALL_EDGE_TYPES` entry. Pre-fix the
    // coverage was implicit in the test above plus
    // `entity_kind_round_trips_local_only_strings`; making it
    // explicit here means a future ALL_ENTITY_TYPES extension
    // that forgets to update the `EntityKind` enum trips a clear
    // failure pointing at the typed constructor.
    for raw in ALL_ENTITY_TYPES.iter().chain(ALL_EDGE_TYPES.iter()) {
        let kind = EntityKind::try_parse(raw)
            .unwrap_or_else(|err| panic!("missing EntityKind for {raw}: {err}"));
        assert_eq!(kind.as_str(), *raw);
    }
}

// Negative coverage for the unknown-entity path lives on
// [`EntityKind::parse`] / `entity_kind_parse_rejects_unknown`.
// `try_parse` is the closed-set strict constructor — it
// `debug_assert!`s on unknown input by design (L2),
// so a debug-build test that invokes the unknown arm would panic
// at the assertion site rather than reach the typed `Err`.

#[test]
fn entity_kind_round_trips_local_only_strings() {
    for raw in [
        EDGE_TASK_PROVIDER_EVENT_LINK,
        ENTITY_DEVICE_STATE,
        ENTITY_SAVED_QUERY,
        ENTITY_IMPORT_SESSION,
    ] {
        let kind = EntityKind::parse(raw).unwrap();
        assert_eq!(kind.as_str(), raw);
        assert!(
            !kind.is_syncable_kind(),
            "{raw} must not be marked syncable"
        );
    }
}

#[test]
fn entity_kind_parse_rejects_unknown() {
    assert!(EntityKind::parse("definitely-not-an-entity").is_none());
    assert!(EntityKind::parse("").is_none());
}

#[test]
fn entity_kind_is_edge_matches_edge_set() {
    for raw in ALL_EDGE_TYPES {
        let kind = EntityKind::parse(raw).unwrap();
        assert!(kind.is_edge(), "{raw} should be classified as edge");
    }
    for raw in ALL_ENTITY_TYPES {
        let kind = EntityKind::parse(raw).unwrap();
        assert!(!kind.is_edge(), "{raw} must not be classified as edge");
    }
}

#[test]
fn entity_kind_table_pk_covers_simple_pk_syncable_types() {
    // Every syncable kind that ISN'T an edge or `ai_changelog`
    // must resolve to a simple-PK (table, pk) pair. This is the
    // RF-H4 source-of-truth that sync/outbox code routes through.
    for kind in [
        EntityKind::Task,
        EntityKind::List,
        EntityKind::Habit,
        EntityKind::Tag,
        EntityKind::CalendarEvent,
        EntityKind::Preference,
        EntityKind::Memory,
        EntityKind::MemoryRevision,
        EntityKind::DailyReview,
        EntityKind::CurrentFocus,
        EntityKind::FocusSchedule,
        EntityKind::CalendarSubscription,
        EntityKind::TaskReminder,
        EntityKind::TaskChecklistItem,
        EntityKind::HabitReminderPolicy,
    ] {
        assert!(
            kind.table_pk().is_some(),
            "{kind} should have a simple-PK table mapping"
        );
    }
    // Edges + audit stream + local-only kinds: no simple-PK row.
    for kind in [
        EntityKind::AiChangelog,
        EntityKind::TaskTag,
        EntityKind::TaskDependency,
        EntityKind::TaskCalendarEventLink,
        EntityKind::HabitCompletion,
        EntityKind::TaskProviderEventLink,
        EntityKind::DeviceState,
        EntityKind::SavedQuery,
        EntityKind::ImportSession,
    ] {
        assert!(
            kind.table_pk().is_none(),
            "{kind} must not resolve to a simple-PK table"
        );
    }
}

#[test]
fn entity_kind_table_name_covers_every_persistent_kind() {
    // `table_name()` is the single source of
    // truth that string-typed `match entity_type { TASK =>
    // "tasks", ... }` blocks across
    // `outbox_enqueue::extract_blob_hashes`, and the sync-apply test
    // fixtures all route through. Every
    // entity kind that is persisted as a single table — every
    // syncable simple-PK kind, every edge, plus the audit
    // stream and the local-only `device_state` / `saved_query`
    // / `feedback` tables — must resolve to a non-empty SQL
    // identifier.
    let cases: &[(EntityKind, &str)] = &[
        (EntityKind::Task, "tasks"),
        (EntityKind::List, "lists"),
        (EntityKind::Habit, "habits"),
        (EntityKind::Tag, "tags"),
        (EntityKind::CalendarEvent, "calendar_events"),
        (EntityKind::Preference, "preferences"),
        (EntityKind::Memory, "memories"),
        (EntityKind::MemoryRevision, "memory_revisions"),
        (EntityKind::DailyReview, "daily_reviews"),
        (EntityKind::CurrentFocus, "current_focus"),
        (EntityKind::FocusSchedule, "focus_schedule"),
        (EntityKind::CalendarSubscription, "calendar_subscriptions"),
        (EntityKind::TaskReminder, "task_reminders"),
        (EntityKind::TaskChecklistItem, "task_checklist_items"),
        (EntityKind::HabitReminderPolicy, "habit_reminder_policies"),
        (EntityKind::TaskTag, "task_tags"),
        (EntityKind::TaskDependency, "task_dependencies"),
        (
            EntityKind::TaskCalendarEventLink,
            "task_calendar_event_links",
        ),
        (EntityKind::HabitCompletion, "habit_completions"),
        (
            EntityKind::TaskProviderEventLink,
            "task_provider_event_links",
        ),
        (EntityKind::AiChangelog, "ai_changelog"),
        (EntityKind::DeviceState, "device_state"),
    ];
    for (kind, expected) in cases {
        assert_eq!(
            kind.table_name(),
            Some(*expected),
            "EntityKind::table_name mismatch for {kind:?}"
        );
    }
    // The synthetic `import_session` audit classification has no
    // single-table mapping by design.
    assert_eq!(EntityKind::ImportSession.table_name(), None);
}

#[test]
fn entity_kind_serde_uses_canonical_string() {
    let json = serde_json::to_string(&EntityKind::CalendarEvent).unwrap();
    assert_eq!(json, "\"calendar_event\"");
    let parsed: EntityKind = serde_json::from_str("\"task_checklist_item\"").unwrap();
    assert_eq!(parsed, EntityKind::TaskChecklistItem);
}

#[test]
fn entity_kind_from_str_surfaces_unknown_error() {
    let err: UnknownEntityKind = "bogus".parse::<EntityKind>().unwrap_err();
    assert_eq!(err.0, "bogus");
    assert!(err.to_string().contains("unknown entity kind"));
}

#[test]
fn calendar_access_mode_serde_roundtrip() {
    let mode = CalendarAiAccessMode::BusyOnly;
    let json = serde_json::to_string(&mode).unwrap();
    let deserialized: CalendarAiAccessMode = serde_json::from_str(&json).unwrap();
    assert_eq!(deserialized, mode);
}
