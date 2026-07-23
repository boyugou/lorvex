//! Shared deterministic fixtures for the render snapshot suite. No
//! clock-dependent helpers (`chrono::Utc::now`, etc.) — every
//! timestamp is a fixed ISO string so the goldens stay stable.

use std::path::Path;

use lorvex_domain::CanonicalCalendarEventType;
use lorvex_store::calendar_timeline::{
    CalendarEventRow, CalendarEventRowFields, CalendarTimelineItem, CalendarTimelineItemFields,
    TimelineSource,
};
use lorvex_store::repositories::{list_repo, memory_repo, task::read};

use crate::models::{CurrentFocusView, HabitSummary, TagSummary, TaskListItem, TaskSummary};

const DB_PATH: &str = "/tmp/lorvex.db";

pub(super) fn db_path() -> &'static Path {
    Path::new(DB_PATH)
}

pub(super) fn fixture_task_alpha() -> TaskSummary {
    TaskSummary {
        id: "task-alpha".to_string(),
        title: "Ship feature".to_string(),
        status: "open".to_string(),
        due_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
        planned_date: None,
        priority: Some(1),
        list_id: "list-work".to_string(),
    }
}

pub(super) fn fixture_task_bravo() -> TaskSummary {
    TaskSummary {
        id: "task-bravo".to_string(),
        title: "Review PR".to_string(),
        status: "in_progress".to_string(),
        due_date: Some(lorvex_domain::Date::parse("2026-04-12").unwrap()),
        planned_date: Some(lorvex_domain::Date::parse("2026-04-11").unwrap()),
        priority: Some(2),
        list_id: "list-work".to_string(),
    }
}

pub(super) fn fixture_task_charlie() -> TaskSummary {
    TaskSummary {
        id: "task-charlie".to_string(),
        title: "Plain task".to_string(),
        status: "completed".to_string(),
        due_date: None,
        planned_date: None,
        priority: None,
        list_id: "list-home".to_string(),
    }
}

pub(super) fn fixture_tasks() -> Vec<TaskSummary> {
    vec![
        fixture_task_alpha(),
        fixture_task_bravo(),
        fixture_task_charlie(),
    ]
}

pub(super) fn fixture_task_row_full() -> read::TaskRow {
    read::TaskRow::from_parts(
        read::TaskCore::new(read::TaskCoreFields {
            id: "task-alpha".to_string(),
            title: "Ship feature".to_string(),
            body: Some("Body text".to_string()),
            raw_input: Some("raw".to_string()),
            ai_notes: Some("Investigate the sync race".to_string()),
            status: "open".to_string(),
            list_id: "list-work".to_string(),
            priority: Some(1),
            version: "v1".to_string(),
            created_at: "2026-04-01T10:00:00Z".to_string(),
            updated_at: "2026-04-05T12:00:00Z".to_string(),
        }),
        read::TaskScheduling::new(read::TaskSchedulingFields {
            due: lorvex_domain::DueAt::AtMoment {
                date: lorvex_domain::Date::parse("2026-04-10").unwrap(),
                time: lorvex_domain::TimeOfDay::parse("09:00").unwrap(),
            },
            estimated_minutes: Some(60),
            planned_date: Some(lorvex_domain::Date::parse("2026-04-09").unwrap()),
            available_from: None,
            defer_count: 0,
            last_deferred_at: None,
            last_defer_reason: None,
        }),
        read::TaskRecurrenceState::new(read::TaskRecurrenceStateFields::default()),
        read::TaskLifecycleTimestamps::new(read::TaskLifecycleTimestampsFields::default()),
    )
}

pub(super) fn fixture_task_row_minimal() -> read::TaskRow {
    read::TaskRow::from_parts(
        read::TaskCore::new(read::TaskCoreFields {
            id: "task-bravo".to_string(),
            title: "Minimal task".to_string(),
            body: None,
            raw_input: None,
            ai_notes: None,
            status: "open".to_string(),
            list_id: "list-work".to_string(),
            priority: None,
            version: "v1".to_string(),
            created_at: "2026-04-01T10:00:00Z".to_string(),
            updated_at: "2026-04-01T10:00:00Z".to_string(),
        }),
        read::TaskScheduling::new(read::TaskSchedulingFields::default()),
        read::TaskRecurrenceState::new(read::TaskRecurrenceStateFields::default()),
        read::TaskLifecycleTimestamps::new(read::TaskLifecycleTimestampsFields::default()),
    )
}

