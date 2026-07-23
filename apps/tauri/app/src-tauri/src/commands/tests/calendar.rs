use super::*;

#[test]
fn normalize_calendar_recurrence_rejects_invalid_payload() {
    // error messages now come from the canonical
    // `lorvex_domain::validation::ValidationError`, which keys on
    // `field`/`expected` pairs (e.g. `field: "recurrence", expected:
    // "FREQ field (DAILY/WEEKLY/MONTHLY/YEARLY)"`). The substring
    // assertions below pin down what every assertion truly cares
    // about — "is the offending field surfaced?" — without coupling
    // to either the legacy hand-rolled string or the canonical
    // formatter's exact wording.
    let err = normalize_calendar_recurrence(Some("{\"INTERVAL\":1}".to_string()))
        .expect_err("missing FREQ should fail");
    assert!(
        err.contains("FREQ"),
        "missing-FREQ error must mention FREQ; got: {err}"
    );

    // BYDAY is now valid on WEEKLY *and* MONTHLY/YEARLY
    // recurrence — the canonical contract is keyed off RFC 5545 §3.3.10
    // (see `mcp_server::server_contract::task::recurrence` and the
    // `is_valid_byday_token_for_freq` helper). DAILY remains an
    // unambiguous rejection: BYDAY has no defined ordinal-or-bare
    // semantics on a daily rule, so the validator surfaces the
    // canonical "BYDAY is only valid for WEEKLY, MONTHLY, or YEARLY"
    // error. Pre-fix the fixture asserted the older WEEKLY-only
    // contract and silently rotted when the validator was loosened.
    let err =
        normalize_calendar_recurrence(Some("{\"FREQ\":\"DAILY\",\"BYDAY\":[\"MO\"]}".to_string()))
            .expect_err("BYDAY on DAILY must reject");
    assert!(
        err.contains("only valid for WEEKLY"),
        "BYDAY error must mention the WEEKLY/MONTHLY/YEARLY allow-list; got: {err}"
    );

    let err =
        normalize_calendar_recurrence(Some("{\"FREQ\":\"WEEKLY\",\"INTERVAL\":0}".to_string()))
            .expect_err("INTERVAL must be positive");
    assert!(
        err.contains("positive integer"),
        "INTERVAL error must mention positive-integer constraint; got: {err}"
    );
}

#[test]
fn normalize_calendar_recurrence_accepts_plain_frequency_string() {
    let normalized = normalize_calendar_recurrence(Some("WEEKLY".to_string()))
        .expect("plain frequency should normalize");
    let parsed: serde_json::Value = serde_json::from_str(
        normalized
            .as_deref()
            .expect("normalized recurrence should be present"),
    )
    .expect("valid recurrence json");
    assert_eq!(parsed["FREQ"], "WEEKLY");
    assert_eq!(parsed["INTERVAL"], 1);
}

#[test]
fn normalize_calendar_recurrence_defaults_interval_for_object_payload() {
    let normalized = normalize_calendar_recurrence(Some(
        "{\"FREQ\":\"WEEKLY\",\"BYDAY\":[\"MO\",\"WE\"]}".to_string(),
    ))
    .expect("weekly object should normalize");
    let parsed: serde_json::Value = serde_json::from_str(
        normalized
            .as_deref()
            .expect("normalized recurrence should be present"),
    )
    .expect("valid recurrence json");
    assert_eq!(parsed["FREQ"], "WEEKLY");
    assert_eq!(parsed["INTERVAL"], 1);
    assert_eq!(parsed["BYDAY"], serde_json::json!(["MO", "WE"]));
}

