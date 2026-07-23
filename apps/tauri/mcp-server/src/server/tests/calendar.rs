use super::*;
use lorvex_domain::Patch;
use lorvex_sync_payload::CalendarEventUpdateWire;

/// Test helper: build an [`UpdateCalendarEventArgs`] from a single
/// pre-filled [`CalendarEventUpdateWire`] with the MCP-only fields
/// defaulted (no idempotency key, not a dry-run, no diff in response).
fn wire_args(wire: CalendarEventUpdateWire) -> UpdateCalendarEventArgs {
    UpdateCalendarEventArgs {
        wire,
        idempotency_key: None,
        dry_run: false,
        include_diff: false,
    }
}

// Old JSONL import validation tests for calendar events removed — import now
// delegates to lorvex_store::import_from_zip which has its own test suite.

// ── #3033-H1: contract sentinel for dry_run dispatch coverage ────────────
//
// The regression class is "the contract claims dry_run is honored,
// but the router silently drops it" — a calendar mutation surface
// reading `args.dry_run` while routing through `with_conn_typed`
// would commit the mutation even when the assistant requested a
// preview. This sentinel pins the contract: every calendar mutation
// surface that exposes `dry_run: bool` in its args struct MUST route
// the corresponding tool handler through `dispatch_dry_run`. It is a
// source-text assertion against
// `mcp-server/src/calendar/router.rs` so a future drift
// (rename, refactor, accidental `with_conn_typed` paste) trips it
// long before a real preview commit lands in production.

const CALENDAR_ROUTER_SRC: &str = include_str!("../../calendar/router.rs");

/// Calendar tools that MUST route through `dispatch_dry_run` because
/// their args struct exposes a `dry_run: bool` field. Update both
/// places (this list and the contract) when adding a new dry-run-
/// capable surface — the test will catch one without the other.
const DRY_RUN_CALENDAR_TOOLS: &[&str] = &[
    "batch_create_calendar_events",
    "delete_calendar_event",
    "delete_scoped_calendar_event",
    "edit_scoped_calendar_event",
    "update_calendar_event",
    "add_event_exception",
    "link_task_to_event",
    "unlink_task_from_event",
];

#[test]
#[serial_test::serial(hlc)]
fn calendar_dry_run_surfaces_route_through_dispatch_dry_run() {
    for tool in DRY_RUN_CALENDAR_TOOLS {
        // Locate the `pub(crate) fn <tool>(` definition in the router
        // and slice from there to the next blank line that starts a
        // sibling tool — that's the body of this handler.
        let needle = format!("pub(crate) fn {tool}(");
        let start = CALENDAR_ROUTER_SRC
            .find(&needle)
            .unwrap_or_else(|| panic!("router missing tool fn: {tool}"));
        // Find the closing `}` of the function body. We look for the
        // first `\n    }\n` after the start which is the rust-fmt'd
        // close of an `impl` method at 4-space indent.
        let body_end = CALENDAR_ROUTER_SRC[start..]
            .find("\n    }\n")
            .unwrap_or_else(|| panic!("router fn {tool} has no close brace"));
        let body = &CALENDAR_ROUTER_SRC[start..start + body_end];

        assert!(
            body.contains("dispatch_dry_run"),
            "#3033-H1 sentinel: tool `{tool}` exposes `dry_run` in its args \
             struct but the router does not route it through \
             `dispatch_dry_run`. The preview flag is silently consumed; \
             the writer commits the mutation even when the assistant \
             requested a preview. Body inspected:\n{body}",
        );
        assert!(
            !body.contains("self.with_conn_typed("),
            "#3033-H1 sentinel: tool `{tool}` mixes `dispatch_dry_run` and \
             `with_conn_typed` in the same handler — exactly the drift \
             this contract is here to catch. Body:\n{body}",
        );
    }
}

