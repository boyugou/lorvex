use super::is_canonical_uuid;
use lorvex_domain::naming;

/// drift guard. The day-scoped delete handlers
/// (`apply_current_focus_delete`, `apply_focus_schedule_delete`,
/// `apply_daily_review_delete`) cascade to their materialization
/// child tables (`current_focus_items`, `focus_schedule_blocks`,
/// `daily_review_task_links`, `daily_review_list_links`) WITHOUT
/// pre-tombstoning, unlike `apply_task_delete` per.
/// That is safe today because none of those child tables are
/// independently synced — they have no `version` column, no
/// outbox enqueue site, and no entry in `dispatch::ENTITY_HANDLERS`,
/// so the parent upsert is the only path that ever (re)materializes
/// them. A contributor who later promotes one of these tables to a
/// real synced entity (adding it to `ALL_SYNCABLE_TYPES`) MUST also
/// migrate the parent delete onto the cascading-tombstone helper.
/// This test fails the moment the assumption breaks so the cascade
/// gap can never silently propagate.
#[test]
fn day_scoped_materialization_tables_are_not_independently_synced() {
    const FORBIDDEN: &[&str] = &[
        "current_focus_items",
        "focus_schedule_blocks",
        "daily_review_task_links",
        "daily_review_list_links",
    ];
    for child_type in FORBIDDEN {
        assert!(
            !naming::ALL_SYNCABLE_TYPES.contains(child_type),
            "{child_type} was promoted to ALL_SYNCABLE_TYPES — \
             the parent day-scoped delete handler still cascades \
             without pre-tombstoning, which means peers running an \
             older build will permanently lose any edge they hadn't \
             themselves modified (/ #2993-H1). Migrate \
             the parent delete onto `tombstone_child_rows` before \
             enabling sync for this entity type."
        );
    }
}

#[test]
fn accepts_valid_uuids() {
    assert!(is_canonical_uuid("01943a6d-b5c8-7e1f-9a12-3456789abcde"));
    assert!(is_canonical_uuid("550e8400-e29b-41d4-a716-446655440000"));
    assert!(is_canonical_uuid("00000000-0000-0000-0000-000000000000"));
}

#[test]
fn rejects_provider_event_keys() {
    // EventKit calendarItemExternalIdentifier
    assert!(!is_canonical_uuid(
        "3A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D6E7F"
    ));
    // VEVENT UID
    assert!(!is_canonical_uuid("uid-12345@example.com"));
    // Arbitrary provider key
    assert!(!is_canonical_uuid("eventkit-cal-item-123"));
    // Too short
    assert!(!is_canonical_uuid("550e8400-e29b-41d4"));
    // No dashes
    assert!(!is_canonical_uuid("550e8400e29b41d4a716446655440000xxxx"));
    // Wrong dash positions
    assert!(!is_canonical_uuid("550e84-00e29b-41d4a-716-446655440000"));
    // Empty
    assert!(!is_canonical_uuid(""));
}