#[test]
fn update_calendar_event_all_day_clears_persisted_times() {
    let conn = setup_sync_test_conn();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000901";
    let created_at = "2026-03-05T09:00:00Z";
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, description, recurrence, timezone, start_date, start_time,
            end_date, end_time, all_day, location, color, version, created_at, updated_at
         ) VALUES (?1, ?2, NULL, NULL, NULL, ?3, ?4, ?5, ?6, 0, NULL, NULL, ?7, ?8, ?8)",
        params![
            event_id,
            "Timed event",
            "2026-03-05",
            "09:00",
            "2026-03-05",
            "10:00",
            TEST_VERSION,
            created_at,
        ],
    )
    .expect("insert timed calendar event");

    let updated = update_calendar_event_internal(
        &conn,
        lorvex_workflow::calendar_event::CalendarEventUpdateInput {
            id: event_id.to_string(),
            title: None,
            recurrence: lorvex_domain::Patch::Unset,
            timezone: lorvex_domain::Patch::Unset,
            start_date: lorvex_domain::Patch::Unset,
            start_time: lorvex_domain::Patch::Unset,
            end_date: lorvex_domain::Patch::Unset,
            end_time: lorvex_domain::Patch::Unset,
            all_day: Some(true),
            description: lorvex_domain::Patch::Unset,
            location: lorvex_domain::Patch::Unset,
            url: lorvex_domain::Patch::Unset,
            color: lorvex_domain::Patch::Unset,
            event_type: lorvex_domain::Patch::Unset,
            person_name: lorvex_domain::Patch::Unset,
            attendees: lorvex_domain::Patch::Unset,
        },
        "2026-03-05T12:00:00Z",
    )
    .expect("mark event all-day");

    assert!(updated.all_day);
    assert_eq!(updated.start_time, None);
    assert_eq!(updated.end_time, None);

    let persisted = conn
        .query_row(
            "SELECT start_time, end_time, all_day FROM calendar_events WHERE id = ?1",
            params![event_id],
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .expect("load updated event");
    assert_eq!(persisted.0, None);
    assert_eq!(persisted.1, None);
    assert_eq!(persisted.2, 1);
}

fn seed_calendar_event_with_links(conn: &Connection, event_id: &str, task_ids: &[&str]) {
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, start_date, all_day, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, 1, ?4, ?5, ?5)",
        params![
            event_id,
            "Team sync",
            "2026-04-10",
            TEST_VERSION,
            "2026-04-01T08:00:00Z",
        ],
    )
    .expect("insert calendar event");
    for task_id in task_ids {
        // lift to canonical TaskBuilder.
        let title = format!("Task {task_id}");
        lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
            .title(&title)
            .version(TEST_VERSION)
            .created_at("2026-04-01T08:00:00Z")
            .insert(conn);
        conn.execute(
            "INSERT INTO task_calendar_event_links
                (task_id, calendar_event_id, created_at, updated_at, version)
             VALUES (?1, ?2, ?3, ?3, ?4)",
            params![task_id, event_id, "2026-04-01T08:00:00Z", TEST_VERSION],
        )
        .expect("insert task_calendar_event_link");
    }
}