fn create_recurring_event(server: &LorvexMcpServer, start_date: &str, recurrence: &str) -> String {
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Recurring Event".to_string(),
            recurrence: Some(recurrence.to_string()),
            timezone: None,
            start_date: start_date.to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("10:00".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create recurring calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");
    event["id"].as_str().expect("event id").to_string()
}

#[test]
#[serial_test::serial(hlc)]
fn add_event_exception_accepts_valid_daily_occurrence() {
    let server = make_server();
    let event_id = create_recurring_event(&server, "2026-03-10", "DAILY");

    let result = server.add_event_exception(Parameters(AddEventExceptionArgs {
        event_id,
        date: "2026-03-12".to_string(), // day 3 of a daily starting March 10 — valid
        idempotency_key: None,
        dry_run: false,
    }));
    assert!(
        result.is_ok(),
        "valid occurrence should be accepted: {result:?}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn add_event_exception_rejects_non_occurrence_date() {
    let server = make_server();
    // Weekly every Monday; March 10 2026 is a Tuesday
    let event_id = create_recurring_event(
        &server,
        "2026-03-09", // Monday
        r#"{"FREQ":"WEEKLY","INTERVAL":1}"#,
    );

    let err = server
        .add_event_exception(Parameters(AddEventExceptionArgs {
            event_id,
            date: "2026-03-10".to_string(), // Tuesday — not an occurrence of a Monday weekly
            idempotency_key: None,
            dry_run: false,
        }))
        .expect_err("non-occurrence date should be rejected");
    assert!(
        err.contains("not a valid occurrence"),
        "error should mention occurrence: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn add_event_exception_accepts_valid_weekly_byday_occurrence() {
    let server = make_server();
    // Weekly on MO and WE starting 2026-03-09 (Monday)
    let event_id = create_recurring_event(
        &server,
        "2026-03-09",
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#,
    );

    // March 11 2026 is Wednesday — valid
    let result = server.add_event_exception(Parameters(AddEventExceptionArgs {
        event_id: event_id.clone(),
        date: "2026-03-11".to_string(),
        idempotency_key: None,
        dry_run: false,
    }));
    assert!(
        result.is_ok(),
        "Wednesday occurrence should be accepted: {result:?}"
    );

    // March 12 2026 is Thursday — invalid
    let err = server
        .add_event_exception(Parameters(AddEventExceptionArgs {
            event_id,
            date: "2026-03-12".to_string(),
            idempotency_key: None,
            dry_run: false,
        }))
        .expect_err("Thursday is not a MO/WE occurrence");
    assert!(err.contains("not a valid occurrence"), "error: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn add_event_exception_rejects_date_after_until_bound() {
    let server = make_server();
    let event_id = create_recurring_event(
        &server,
        "2026-03-09",
        r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-11"}"#,
    );

    let err = server
        .add_event_exception(Parameters(AddEventExceptionArgs {
            event_id,
            date: "2026-03-15".to_string(), // past `until` bound
            idempotency_key: None,
            dry_run: false,
        }))
        .expect_err("date after until should be rejected");
    assert!(err.contains("not a valid occurrence"), "error: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn create_calendar_event_normalizes_plain_frequency_recurrence() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Weekly Sync".to_string(),
            recurrence: Some("WEEKLY".to_string()),
            timezone: None,
            start_date: "2026-03-10".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("09:30".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid calendar event json");
    let recurrence = event["recurrence"]
        .as_str()
        .expect("calendar recurrence should be persisted");
    let parsed: Value = serde_json::from_str(recurrence).expect("recurrence json");
    assert_eq!(parsed["FREQ"], "WEEKLY");
    assert_eq!(parsed["INTERVAL"], 1);
}

#[test]
#[serial_test::serial(hlc)]
fn create_calendar_event_rejects_dst_skipped_local_time() {
    let server = make_server();
    let err = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Spring-forward event".to_string(),
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            start_date: "2026-03-08".to_string(),
            start_time: Some("02:30".to_string()),
            end_date: None,
            end_time: Some("03:30".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect_err("MCP create must reject DST-skipped wall clocks");

    assert!(
        err.contains("does not exist") && err.contains("America/New_York"),
        "expected shared DST-gap message, got: {err}"
    );
}

fn read_dst_ambiguity_warning(server: &LorvexMcpServer) -> (String, String, String) {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT level, message, details FROM error_logs
                 WHERE source = 'calendar_events.dst_ambiguous'
                 ORDER BY created_at DESC LIMIT 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .map_err(to_error_message)
        })
        .expect("read DST ambiguity warning")
}

#[test]
#[serial_test::serial(hlc)]
fn create_calendar_event_accepts_dst_ambiguous_with_warning() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Fall-back event".to_string(),
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            start_date: "2026-11-01".to_string(),
            start_time: Some("01:30".to_string()),
            end_date: None,
            end_time: Some("02:30".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("MCP create should accept ambiguous fall-back wall clock");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");

    assert_eq!(event["start_time"], "01:30");
    let (level, message, details) = read_dst_ambiguity_warning(&server);
    assert_eq!(level, "warn");
    assert!(
        message.contains("America/New_York") && message.contains("01:30"),
        "expected timezone and wall-clock in warning, got: {message}"
    );
    assert!(
        details.contains(event["id"].as_str().expect("event id")),
        "warning details should point at event id, got: {details}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn update_calendar_event_rejects_non_weekly_byday_recurrence() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Monthly Anchor".to_string(),
            recurrence: None,
            timezone: None,
            start_date: "2026-03-10".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("09:30".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create baseline calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");
    let event_id = event["id"].as_str().expect("event id").to_string();

    let err = server
        .update_calendar_event(Parameters(wire_args(CalendarEventUpdateWire {
            id: event_id,
            title: None,
            recurrence: Patch::Set("{\"FREQ\":\"MONTHLY\",\"BYDAY\":[\"MO\"]}".to_string()),
            timezone: Patch::Unset,
            start_date: Patch::Unset,
            start_time: Patch::Unset,
            end_date: Patch::Unset,
            end_time: Patch::Unset,
            all_day: None,
            description: Patch::Unset,
            location: Patch::Unset,
            url: Patch::Unset,
            color: Patch::Unset,
            event_type: Patch::Unset,
            person_name: Patch::Unset,
            attendees: Patch::Unset,
        })))
        .expect_err("non-weekly recurrence.byday should fail");
    assert!(err.contains("only valid for WEEKLY"), "error: {err}");
}

#[test]
#[serial_test::serial(hlc)]
fn update_calendar_event_rejects_dst_skipped_local_time() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Spring-forward update target".to_string(),
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            start_date: "2026-03-07".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("10:00".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create baseline calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");
    let event_id = event["id"].as_str().expect("event id").to_string();

    let err = server
        .update_calendar_event(Parameters(wire_args(CalendarEventUpdateWire {
            id: event_id,
            title: None,
            recurrence: Patch::Unset,
            timezone: Patch::Unset,
            start_date: Patch::Set("2026-03-08".to_string()),
            start_time: Patch::Set("02:30".to_string()),
            end_date: Patch::Unset,
            end_time: Patch::Set("03:30".to_string()),
            all_day: None,
            description: Patch::Unset,
            location: Patch::Unset,
            url: Patch::Unset,
            color: Patch::Unset,
            event_type: Patch::Unset,
            person_name: Patch::Unset,
            attendees: Patch::Unset,
        })))
        .expect_err("MCP update must reject DST-skipped wall clocks");

    assert!(
        err.contains("does not exist") && err.contains("America/New_York"),
        "expected shared DST-gap message, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn update_calendar_event_accepts_dst_ambiguous_with_warning() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Fall-back update target".to_string(),
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            start_date: "2026-10-31".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("10:00".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create baseline calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");
    let event_id = event["id"].as_str().expect("event id").to_string();

    let payload = server
        .update_calendar_event(Parameters(wire_args(CalendarEventUpdateWire {
            id: event_id.clone(),
            title: None,
            recurrence: Patch::Unset,
            timezone: Patch::Unset,
            start_date: Patch::Set("2026-11-01".to_string()),
            start_time: Patch::Set("01:30".to_string()),
            end_date: Patch::Unset,
            end_time: Patch::Set("02:30".to_string()),
            all_day: None,
            description: Patch::Unset,
            location: Patch::Unset,
            url: Patch::Unset,
            color: Patch::Unset,
            event_type: Patch::Unset,
            person_name: Patch::Unset,
            attendees: Patch::Unset,
        })))
        .expect("MCP update should accept ambiguous fall-back wall clock");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");

    assert_eq!(event["start_time"], "01:30");
    let (level, message, details) = read_dst_ambiguity_warning(&server);
    assert_eq!(level, "warn");
    assert!(
        message.contains("America/New_York") && message.contains("01:30"),
        "expected timezone and wall-clock in warning, got: {message}"
    );
    assert!(
        details.contains(&event_id),
        "warning details should point at event id, got: {details}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn update_calendar_event_rejects_blank_existing_start_date() {
    let server = make_server();
    let payload = server
        .create_calendar_event(Parameters(CreateCalendarEventArgs {
            title: "Broken Event".to_string(),
            recurrence: None,
            timezone: None,
            start_date: "2026-03-10".to_string(),
            start_time: Some("09:00".to_string()),
            end_date: None,
            end_time: Some("09:30".to_string()),
            all_day: Some(false),
            description: None,
            location: None,
            url: None,
            color: None,
            event_type: None,
            person_name: None,
            attendees: None,
        }))
        .expect("create baseline calendar event");
    let event: Value = serde_json::from_str(&payload).expect("valid event json");
    let event_id = event["id"].as_str().expect("event id").to_string();
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE calendar_events SET start_date = '' WHERE id = ?1",
                [&event_id],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("corrupt start_date");

    let err = server
        .update_calendar_event(Parameters(wire_args(CalendarEventUpdateWire {
            id: event_id,
            title: Some("Retitled".to_string()),
            recurrence: Patch::Unset,
            timezone: Patch::Unset,
            start_date: Patch::Unset,
            start_time: Patch::Unset,
            end_date: Patch::Unset,
            end_time: Patch::Unset,
            all_day: None,
            description: Patch::Unset,
            location: Patch::Unset,
            url: Patch::Unset,
            color: Patch::Unset,
            event_type: Patch::Unset,
            person_name: Patch::Unset,
            attendees: Patch::Unset,
        })))
        .expect_err("blank existing start_date should fail");
    assert!(err.contains("start_date"), "error: {err}");
}

fn seed_calendar_event_with_links_mcp(server: &LorvexMcpServer, event_id: &str, task_ids: &[&str]) {
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO calendar_events (
                    id, title, start_date, all_day, version, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 1, ?4, ?5, ?5)",
                (
                    event_id,
                    "Team sync",
                    "2026-04-10",
                    "0000000000000_0000_0000000000000000",
                    "2026-04-01T08:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            for task_id in task_ids {
                // lift to canonical TaskBuilder.
                let title = format!("Task {task_id}");
                lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
                    .title(&title)
                    .created_at("2026-04-01T08:00:00Z")
                    .insert(conn);
                conn.execute(
                    "INSERT INTO task_calendar_event_links
                        (task_id, calendar_event_id, created_at, updated_at, version)
                     VALUES (?1, ?2, ?3, ?3, ?4)",
                    (
                        task_id,
                        event_id,
                        "2026-04-01T08:00:00Z",
                        "0000000000000_0000_0000000000000000",
                    ),
                )
                .map_err(to_error_message)?;
            }
            Ok(())
        })
        .expect("seed calendar event with links");
}

fn count_outbox_entries(
    server: &LorvexMcpServer,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                (entity_type, entity_id, operation),
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count outbox entries")
}

fn count_tombstones(server: &LorvexMcpServer, entity_type: &str, entity_id: &str) -> i64 {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_tombstones
                 WHERE entity_type = ?1 AND entity_id = ?2",
                (entity_type, entity_id),
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count tombstones")
}

fn read_outbox_payload(server: &LorvexMcpServer, entity_type: &str, entity_id: &str) -> Value {
    server
        .with_conn(|conn| {
            let raw: String = conn
                .query_row(
                    "SELECT payload FROM sync_outbox
                     WHERE entity_type = ?1 AND entity_id = ?2
                     ORDER BY id DESC LIMIT 1",
                    (entity_type, entity_id),
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            serde_json::from_str(&raw).map_err(|error| error.to_string())
        })
        .expect("read outbox payload")
}

fn read_changelog_before_json(
    server: &LorvexMcpServer,
    entity_type: &str,
    entity_id: &str,
) -> Value {
    server
        .with_conn(|conn| {
            let raw: String = conn
                .query_row(
                    "SELECT before_json FROM ai_changelog
                     WHERE entity_type = ?1 AND entity_id = ?2
                     ORDER BY timestamp DESC LIMIT 1",
                    (entity_type, entity_id),
                    |row| row.get(0),
                )
                .map_err(to_error_message)?;
            serde_json::from_str(&raw).map_err(|error| error.to_string())
        })
        .expect("read changelog before_json")
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_delete_calendar_event_emits_edge_tombstones() {
    // MCP delete_calendar_event must mirror the inbound
    // apply path and tombstone + enqueue a DELETE envelope for every
    // task_calendar_event_link that the SQLite FK CASCADE removes.
    let server = make_server();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000603";
    let task_ids = [
        "01966a3f-7c8b-7d4e-8f3a-000000000601",
        "01966a3f-7c8b-7d4e-8f3a-000000000602",
    ];
    seed_calendar_event_with_links_mcp(&server, event_id, &task_ids);

    let payload = server
        .delete_calendar_event(Parameters(DeleteCalendarEventArgs {
            idempotency_key: None,
            id: event_id.to_string(),
            dry_run: false,
        }))
        .expect("delete_calendar_event should succeed");
    let result: Value = serde_json::from_str(&payload).expect("valid delete result json");
    assert_eq!(result["id"], event_id);
    assert_eq!(result["deleted"], true);
    let mut returned_ids: Vec<String> = result["unlinked_task_ids"]
        .as_array()
        .expect("unlinked_task_ids array")
        .iter()
        .map(|v| v.as_str().expect("task id string").to_string())
        .collect();
    returned_ids.sort();
    assert_eq!(
        returned_ids,
        vec![
            "01966a3f-7c8b-7d4e-8f3a-000000000601".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000602".to_string()
        ]
    );

    // Calendar event row itself is gone.
    let remaining_events: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
                [event_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count calendar event");
    assert_eq!(remaining_events, 0);

    for task_id in &task_ids {
        let edge_entity_id = format!("{task_id}:{event_id}");
        assert!(
            count_outbox_entries(
                &server,
                "task_calendar_event_link",
                &edge_entity_id,
                "delete"
            ) >= 1,
            "expected DELETE envelope in sync_outbox for edge {edge_entity_id}"
        );
        assert_eq!(
            count_tombstones(&server, "task_calendar_event_link", &edge_entity_id),
            1,
            "expected tombstone for edge {edge_entity_id}"
        );
        for snapshot in [
            read_outbox_payload(&server, "task_calendar_event_link", &edge_entity_id),
            read_changelog_before_json(&server, "task_calendar_event_link", &edge_entity_id),
        ] {
            assert_eq!(snapshot["task_id"], serde_json::json!(task_id));
            assert_eq!(snapshot["calendar_event_id"], serde_json::json!(event_id));
            assert_eq!(
                snapshot["created_at"],
                serde_json::json!("2026-04-01T08:00:00Z"),
                "edge delete snapshot must preserve created_at"
            );
            assert_eq!(
                snapshot["updated_at"],
                serde_json::json!("2026-04-01T08:00:00Z"),
                "edge delete snapshot must preserve updated_at"
            );
            assert_eq!(
                snapshot["version"],
                serde_json::json!("0000000000000_0000_0000000000000000"),
                "edge delete snapshot must preserve the link row version"
            );
        }
    }

    // The calendar_event delete envelope itself must still be enqueued.
    assert_eq!(
        count_outbox_entries(&server, "calendar_event", event_id, "delete"),
        1
    );
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_delete_calendar_event_without_any_links_does_not_emit_edge_envelopes() {
    let server = make_server();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000603";
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO calendar_events (
                    id, title, start_date, all_day, version, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 1, ?4, ?5, ?5)",
                (
                    event_id,
                    "Solo event",
                    "2026-04-12",
                    "0000000000000_0000_0000000000000000",
                    "2026-04-01T08:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("insert calendar event");

    let payload = server
        .delete_calendar_event(Parameters(DeleteCalendarEventArgs {
            idempotency_key: None,
            id: event_id.to_string(),
            dry_run: false,
        }))
        .expect("delete_calendar_event should succeed");
    let result: Value = serde_json::from_str(&payload).expect("valid delete result json");
    let unlinked = result["unlinked_task_ids"]
        .as_array()
        .expect("unlinked_task_ids array");
    assert!(unlinked.is_empty(), "no edges → no unlinked ids");

    let edge_outbox_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = 'task_calendar_event_link'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count edge outbox entries");
    assert_eq!(edge_outbox_count, 0);
    let edge_tombstone_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM sync_tombstones
                 WHERE entity_type = 'task_calendar_event_link'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .map_err(to_error_message)
        })
        .expect("count edge tombstones");
    assert_eq!(edge_tombstone_count, 0);

    assert_eq!(
        count_outbox_entries(&server, "calendar_event", event_id, "delete"),
        1
    );
}