pub(super) fn fixture_list_row() -> list_repo::ListRow {
    use lorvex_domain::time::SyncTimestamp;
    // fixtures must round-trip through the canonical
    // `SyncTimestamp` parser so wire snapshots stay byte-stable.
    let parse = |raw: &str| SyncTimestamp::parse(raw).expect("canonical fixture timestamp");
    list_repo::ListRow {
        id: "list-work".to_string(),
        name: "Work".to_string(),
        color: Some("#ff0000".to_string()),
        icon: Some("briefcase".to_string()),
        description: Some("Work-related tasks".to_string()),
        ai_notes: Some("Keep prioritised".to_string()),
        created_at: parse("2026-04-01T10:00:00Z"),
        updated_at: parse("2026-04-02T10:00:00Z"),
        version: "v1".to_string(),
        archived_at: None,
        position: 0,
    }
}

pub(super) fn fixture_list_with_counts() -> Vec<list_repo::ListWithCounts> {
    use lorvex_domain::time::SyncTimestamp;
    let parse = |raw: &str| SyncTimestamp::parse(raw).expect("canonical fixture timestamp");
    vec![
        list_repo::ListWithCounts {
            list: fixture_list_row(),
            open_count: 3,
            total_count: 5,
        },
        list_repo::ListWithCounts {
            list: list_repo::ListRow {
                id: "list-home".to_string(),
                name: "Home".to_string(),
                color: None,
                icon: None,
                description: None,
                ai_notes: None,
                created_at: parse("2026-04-01T10:00:00Z"),
                updated_at: parse("2026-04-01T10:00:00Z"),
                version: "v1".to_string(),
                archived_at: None,
                position: 0,
            },
            open_count: 0,
            total_count: 2,
        },
    ]
}

pub(super) fn fixture_timeline_canonical() -> CalendarTimelineItem {
    CalendarTimelineItem::new(CalendarTimelineItemFields {
        source: TimelineSource::Canonical,
        editable: true,
        id: "event-alpha".to_string(),
        title: "Standup".to_string(),
        start_date: lorvex_domain::Date::parse("2026-04-10").unwrap(),
        start_time: Some(lorvex_domain::TimeOfDay::parse("09:00").unwrap()),
        end_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
        end_time: Some(lorvex_domain::TimeOfDay::parse("09:30").unwrap()),
        all_day: false,
        location: Some("Zoom".to_string()),
        color: Some("#00aaff".to_string()),
        event_type: "event".to_string(),
        person_name: None,
        timezone: Some("America/Los_Angeles".to_string()),
        provider_kind: None,
        provider_scope: None,
        is_recurring: false,
        source_time_kind: None,
        source_tzid: None,
        url: None,
        attendees_json: None,
    })
    .expect("canonical timeline fixture has valid typed timing")
}

pub(super) fn fixture_timeline_all_day() -> CalendarTimelineItem {
    CalendarTimelineItem::new(CalendarTimelineItemFields {
        source: TimelineSource::Canonical,
        editable: true,
        id: "event-bravo".to_string(),
        title: "Conference".to_string(),
        start_date: lorvex_domain::Date::parse("2026-04-12").unwrap(),
        start_time: None,
        end_date: Some(lorvex_domain::Date::parse("2026-04-12").unwrap()),
        end_time: None,
        all_day: true,
        location: None,
        color: None,
        event_type: "event".to_string(),
        person_name: None,
        timezone: None,
        provider_kind: None,
        provider_scope: None,
        is_recurring: false,
        source_time_kind: None,
        source_tzid: None,
        url: None,
        attendees_json: None,
    })
    .expect("all-day timeline fixture has valid typed timing")
}

