//! Tests for `commands::mutate::calendar::effects`, extracted from the parent module.

use super::*;
use crate::commands::shared::test_support::{eid, seed_task, tid};
use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_CALENDAR_EVENT,
};
use lorvex_domain::Patch;
use lorvex_runtime::read_local_change_seq;

/// Test helper that promotes raw `&str` fixture values to the
/// `Cow<'a, str>` shape `CalendarEventCreateFields` carries in
/// production, so the tests stay readable.
#[allow(clippy::too_many_arguments)]
fn fields(
    title: &'static str,
    start_date: &'static str,
    start_time: Option<&'static str>,
    end_date: Option<&'static str>,
    end_time: Option<&'static str>,
    all_day: bool,
    description: Option<&'static str>,
    location: Option<&'static str>,
    url: Option<&'static str>,
    color: Option<&'static str>,
    recurrence: Option<&'static str>,
    timezone: Option<&'static str>,
    event_type: Option<&'static str>,
    person_name: Option<&'static str>,
) -> CalendarEventCreateFields<'static> {
    CalendarEventCreateFields {
        title: Cow::Borrowed(title),
        start_date: Cow::Borrowed(start_date),
        start_time: start_time.map(Cow::Borrowed),
        end_date: end_date.map(Cow::Borrowed),
        end_time: end_time.map(Cow::Borrowed),
        all_day,
        description: description.map(Cow::Borrowed),
        location: location.map(Cow::Borrowed),
        url: url.map(Cow::Borrowed),
        color: color.map(Cow::Borrowed),
        recurrence: recurrence.map(Cow::Borrowed),
        timezone: timezone.map(Cow::Borrowed),
        event_type: event_type.map(Cow::Borrowed),
        person_name: person_name.map(Cow::Borrowed),
    }
}

#[test]
fn calendar_event_crud_with_conn_syncs_changelog_and_link_tombstones() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let created = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "Design review",
            "2026-04-30",
            Some("09:30"),
            None,
            Some("10:00"),
            false,
            Some("Discuss scope"),
            Some("Room 4"),
            None,
            Some("#4A90D9"),
            Some("WEEKLY"),
            Some("America/New_York"),
            Some("event"),
            None,
        ),
    )
    .expect("create calendar event");
    assert_eq!(created.title, "Design review");
    assert_eq!(
        created.start_time(),
        Some(lorvex_domain::TimeOfDay::parse("09:30").unwrap())
    );
    // The per-event EXDATE registry lives in
    // `calendar_event_recurrence_exceptions`; the read projection
    // rebuilds the JSON payload with `NULLIF(json_group_array(...), '[]')`,
    // so an event with no exceptions surfaces as `None` (not `"[]"`) —
    // the canonical "no exceptions" form shared with the Apple app.
    assert_eq!(created.recurrence_exceptions.as_deref(), None);

    let updated = update_calendar_event_with_conn(
        &mut conn,
        &eid(&created.id),
        &CalendarEventUpdateFields {
            title: Some("Updated review"),
            all_day: Some(true),
            location: Patch::Clear,
            ..CalendarEventUpdateFields::default()
        },
    )
    .expect("update calendar event");
    assert_eq!(updated.title, "Updated review");
    assert!(updated.all_day());
    assert_eq!(updated.start_time(), None);
    assert_eq!(updated.end_time(), None);
    assert_eq!(updated.location, None);

    const LINKED_TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-00000000ca11";
    seed_task(&conn, LINKED_TASK_ID, "Linked task", "open");
    conn.execute(
        "INSERT INTO task_calendar_event_links
         (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-04-30T00:00:00Z', '2026-04-30T00:00:00Z')",
        rusqlite::params![LINKED_TASK_ID, &created.id],
    )
    .expect("seed calendar link");

    let deleted = delete_calendar_event_with_conn(&mut conn, &eid(&created.id))
        .expect("delete calendar event");
    assert_eq!(deleted.id, created.id);
    assert_eq!(deleted.unlinked_task_ids, vec![LINKED_TASK_ID.to_string()]);

    let event_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
            [&created.id],
            |row| row.get(0),
        )
        .expect("count calendar events");
    assert_eq!(event_count, 0);

    let event_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            rusqlite::params![ENTITY_CALENDAR_EVENT, created.id],
            |row| row.get(0),
        )
        .expect("count calendar event outbox");
    assert_eq!(event_outbox, 1);

    let edge_delete_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
            rusqlite::params![
                EDGE_TASK_CALENDAR_EVENT_LINK,
                format!("{LINKED_TASK_ID}:{}", deleted.id)
            ],
            |row| row.get(0),
        )
        .expect("count link delete outbox");
    assert_eq!(edge_delete_outbox, 1);

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
            [ENTITY_CALENDAR_EVENT],
            |row| row.get(0),
        )
        .expect("count calendar changelog rows");
    assert_eq!(changelog_count, 3);
}