#[test]
fn local_delete_calendar_event_emits_edge_tombstones() {
    // local Tauri delete_calendar_event must enqueue a
    // DELETE envelope and record a sync_tombstone for every live
    // task_calendar_event_link so peers converge instead of keeping
    // orphaned edge rows.
    let conn = setup_sync_test_conn();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000902";
    let task_ids = [
        "01966a3f-7c8b-7d4e-8f3a-000000000903",
        "01966a3f-7c8b-7d4e-8f3a-000000000904",
    ];
    seed_calendar_event_with_links(&conn, event_id, &task_ids);

    let outcome = delete_calendar_event_internal(&conn, event_id)
        .expect("delete_calendar_event_internal should succeed");
    let mut unlinked_sorted = outcome.unlinked_task_ids;
    unlinked_sorted.sort();
    assert_eq!(
        unlinked_sorted,
        task_ids
            .iter()
            .map(|task_id| task_id.to_string())
            .collect::<Vec<_>>()
    );

    // Calendar event row itself is gone (SQLite CASCADE covers the
    // task_calendar_event_links locally).
    let remaining_events: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
            params![event_id],
            |row| row.get(0),
        )
        .expect("count calendar event");
    assert_eq!(remaining_events, 0, "calendar_event row should be deleted");
    let remaining_links: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_calendar_event_links WHERE calendar_event_id = ?1",
            params![event_id],
            |row| row.get(0),
        )
        .expect("count links");
    assert_eq!(remaining_links, 0, "link rows should cascade");

    for task_id in &task_ids {
        let edge_entity_id = format!("{task_id}:{event_id}");

        // Outbox must carry a DELETE envelope for this edge so peers
        // learn about the cascade — without this the fix has not landed.
        let outbox_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = 'task_calendar_event_link'
                   AND entity_id = ?1
                   AND operation = 'delete'",
                params![edge_entity_id],
                |row| row.get(0),
            )
            .expect("count outbox entries");
        assert!(
            outbox_count >= 1,
            "expected DELETE envelope in sync_outbox for edge {edge_entity_id}",
        );
        let payload_raw: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox
                 WHERE entity_type = 'task_calendar_event_link'
                   AND entity_id = ?1
                   AND operation = 'delete'
                 ORDER BY id DESC LIMIT 1",
                params![edge_entity_id],
                |row| row.get(0),
            )
            .expect("load edge delete outbox payload");
        let payload: serde_json::Value =
            serde_json::from_str(&payload_raw).expect("edge delete payload is valid json");
        assert_eq!(payload["task_id"], serde_json::json!(task_id));
        assert_eq!(payload["calendar_event_id"], serde_json::json!(event_id));
        assert_eq!(
            payload["created_at"],
            serde_json::json!("2026-04-01T08:00:00Z"),
            "edge tombstone payload must preserve pre-delete created_at"
        );
        assert_eq!(
            payload["updated_at"],
            serde_json::json!("2026-04-01T08:00:00Z"),
            "edge tombstone payload must preserve pre-delete updated_at"
        );
        assert_eq!(
            payload["version"],
            serde_json::json!(TEST_VERSION),
            "edge tombstone payload must preserve the edge row version, not the delete envelope HLC"
        );

        // Tombstone must also be present locally so a late-arriving
        // edge upsert with a smaller HLC is rejected by the
        // tombstone-vs-upsert guard.
        let tombstone_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_tombstones
                 WHERE entity_type = 'task_calendar_event_link'
                   AND entity_id = ?1",
                params![edge_entity_id],
                |row| row.get(0),
            )
            .expect("count tombstones");
        assert_eq!(
            tombstone_count, 1,
            "expected tombstone row for edge {edge_entity_id}"
        );
    }

    // The calendar_event delete envelope itself must still be enqueued.
    let event_delete_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'calendar_event'
               AND entity_id = ?1
               AND operation = 'delete'",
            params![event_id],
            |row| row.get(0),
        )
        .expect("count event delete outbox entries");
    assert_eq!(event_delete_outbox_count, 1);
}

#[test]
fn local_delete_calendar_event_without_any_links_does_not_emit_edge_envelopes() {
    // Negative case: an event with no task links must still delete
    // cleanly and must NOT emit spurious edge DELETE envelopes or
    // tombstones.
    let conn = setup_sync_test_conn();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000905";
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, start_date, all_day, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, 1, ?4, ?5, ?5)",
        params![
            event_id,
            "Solo event",
            "2026-04-12",
            TEST_VERSION,
            "2026-04-01T08:00:00Z",
        ],
    )
    .expect("insert calendar event");

    let outcome = delete_calendar_event_internal(&conn, event_id)
        .expect("delete_calendar_event_internal should succeed");
    assert!(
        outcome.unlinked_task_ids.is_empty(),
        "no linked tasks means no unlinked ids"
    );

    let edge_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task_calendar_event_link'",
            [],
            |row| row.get(0),
        )
        .expect("count edge outbox entries");
    assert_eq!(
        edge_outbox_count, 0,
        "no edges existed, no edge envelopes should be emitted"
    );
    let edge_tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones
             WHERE entity_type = 'task_calendar_event_link'",
            [],
            |row| row.get(0),
        )
        .expect("count edge tombstones");
    assert_eq!(edge_tombstone_count, 0);

    let event_delete_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'calendar_event' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("count event delete outbox entries");
    assert_eq!(event_delete_outbox_count, 1);
}