pub(super) fn fixture_calendar_event_row() -> CalendarEventRow {
    CalendarEventRow::new(CalendarEventRowFields {
        id: "event-alpha".to_string(),
        title: "Standup".to_string(),
        description: Some("Daily team sync".to_string()),
        recurrence: Some("FREQ=DAILY".to_string()),
        recurrence_exceptions: None,
        timezone: Some("America/Los_Angeles".to_string()),
        start_date: lorvex_domain::Date::parse("2026-04-10").unwrap(),
        start_time: Some(lorvex_domain::TimeOfDay::parse("09:00").unwrap()),
        end_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
        end_time: Some(lorvex_domain::TimeOfDay::parse("09:30").unwrap()),
        all_day: false,
        location: Some("Zoom".to_string()),
        color: Some("#00aaff".to_string()),
        event_type: CanonicalCalendarEventType::Event,
        person_name: None,
        url: Some("https://example.com/zoom".to_string()),
        created_at: "2026-04-01T10:00:00Z".to_string(),
        updated_at: "2026-04-02T10:00:00Z".to_string(),
        version: "2026-04-02T10:00:00Z_0000000000000000".to_string(),
    })
    .expect("calendar event row fixture has valid typed timing")
}

pub(super) fn fixture_habits() -> Vec<HabitSummary> {
    vec![
        HabitSummary {
            id: "habit-alpha".to_string(),
            name: "Read".to_string(),
            icon: Some("book".to_string()),
            frequency_type: "daily".to_string(),
            target_count: 1,
            completions_today: 1,
        },
        HabitSummary {
            id: "habit-bravo".to_string(),
            name: "Push-ups".to_string(),
            icon: None,
            frequency_type: "daily".to_string(),
            target_count: 3,
            completions_today: 1,
        },
        HabitSummary {
            id: "habit-charlie".to_string(),
            name: "Meditate".to_string(),
            icon: Some("lotus".to_string()),
            frequency_type: "weekly".to_string(),
            target_count: 5,
            completions_today: 0,
        },
    ]
}

pub(super) fn fixture_memory_entries() -> Vec<memory_repo::MemoryEntry> {
    use lorvex_domain::time::SyncTimestamp;
    // fixture timestamps must round-trip through the
    // canonical `SyncTimestamp` parser so render snapshots stay
    // byte-stable across the wire-format change.
    let parse = |raw: &str| SyncTimestamp::parse(raw).expect("canonical fixture timestamp");
    vec![
        memory_repo::MemoryEntry {
            key: "preferences.tone".to_string(),
            content: "friendly".to_string(),
            version: "v1".to_string(),
            updated_at: parse("2026-04-01T10:00:00Z"),
        },
        memory_repo::MemoryEntry {
            key: "notes.long".to_string(),
            content:
                "This is a long memory entry that should be truncated at eighty bytes because \
                 we want to keep the collection view compact and readable across contexts."
                    .to_string(),
            version: "v2".to_string(),
            updated_at: parse("2026-04-03T10:00:00Z"),
        },
    ]
}

pub(super) fn fixture_tags() -> Vec<TagSummary> {
    vec![
        TagSummary {
            id: "tag-alpha".to_string(),
            display_name: "work".to_string(),
            color: Some("#ff0000".to_string()),
            task_count: 5,
        },
        TagSummary {
            id: "tag-bravo".to_string(),
            display_name: "personal".to_string(),
            color: None,
            task_count: 1,
        },
    ]
}

pub(super) fn fixture_current_focus() -> CurrentFocusView {
    CurrentFocusView {
        date: "2026-04-10".to_string(),
        briefing: Some("Focus on shipping the sync fixes.".to_string()),
        timezone: Some("America/Los_Angeles".to_string()),
        created_at: "2026-04-10T08:00:00Z".to_string(),
        updated_at: "2026-04-10T08:30:00Z".to_string(),
        task_ids: vec!["task-alpha".to_string(), "task-bravo".to_string()],
        tasks: vec![fixture_task_alpha(), fixture_task_bravo()],
    }
}

pub(super) fn fixture_task_list_items() -> Vec<TaskListItem> {
    vec![
        TaskListItem {
            id: "task-alpha".to_string(),
            title: "Ship feature".to_string(),
            when: Some("2026-04-10".to_string()),
        },
        TaskListItem {
            id: "task-bravo".to_string(),
            title: "Review PR".to_string(),
            when: None,
        },
    ]
}