#[test]
fn batch_create_calendar_events_with_conn_is_atomic_and_syncs() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let inputs = vec![
        CalendarEventCreateInput {
            title: "Planning block".to_string(),
            start_date: "2026-05-01".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("10:00".to_string()),
            all_day: false,
            description: None,
            location: Some("Room 1".to_string()),
            url: None,
            color: Some("#4A90D9".to_string()),
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            event_type: Some("event".to_string()),
            person_name: None,
        },
        CalendarEventCreateInput {
            title: "Monthly close".to_string(),
            start_date: "2026-05-10".to_string(),
            start_time: None,
            end_date: None,
            end_time: None,
            all_day: true,
            description: None,
            location: None,
            url: None,
            color: None,
            recurrence: Some("MONTHLY".to_string()),
            timezone: None,
            event_type: None,
            person_name: None,
        },
    ];

    let result = create_calendar_events_with_conn(&mut conn, &inputs).expect("batch create events");
    assert_eq!(result.created_count, 2);
    assert_eq!(result.calendar_events.len(), 2);
    assert_eq!(result.calendar_events[0].title, "Planning block");
    assert_eq!(
        result.calendar_events[1].recurrence_exceptions.as_deref(),
        None
    );

    let event_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count calendar events");
    assert_eq!(event_count, 2);
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [ENTITY_CALENDAR_EVENT],
            |row| row.get(0),
        )
        .expect("count calendar event outbox rows");
    assert_eq!(outbox_count, 2);
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND operation = 'batch_create'",
            [ENTITY_CALENDAR_EVENT],
            |row| row.get(0),
        )
        .expect("count batch-create changelog rows");
    assert_eq!(changelog_count, 2);

    let invalid_inputs = vec![
        CalendarEventCreateInput {
            title: "Would be valid".to_string(),
            start_date: "2026-05-12".to_string(),
            start_time: None,
            end_date: None,
            end_time: None,
            all_day: true,
            description: None,
            location: None,
            url: None,
            color: None,
            recurrence: None,
            timezone: None,
            event_type: None,
            person_name: None,
        },
        CalendarEventCreateInput {
            title: "Invalid date".to_string(),
            start_date: "not-a-date".to_string(),
            start_time: None,
            end_date: None,
            end_time: None,
            all_day: true,
            description: None,
            location: None,
            url: None,
            color: None,
            recurrence: None,
            timezone: None,
            event_type: None,
            person_name: None,
        },
    ];
    create_calendar_events_with_conn(&mut conn, &invalid_inputs)
        .expect_err("invalid batch should fail before inserting");
    let event_count_after_error: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count calendar events after invalid batch");
    assert_eq!(event_count_after_error, 2);
}

#[test]
fn update_calendar_event_with_conn_rejects_end_time_without_start_time() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let created = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "All day",
            "2026-05-01",
            None,
            None,
            None,
            true,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        ),
    )
    .expect("create all-day event");

    let error = update_calendar_event_with_conn(
        &mut conn,
        &eid(&created.id),
        &CalendarEventUpdateFields {
            all_day: Some(false),
            end_time: Patch::Set("11:00"),
            ..CalendarEventUpdateFields::default()
        },
    )
    .expect_err("end time without start time should fail");
    assert!(
        error.to_string().contains("Pick a start time"),
        "a timed event with an end time but no start time must be rejected with the \
         actionable start-time message, got: {error}"
    );
}

