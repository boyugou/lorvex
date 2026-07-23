use super::support::*;

// ===========================================================================
// 22. calendar_event: tombstone, LWW, malformed enum, attendee shadow
//     round-trip (issue #2856)
// ===========================================================================

fn calendar_event_payload_minimal() -> serde_json::Value {
    serde_json::json!({
        "title": "Standup",
        "start_date": "2026-04-20",
        "all_day": false,
        "event_type": "event",
        "created_at": "2026-04-20T09:00:00.000Z",
        "updated_at": "2026-04-20T09:00:00.000Z",
    })
}

#[test]
fn calendar_event_tombstone_blocks_lower_version_upsert() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-00000000310a",
        V2,
        "2026-04-21T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let payload = calendar_event_payload_minimal().to_string();
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-00000000310a",
        V1,
        &payload,
    );
    let r = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(r, ApplyResult::Skipped { .. }));

    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-00000000310a'"
        ),
        0
    );
    assert!(get_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-00000000310a"
    )
    .unwrap()
    .is_some());
}

#[test]
fn calendar_event_lww_older_upsert_after_newer_is_skipped() {
    let conn = test_db();

    let mut newer = calendar_event_payload_minimal();
    newer["title"] = serde_json::Value::String("New title".into());
    apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_EVENT,
            "01966a3f-7c8b-7d4e-8f3a-000000003108",
            V3,
            &newer.to_string(),
        ),
    )
    .unwrap();

    let mut older = calendar_event_payload_minimal();
    older["title"] = serde_json::Value::String("Old title".into());
    let r = apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_EVENT,
            "01966a3f-7c8b-7d4e-8f3a-000000003108",
            V1,
            &older.to_string(),
        ),
    )
    .unwrap();
    assert!(matches!(r, ApplyResult::Skipped { .. }));

    let title: String = conn
        .query_row(
            "SELECT title FROM calendar_events WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003108'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title, "New title");
}

/// Schema CHECK at `001_schema.sql:187` constrains `event_type` to a
/// closed set. Apply must reject malformed values at the trust
/// boundary so the CHECK never aborts the apply batch.
#[test]
fn calendar_event_rejects_malformed_event_type_enum() {
    let conn = test_db();

    let mut payload = calendar_event_payload_minimal();
    payload["event_type"] = serde_json::Value::String("meeting".into());
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003106",
        V2,
        &payload.to_string(),
    );

    let err = apply_envelope(&conn, &env)
        .expect_err("calendar_event malformed `event_type` must reject at the boundary");
    let msg = err.to_string();
    assert!(
        msg.contains("event_type") || msg.to_lowercase().contains("calendar_event"),
        "error must mention event_type / calendar_event, got: {msg}"
    );
    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003106'"
        ),
        0
    );
}

/// Schema CHECK at `001_schema.sql:188` enforces all_day↔time mutual
/// exclusion. Apply must reject the violating shape with a clean
/// InvalidPayload.
#[test]
fn calendar_event_rejects_all_day_with_start_time() {
    let conn = test_db();

    let payload = serde_json::json!({
        "title": "All-day with start_time (illegal)",
        "start_date": "2026-04-20",
        "start_time": "09:00",
        "all_day": true,
        "event_type": "event",
        "created_at": "2026-04-20T09:00:00.000Z",
        "updated_at": "2026-04-20T09:00:00.000Z",
    })
    .to_string();
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003105",
        V2,
        &payload,
    );

    let err = apply_envelope(&conn, &env)
        .expect_err("all_day=true with start_time must reject at the boundary");
    assert!(err.to_string().to_lowercase().contains("all_day"));
    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003105'"
        ),
        0
    );
}

#[test]
fn calendar_event_persists_override_linkage_fields() {
    let conn = test_db();

    let mut payload = calendar_event_payload_minimal();
    payload["series_id"] = serde_json::Value::String("01966a3f-7c8b-7d4e-8f3a-000000003120".into());
    payload["recurrence_instance_date"] = serde_json::Value::String("2026-04-20".into());
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003121",
        V2,
        &payload.to_string(),
    );

    let r = apply_envelope(&conn, &env).unwrap();
    assert_eq!(r, ApplyResult::Applied);
    let (series_id, recurrence_instance_date): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT series_id, recurrence_instance_date
               FROM calendar_events
              WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003121'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(
        series_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-000000003120")
    );
    assert_eq!(recurrence_instance_date.as_deref(), Some("2026-04-20"));
}

