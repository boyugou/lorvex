use super::*;
use lorvex_domain::Patch;
#[test]
fn parse_calendar_tree() {
    assert_eq!(
        parse(&["calendar", "list"]),
        Command::Calendar(CalendarCommand::List {
            limit: 20,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["calendar", "show", "01900000-0000-7000-8003-000000000001"]),
        Command::Calendar(CalendarCommand::Show {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["calendar", "today"]),
        Command::Calendar(CalendarCommand::Today {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "create",
            "Design",
            "review",
            "--start-date",
            "2026-04-30",
            "--start-time",
            "09:30",
            "--end-time",
            "10:00",
            "--timezone",
            "America/New_York",
            "--event-type",
            "event",
        ]),
        Command::Calendar(CalendarCommand::Create {
            title: "Design review".to_string(),
            start_date: "2026-04-30".to_string(),
            start_time: Some("09:30".to_string()),
            end_date: None,
            end_time: Some("10:00".to_string()),
            all_day: false,
            description: None,
            location: None,
            url: None,
            color: None,
            recurrence: None,
            timezone: Some("America/New_York".to_string()),
            event_type: Some("event".to_string()),
            person_name: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "update",
            "01900000-0000-7000-8003-000000000001",
            "--title",
            "Updated",
            "--clear-location",
            "--all-day",
        ]),
        Command::Calendar(CalendarCommand::Update {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            title: Some("Updated".to_string()),
            start_date: None,
            start_time: Patch::Unset,
            end_date: Patch::Unset,
            end_time: Patch::Unset,
            all_day: Some(true),
            description: Patch::Unset,
            location: Patch::Clear,
            url: Patch::Unset,
            color: Patch::Unset,
            recurrence: Patch::Unset,
            timezone: Patch::Unset,
            event_type: Patch::Unset,
            person_name: Patch::Unset,
            attendees: AttendeesPatch::Unset,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "batch-create",
            "--events-json",
            r#"[{"title":"A","start_date":"2026-04-30"}]"#,
        ]),
        Command::Calendar(CalendarCommand::BatchCreate {
            events_json: r#"[{"title":"A","start_date":"2026-04-30"}]"#.to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["calendar", "delete", "01900000-0000-7000-8003-000000000001"]),
        Command::Calendar(CalendarCommand::Delete {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "link",
            "01900000-0000-7000-8003-000000000001",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002"
        ]),
        Command::Calendar(CalendarCommand::Link {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "unlink",
            "01900000-0000-7000-8003-000000000001",
            "01900000-0000-7000-8000-000000000001"
        ]),
        Command::Calendar(CalendarCommand::Unlink {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "links-for-task",
            "01900000-0000-7000-8000-000000000001"
        ]),
        Command::Calendar(CalendarCommand::LinksForTask {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "links-for-event",
            "01900000-0000-7000-8003-000000000001"
        ]),
        Command::Calendar(CalendarCommand::LinksForEvent {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "add-exception",
            "01900000-0000-7000-8003-000000000001",
            "2026-05-07"
        ]),
        Command::Calendar(CalendarCommand::AddException {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            date: "2026-05-07".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "remove-exception",
            "01900000-0000-7000-8003-000000000001",
            "2026-05-07"
        ]),
        Command::Calendar(CalendarCommand::RemoveException {
            event_id: "01900000-0000-7000-8003-000000000001".to_string(),
            date: "2026-05-07".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "provider-link",
            "01900000-0000-7000-8000-000000000001",
            "--provider-kind",
            "eventkit",
            "--provider-scope",
            "default",
            "--provider-event-key",
            "ek-1",
        ]),
        Command::Calendar(CalendarCommand::ProviderLink {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            provider_kind: "eventkit".to_string(),
            provider_scope: "default".to_string(),
            provider_event_key: "ek-1".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "provider-unlink",
            "01900000-0000-7000-8000-000000000001",
            "--provider-kind",
            "ical_subscription",
            "--provider-scope",
            "sub-a",
            "--provider-event-key",
            "uid-1",
        ]),
        Command::Calendar(CalendarCommand::ProviderUnlink {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            provider_kind: "ical_subscription".to_string(),
            provider_scope: "sub-a".to_string(),
            provider_event_key: "uid-1".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "provider-link",
            "01900000-0000-7000-8000-000000000001",
            "--provider-kind",
            "eventkit",
            "--provider-event-key",
            "ek-1",
        ]),
        Command::Calendar(CalendarCommand::ProviderLink {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            provider_kind: "eventkit".to_string(),
            provider_scope: String::new(),
            provider_event_key: "ek-1".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "provider-links-for-task",
            "01900000-0000-7000-8000-000000000001"
        ]),
        Command::Calendar(CalendarCommand::ProviderLinksForTask {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "export-ics",
            "--from",
            "2026-05-01",
            "--to",
            "2026-05-31",
        ]),
        Command::Calendar(CalendarCommand::ExportIcs {
            from: "2026-05-01".to_string(),
            to: "2026-05-31".to_string(),
            format: OutputFormat::Text,
        })
    );
}