#[test]
fn update_calendar_event_with_conn_reanchors_monthly_recurrence_on_start_date_change() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let created = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "Monthly close",
            "2026-05-10",
            None,
            None,
            None,
            true,
            None,
            None,
            None,
            None,
            Some("MONTHLY"),
            None,
            None,
            None,
        ),
    )
    .expect("create monthly event");
    let created_rule: serde_json::Value =
        serde_json::from_str(created.recurrence.as_deref().expect("recurrence"))
            .expect("created recurrence json");
    assert_eq!(created_rule["BYMONTHDAY"], serde_json::json!([10]));

    let updated = update_calendar_event_with_conn(
        &mut conn,
        &eid(&created.id),
        &CalendarEventUpdateFields {
            start_date: Some("2026-05-22"),
            ..CalendarEventUpdateFields::default()
        },
    )
    .expect("update start date");
    let updated_rule: serde_json::Value =
        serde_json::from_str(updated.recurrence.as_deref().expect("recurrence"))
            .expect("updated recurrence json");
    assert_eq!(updated_rule["BYMONTHDAY"], serde_json::json!([22]));
    assert_eq!(updated.recurrence_exceptions.as_deref(), None);
}

#[test]
fn update_calendar_event_with_conn_preserves_positional_monthly_recurrence() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let created = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "First Monday planning",
            "2026-01-05",
            Some("09:00"),
            None,
            Some("10:00"),
            false,
            None,
            None,
            None,
            None,
            Some(r#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1]}"#),
            None,
            None,
            None,
        ),
    )
    .expect("create positional monthly event");
    let created_rule: serde_json::Value =
        serde_json::from_str(created.recurrence.as_deref().expect("recurrence"))
            .expect("created recurrence json");
    assert_eq!(created_rule["BYDAY"], serde_json::json!(["MO"]));
    assert_eq!(created_rule["BYSETPOS"], serde_json::json!([1]));
    assert!(created_rule.get("BYMONTHDAY").is_none());

    let updated = update_calendar_event_with_conn(
        &mut conn,
        &eid(&created.id),
        &CalendarEventUpdateFields {
            start_date: Some("2026-01-12"),
            ..CalendarEventUpdateFields::default()
        },
    )
    .expect("update start date");
    let updated_rule: serde_json::Value =
        serde_json::from_str(updated.recurrence.as_deref().expect("recurrence"))
            .expect("updated recurrence json");
    assert_eq!(updated_rule["BYDAY"], serde_json::json!(["MO"]));
    assert_eq!(updated_rule["BYSETPOS"], serde_json::json!([1]));
    assert!(updated_rule.get("BYMONTHDAY").is_none());
}