#[test]
fn calendar_event_rejects_half_set_override_linkage() {
    let conn = test_db();

    let mut payload = calendar_event_payload_minimal();
    payload["series_id"] = serde_json::Value::String("01966a3f-7c8b-7d4e-8f3a-000000003122".into());
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003123",
        V2,
        &payload.to_string(),
    );

    let err = apply_envelope(&conn, &env)
        .expect_err("half-set calendar override linkage must reject before SQL");
    assert!(
        err.to_string().contains("series_id")
            && err.to_string().contains("recurrence_instance_date")
    );
    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003123'"
        ),
        0
    );
}

#[test]
fn calendar_event_override_collision_merges_to_min_id_with_redirect() {
    let conn = test_db();
    let series_id = "01966a3f-7c8b-7d4e-8f3a-000000003124";
    let occurrence_date = "2026-04-25";
    let loser_id = "01966a3f-7c8b-7d4e-8f3a-000000003126";
    let winner_id = "01966a3f-7c8b-7d4e-8f3a-000000003125";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000003127";
    seed_task(&conn, task_id);

    let mut first = calendar_event_payload_minimal();
    first["title"] = serde_json::Value::String("Existing override".into());
    first["series_id"] = serde_json::Value::String(series_id.into());
    first["recurrence_instance_date"] = serde_json::Value::String(occurrence_date.into());
    apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_EVENT,
            loser_id,
            V1,
            &first.to_string(),
        ),
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_calendar_event_links
             (task_id, calendar_event_id, created_at, updated_at, version)
         VALUES (?1, ?2, '2026-04-25T00:00:00.000Z',
                 '2026-04-25T00:00:00.000Z', ?3)",
        params![task_id, loser_id, V1],
    )
    .unwrap();

    let mut second = calendar_event_payload_minimal();
    second["title"] = serde_json::Value::String("Incoming override wins by id".into());
    second["series_id"] = serde_json::Value::String(series_id.into());
    second["recurrence_instance_date"] = serde_json::Value::String(occurrence_date.into());
    let r = apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_EVENT,
            winner_id,
            V2,
            &second.to_string(),
        ),
    )
    .unwrap();
    assert_eq!(r, ApplyResult::Applied);

    assert_eq!(
        count_rows(&conn, "calendar_events", &format!("id = '{loser_id}'")),
        0
    );
    let (stored_series, stored_occurrence, title): (Option<String>, Option<String>, String) = conn
        .query_row(
            "SELECT series_id, recurrence_instance_date, title
               FROM calendar_events
              WHERE id = ?1",
            params![winner_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(stored_series.as_deref(), Some(series_id));
    assert_eq!(stored_occurrence.as_deref(), Some(occurrence_date));
    assert_eq!(title, "Incoming override wins by id");

    let linked_event_id: String = conn
        .query_row(
            "SELECT calendar_event_id FROM task_calendar_event_links WHERE task_id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(linked_event_id, winner_id);

    let tombstone = get_tombstone(&conn, naming::ENTITY_CALENDAR_EVENT, loser_id)
        .unwrap()
        .expect("loser override must be tombstoned with redirect");
    assert_eq!(tombstone.redirect_entity_id.as_deref(), Some(winner_id));
    assert_eq!(
        count_rows(
            &conn,
            "sync_conflict_log",
            &format!(
                "entity_type = '{}' AND entity_id = '{}' AND resolution_type = '{}'",
                naming::ENTITY_CALENDAR_EVENT,
                winner_id,
                naming::RESOLUTION_RECURRENCE_DEDUP
            )
        ),
        1
    );
}

/// a calendar_event envelope carrying surplus
/// per-attendee fields lands the known fields in the primary table
/// AND the surplus fields in the attendee shadow, and
/// `load_attendees_with_extras` reassembles them on the next
/// outbound enqueue — verifying the round-trip end-to-end through
/// the apply pipeline (not just the unit-level helper).
#[test]
fn calendar_event_attendee_shadow_round_trip_through_apply_envelope() {
    let conn = test_db();

    let payload = serde_json::json!({
        "title": "Roundtrip standup",
        "start_date": "2026-04-22",
        "all_day": false,
        "event_type": "event",
        "created_at": "2026-04-22T09:00:00.000Z",
        "updated_at": "2026-04-22T09:00:00.000Z",
        "attendees": [
            {
                "email": "Alice@Example.com",
                "name": "Alice",
                "status": "accepted",
                "role": "chair",
                "rsvp_deadline": "2026-04-21T17:00:00Z",
            }
        ],
    })
    .to_string();
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003109",
        V2,
        &payload,
    );
    let r = apply_envelope(&conn, &env).unwrap();
    assert_eq!(r, ApplyResult::Applied);

    // email is normalized to lowercase by the apply path.
    let primary_email: String = conn
        .query_row(
            "SELECT email FROM calendar_event_attendees WHERE event_id = '01966a3f-7c8b-7d4e-8f3a-000000003109'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(primary_email, "alice@example.com");

    // Surplus keys landed in the shadow row.
    let shadow_json: String = conn
        .query_row(
            "SELECT extra_fields_json
             FROM calendar_event_attendee_shadow
             WHERE event_id = '01966a3f-7c8b-7d4e-8f3a-000000003109' AND attendee_id = 'email:alice@example.com'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    let shadow: serde_json::Value = serde_json::from_str(&shadow_json).unwrap();
    assert_eq!(shadow.get("role").and_then(|v| v.as_str()), Some("chair"));
    assert_eq!(
        shadow.get("rsvp_deadline").and_then(|v| v.as_str()),
        Some("2026-04-21T17:00:00Z")
    );

    // Re-echo path: `load_attendees_with_extras` reassembles the
    // surplus alongside the canonical fields.
    let typed_event_id =
        lorvex_domain::EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000003109".to_string());
    let merged =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(&conn, &typed_event_id)
            .unwrap();
    assert_eq!(merged.len(), 1);
    let att = merged[0].as_object().unwrap();
    assert_eq!(
        att.get("email").and_then(|v| v.as_str()),
        Some("alice@example.com")
    );
    assert_eq!(att.get("role").and_then(|v| v.as_str()), Some("chair"));

    // Removing the attendee in a later envelope purges the shadow row.
    let payload_v2 = serde_json::json!({
        "title": "Roundtrip standup",
        "start_date": "2026-04-22",
        "all_day": false,
        "event_type": "event",
        "created_at": "2026-04-22T09:00:00.000Z",
        "updated_at": "2026-04-22T10:00:00.000Z",
        "attendees": [],
    })
    .to_string();
    let env_v2 = upsert_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003109",
        V3,
        &payload_v2,
    );
    apply_envelope(&conn, &env_v2).unwrap();
    assert_eq!(
        count_rows(
            &conn,
            "calendar_event_attendee_shadow",
            "event_id = '01966a3f-7c8b-7d4e-8f3a-000000003109'"
        ),
        0,
        "shadow rows for removed attendees must be purged"
    );
}

/// Aggregate delete of a calendar_event must succeed under LWW and
/// remove the row.
#[test]
fn calendar_event_delete_removes_row_under_lww() {
    let conn = test_db();

    apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_EVENT,
            "01966a3f-7c8b-7d4e-8f3a-000000003107",
            V1,
            &calendar_event_payload_minimal().to_string(),
        ),
    )
    .unwrap();
    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003107'"
        ),
        1
    );

    let env_delete = delete_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000003107",
        V3,
    );
    let r = apply_envelope(&conn, &env_delete).unwrap();
    assert_eq!(r, ApplyResult::Applied);
    assert_eq!(
        count_rows(
            &conn,
            "calendar_events",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003107'"
        ),
        0
    );
}

