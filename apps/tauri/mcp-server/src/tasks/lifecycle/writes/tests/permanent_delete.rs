//! `permanent_delete_task`: cascade-tombstone payloads must carry the
//! full pre-delete row (#2945-M2), not the degenerate composite-PK
//! shape that earlier delete helpers emitted.

use super::support::*;

/// Regression for #2945-M2. Pre-fix the cascade tombstones synthesized
/// from `{id, task_id}` (or composite halves) with no version /
/// created_at / text fields. Sibling delete paths (#2818, #2928-H1)
/// snapshot the full pre-delete row JSON so peers that GC'd their
/// copy can rebuild `before_json` from the tombstone envelope.
/// `permanent_delete_task` now does the same for every cascaded child
/// and edge: `task_tags`, `task_checklist_items`, `task_reminders`,
/// `task_calendar_event_links`. Dependencies are snapshotted in
/// `remove_task_from_all_deps`; provider links and reminder delivery
/// state are not in `ALL_SYNCABLE_TYPES`, so they don't reach the
/// outbox.
// #4423: `#[serial(hlc)]` — see the matching annotation on
// `reviews::daily::tests::review_reads_include_linked_arrays` for
// the full rationale.
#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_cascade_tombstones_carry_full_pre_delete_rows() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex poisoned");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let now = "2026-04-01T00:00:00Z";
    let archived = "2026-04-15T00:00:00Z";

    // Parent task — already archived so the Trash gate passes.
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000011d")
        .title("Task 1")
        .created_at(now)
        .archived_at(Some(archived))
        .insert(&conn);

    // Tag + edge.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001101', 'work', 'work', '0000000000000_0000_0000000000000000', ?1, ?1)",
        [now],
    )
    .expect("insert tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000011d', '01966a3f-7c8b-7d4e-8f3a-000000001101', '0000000000000_0000_0000000000000000', ?1)",
        [now],
    )
    .expect("insert task_tag");

    // Checklist item.
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001102', '01966a3f-7c8b-7d4e-8f3a-00000000011d', 0, 'step one', '0000000000000_0000_0000000000000000', ?1, ?1)",
        [now],
    )
    .expect("insert checklist item");

    // Reminder.
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001103', '01966a3f-7c8b-7d4e-8f3a-00000000011d', '2026-05-01T09:00:00Z', '0000000000000_0000_0000000000000000', ?1)",
        [now],
    )
    .expect("insert reminder");

    // Calendar event + link.
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001104', 'Standup', '2026-05-01', '0000000000000_0000_0000000000000000', ?1, ?1)",
        [now],
    )
    .expect("insert calendar event");
    conn.execute(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000011d', '01966a3f-7c8b-7d4e-8f3a-000000001104', '0000000000000_0000_0000000000000000', ?1, ?1)",
        [now],
    )
    .expect("insert calendar link");

    permanent_delete_task(
        &conn,
        PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011d".to_string(),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("permanent delete should succeed for archived task");

    // Helper: load the most recent outbox payload for a (type, id).
    let outbox_payload = |entity_type: &str, entity_id: &str| -> Value {
        let payload_text: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2
                 ORDER BY id DESC LIMIT 1",
                rusqlite::params![entity_type, entity_id],
                |row| row.get(0),
            )
            .unwrap_or_else(|err| {
                panic!("expected outbox row for ({entity_type}, {entity_id}): {err}")
            });
        serde_json::from_str(&payload_text).expect("outbox payload is JSON")
    };

    // task_tags: full row carries tag_id + version + created_at — not
    // just the composite-PK fields the pre-fix code emitted.
    let tag_payload = outbox_payload(
        "task_tag",
        "01966a3f-7c8b-7d4e-8f3a-00000000011d:01966a3f-7c8b-7d4e-8f3a-000000001101",
    );
    assert_eq!(
        tag_payload.get("task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000011d"),
        "tag tombstone task_id"
    );
    assert_eq!(
        tag_payload.get("tag_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "tag tombstone tag_id"
    );
    assert!(
        tag_payload.get("version").is_some(),
        "tag tombstone must carry version (full pre-delete row, not just composite key)"
    );
    assert!(
        tag_payload.get("created_at").is_some(),
        "tag tombstone must carry created_at"
    );

    // task_checklist_items: pre-delete row keeps `text` + `position` so
    // a peer can render the lost item to the user.
    let cli_payload = outbox_payload(
        "task_checklist_item",
        "01966a3f-7c8b-7d4e-8f3a-000000001102",
    );
    assert_eq!(
        cli_payload.get("id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-000000001102")
    );
    assert_eq!(
        cli_payload.get("task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000011d")
    );
    assert_eq!(
        cli_payload.get("text").and_then(Value::as_str),
        Some("step one"),
        "checklist tombstone must carry text (full row, not just {{id, task_id}})"
    );
    assert!(
        cli_payload.get("position").is_some(),
        "checklist tombstone must carry position"
    );
    assert!(
        cli_payload.get("version").is_some(),
        "checklist tombstone must carry version"
    );
    assert!(
        cli_payload.get("created_at").is_some(),
        "checklist tombstone must carry created_at"
    );

    // task_reminders: pre-delete row keeps `reminder_at` so the peer
    // can rebuild before_json with the wall-clock the user scheduled.
    let rem_payload = outbox_payload("task_reminder", "01966a3f-7c8b-7d4e-8f3a-000000001103");
    assert_eq!(
        rem_payload.get("id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-000000001103")
    );
    assert_eq!(
        rem_payload.get("task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000011d")
    );
    assert_eq!(
        rem_payload.get("reminder_at").and_then(Value::as_str),
        Some("2026-05-01T09:00:00Z"),
        "reminder tombstone must carry reminder_at"
    );
    assert!(
        rem_payload.get("version").is_some(),
        "reminder tombstone must carry version"
    );
    assert!(
        rem_payload.get("created_at").is_some(),
        "reminder tombstone must carry created_at"
    );

    // task_calendar_event_links: full row keeps the version + both
    // timestamps; pre-fix the payload was just the two-key composite.
    let link_payload = outbox_payload(
        "task_calendar_event_link",
        "01966a3f-7c8b-7d4e-8f3a-00000000011d:01966a3f-7c8b-7d4e-8f3a-000000001104",
    );
    assert_eq!(
        link_payload.get("task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000011d")
    );
    assert_eq!(
        link_payload
            .get("calendar_event_id")
            .and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-000000001104")
    );
    assert!(
        link_payload.get("version").is_some(),
        "calendar-link tombstone must carry version"
    );
    assert!(
        link_payload.get("created_at").is_some(),
        "calendar-link tombstone must carry created_at"
    );
    assert!(
        link_payload.get("updated_at").is_some(),
        "calendar-link tombstone must carry updated_at"
    );
}