#[test]
fn calendar_link_and_exception_helpers_sync_edges_and_events() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    const TASK_CAL_A: &str = "01966a3f-7c8b-7d4e-8f3a-00000000ca12";
    const TASK_CAL_B: &str = "01966a3f-7c8b-7d4e-8f3a-00000000ca13";
    seed_task(&conn, TASK_CAL_A, "Linked task A", "open");
    seed_task(&conn, TASK_CAL_B, "Linked task B", "open");
    let created = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "Daily review",
            "2026-05-01",
            None,
            None,
            None,
            true,
            None,
            None,
            None,
            None,
            Some("DAILY"),
            None,
            None,
            None,
        ),
    )
    .expect("create daily event");

    let linked = link_tasks_to_calendar_event_with_conn(
        &mut conn,
        &eid(&created.id),
        &[TASK_CAL_A.to_string(), TASK_CAL_B.to_string()],
    )
    .expect("link tasks");
    assert_eq!(linked.linked_count, 2);
    assert_eq!(
        get_calendar_links_for_event_with_conn(&conn, &eid(&created.id))
            .expect("links for event")
            .len(),
        2
    );
    assert_eq!(
        get_calendar_links_for_task_with_conn(&conn, &tid(TASK_CAL_A))
            .expect("links for task")
            .len(),
        1
    );
    let edge_upserts_before_unlink: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = 'upsert'",
            [EDGE_TASK_CALENDAR_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count link upsert outbox before unlink");
    assert_eq!(edge_upserts_before_unlink, 2);

    let with_exception =
        add_calendar_event_exception_with_conn(&mut conn, &eid(&created.id), "2026-05-02")
            .expect("add event exception");
    assert_eq!(
        with_exception.recurrence_exceptions.as_deref(),
        Some(r#"["2026-05-02"]"#)
    );
    let without_exception =
        remove_calendar_event_exception_with_conn(&mut conn, &eid(&created.id), "2026-05-02")
            .expect("remove event exception");
    assert_eq!(without_exception.recurrence_exceptions.as_deref(), None);

    let unlinked =
        unlink_task_from_calendar_event_with_conn(&mut conn, &eid(&created.id), &tid(TASK_CAL_A))
            .expect("unlink task");
    assert!(unlinked.deleted);
    assert!(unlinked.remaining_links.is_empty());

    let edge_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = 'upsert'",
            [EDGE_TASK_CALENDAR_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count link upsert outbox");
    assert_eq!(edge_upserts, 1);

    let edge_deletes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = 'delete'",
            [EDGE_TASK_CALENDAR_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count link delete outbox");
    assert_eq!(edge_deletes, 1);

    let edge_changelog: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
            [EDGE_TASK_CALENDAR_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count edge changelog");
    assert_eq!(edge_changelog, 3);
}

#[test]
fn provider_calendar_link_helpers_are_local_only_and_logged() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-provider-a", "Provider linked task", "open");

    let start_seq = read_local_change_seq(&conn).expect("read local seq before link");
    let link = link_task_to_provider_event_with_conn(
        &mut conn,
        &tid("task-provider-a"),
        "eventkit",
        "",
        "ek-event-1",
    )
    .expect("link provider event");
    assert_eq!(link.task_id, "task-provider-a");
    assert_eq!(link.provider_kind, "eventkit");
    assert_eq!(link.provider_scope, "");
    assert_eq!(link.provider_event_key, "ek-event-1");

    let resolved = get_provider_event_links_for_task_with_conn(&conn, &tid("task-provider-a"))
        .expect("get provider links");
    assert_eq!(resolved.len(), 1);
    assert_eq!(resolved[0].resolution_state, "unavailable");

    let provider_edge_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [EDGE_TASK_PROVIDER_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count provider edge outbox");
    assert_eq!(provider_edge_outbox, 0);

    let unlink = unlink_task_from_provider_event_with_conn(
        &mut conn,
        &tid("task-provider-a"),
        "eventkit",
        "",
        "ek-event-1",
    )
    .expect("unlink provider event");
    assert!(unlink.remaining_links.is_empty());

    let remaining = get_provider_event_links_for_task_with_conn(&conn, &tid("task-provider-a"))
        .expect("get remaining provider links");
    assert!(remaining.is_empty());

    let provider_changelog: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
            [EDGE_TASK_PROVIDER_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count provider link changelog");
    assert_eq!(provider_changelog, 2);
    assert!(
        read_local_change_seq(&conn).expect("read local seq after unlink") > start_seq,
        "provider link writes should bump local change seq for changelog visibility"
    );
}

/// `provider_event_key`, `provider_kind`, and
/// `provider_scope` are stored verbatim in `task_provider_event_links`,
/// so each must be NFC-normalized + bidi/ZWSP/control-stripped at the
/// CLI trust boundary before the row is inserted. Build inputs that
/// embed the standard hazards and assert the persisted row carries
/// the sanitized form.
#[test]
fn provider_event_link_sanitizes_kind_scope_and_event_key() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-provider-sanitize", "Sanitize provider", "open");

    // U+202E RTLO + U+200B ZWSP + U+0000 NUL embedded in each field.
    let raw_kind = "event\u{200B}kit\u{202E}";
    let raw_scope = "personal\u{0000}";
    let raw_key = "ek-event-\u{202E}1\u{200B}";

    let link = link_task_to_provider_event_with_conn(
        &mut conn,
        &tid("task-provider-sanitize"),
        raw_kind,
        raw_scope,
        raw_key,
    )
    .expect("link provider event with sanitization hazards");

    // The DB row must carry the sanitized form.
    let stored: (String, String, String) = conn
        .query_row(
            "SELECT provider_kind, provider_scope, provider_event_key
             FROM task_provider_event_links
             WHERE task_id = 'task-provider-sanitize'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load provider link row");
    for value in [&stored.0, &stored.1, &stored.2] {
        assert!(
            !value.contains('\u{202E}'),
            "stored {value:?} retained U+202E"
        );
        assert!(
            !value.contains('\u{200B}'),
            "stored {value:?} retained U+200B"
        );
        assert!(
            !value.contains('\u{0000}'),
            "stored {value:?} retained U+0000"
        );
    }
    // The benign payload survives.
    assert!(stored.0.contains("eventkit"));
    assert!(stored.1.contains("personal"));
    assert!(stored.2.contains("ek-event-"));

    // The returned link mirrors the persisted row.
    assert_eq!(link.provider_kind, stored.0);
    assert_eq!(link.provider_scope, stored.1);
    assert_eq!(link.provider_event_key, stored.2);
}

#[test]
fn provider_event_link_rejects_overlong_scope_before_changelog_or_seq_bump() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "task-provider-overlong-scope",
        "Overlong scope",
        "open",
    );
    let start_seq = read_local_change_seq(&conn).expect("read local seq before link");
    let too_long = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN + 1);

    let err = link_task_to_provider_event_with_conn(
        &mut conn,
        &tid("task-provider-overlong-scope"),
        "eventkit",
        &too_long,
        "ek-event-1",
    )
    .expect_err("overlong provider scope should reject");

    assert!(
        err.to_string().contains("provider_scope"),
        "expected provider_scope validation error, got: {err}"
    );
    let changelog_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
            [EDGE_TASK_PROVIDER_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count provider changelog rows");
    assert_eq!(changelog_rows, 0);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after failed link"),
        start_seq
    );
}

#[test]
fn provider_event_unlink_rejects_missing_link_without_changelog_or_seq_bump() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "task-provider-missing-link",
        "Missing provider link",
        "open",
    );
    let start_seq = read_local_change_seq(&conn).expect("read local seq before unlink");

    let err = unlink_task_from_provider_event_with_conn(
        &mut conn,
        &tid("task-provider-missing-link"),
        "eventkit",
        "default",
        "missing-event",
    )
    .expect_err("missing provider link should reject");

    assert!(
        err.to_string().contains("missing-event"),
        "expected missing-link diagnostic, got: {err}"
    );
    let changelog_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1",
            [EDGE_TASK_PROVIDER_EVENT_LINK],
            |row| row.get(0),
        )
        .expect("count provider changelog rows");
    assert_eq!(changelog_rows, 0);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after failed unlink"),
        start_seq
    );
}

#[test]
fn calendar_ics_export_helper_emits_canonical_calendar_events() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let event = create_calendar_event_with_conn(
        &mut conn,
        &fields(
            "Planning Review",
            "2026-05-12",
            Some("09:30"),
            None,
            Some("10:00"),
            false,
            Some("Review roadmap"),
            Some("Room 4"),
            None,
            None,
            None,
            Some("America/New_York"),
            None,
            None,
        ),
    )
    .expect("create calendar event");

    let ics = export_calendar_ics_with_conn(&conn, "2026-05-01", "2026-05-31")
        .expect("export calendar ics");

    assert!(ics.starts_with("BEGIN:VCALENDAR"));
    assert!(ics.contains(&format!("UID:{}@lorvex", event.id)));
    assert!(ics.contains("SUMMARY:Planning Review"));
    assert!(ics.contains("LOCATION:Room 4"));
}