// ===========================================================================
// 23. calendar_subscription: tombstone, LWW, URL-scheme rejection,
//     delete (issue #2856)
// ===========================================================================

fn calendar_subscription_payload(name: &str, url: &str, updated_at: &str) -> String {
    serde_json::json!({
        "name": name,
        "url": url,
        "color": "#00aabb",
        "enabled": true,
        "created_at": "2026-04-01T09:00:00.000Z",
        "updated_at": updated_at,
    })
    .to_string()
}

#[test]
fn calendar_subscription_tombstone_blocks_lower_version_upsert() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000003116",
        V2,
        "2026-04-02T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let payload = calendar_subscription_payload(
        "Team",
        "https://example.com/team.ics",
        "2026-04-01T09:00:00.000Z",
    );
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000003116",
        V1,
        &payload,
    );
    let r = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(r, ApplyResult::Skipped { .. }));

    assert_eq!(
        count_rows(
            &conn,
            "calendar_subscriptions",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003116'"
        ),
        0
    );
    assert!(get_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000003116"
    )
    .unwrap()
    .is_some());
}

#[test]
fn calendar_subscription_lww_older_upsert_after_newer_is_skipped() {
    let conn = test_db();

    let newer = calendar_subscription_payload(
        "Renamed",
        "https://example.com/v2.ics",
        "2026-04-02T00:00:00.000Z",
    );
    apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_SUBSCRIPTION,
            "01966a3f-7c8b-7d4e-8f3a-000000003115",
            V3,
            &newer,
        ),
    )
    .unwrap();

    let older = calendar_subscription_payload(
        "Original",
        "https://example.com/v1.ics",
        "2026-04-01T00:00:00.000Z",
    );
    let r = apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_SUBSCRIPTION,
            "01966a3f-7c8b-7d4e-8f3a-000000003115",
            V1,
            &older,
        ),
    )
    .unwrap();
    assert!(matches!(r, ApplyResult::Skipped { .. }));

    let (name, url): (String, String) = conn
        .query_row(
            "SELECT name, url FROM calendar_subscriptions WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003115'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(name, "Renamed");
    assert_eq!(url, "https://example.com/v2.ics");
}

/// only http/https/webcal schemes are valid.
/// `javascript:`, `data:`, `file:` MUST reject at the apply boundary
/// so a peer with a forked builder cannot land an exploit URL into
/// the live row.
#[test]
fn calendar_subscription_rejects_javascript_url_scheme() {
    let conn = test_db();

    let payload = calendar_subscription_payload(
        "Malicious",
        "javascript:alert(1)",
        "2026-04-02T00:00:00.000Z",
    );
    let env = upsert_envelope(
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000003113",
        V2,
        &payload,
    );

    let err = apply_envelope(&conn, &env)
        .expect_err("calendar_subscription with javascript: URL must reject");
    assert!(
        err.to_string().to_lowercase().contains("url"),
        "error must mention URL, got: {err}"
    );
    assert_eq!(
        count_rows(
            &conn,
            "calendar_subscriptions",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003113'"
        ),
        0
    );
}

/// Aggregate delete must succeed under LWW.
#[test]
fn calendar_subscription_delete_removes_row_under_lww() {
    let conn = test_db();

    let payload = calendar_subscription_payload(
        "Delete me",
        "https://example.com/del.ics",
        "2026-04-01T09:00:00.000Z",
    );
    apply_envelope(
        &conn,
        &upsert_envelope(
            naming::ENTITY_CALENDAR_SUBSCRIPTION,
            "01966a3f-7c8b-7d4e-8f3a-000000003114",
            V1,
            &payload,
        ),
    )
    .unwrap();
    assert_eq!(
        count_rows(
            &conn,
            "calendar_subscriptions",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003114'"
        ),
        1
    );

    let env_delete = delete_envelope(
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000003114",
        V3,
    );
    let r = apply_envelope(&conn, &env_delete).unwrap();
    assert_eq!(r, ApplyResult::Applied);
    assert_eq!(
        count_rows(
            &conn,
            "calendar_subscriptions",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003114'"
        ),
        0
    );
}
