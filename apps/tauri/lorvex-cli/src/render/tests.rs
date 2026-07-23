use std::path::Path;

use lorvex_store::repositories::{list_repo, task::read};

use super::*;
use crate::cli::OutputFormat;
use crate::models::TaskSummary;

#[test]
fn yes_no_formats_boolean_flags() {
    assert_eq!(yes_no(true), "yes");
    assert_eq!(yes_no(false), "no");
}

#[test]
fn render_task_action_result_supports_json_output() {
    let rendered = render_task_action_result(
        "task.complete",
        "task-1",
        "Ship it",
        Path::new("/tmp/lorvex.db"),
        OutputFormat::Json,
    )
    .expect("render json action");
    let value: serde_json::Value =
        serde_json::from_str(&rendered).expect("parse rendered action json");
    // render_task_action_result wraps the payload in the canonical
    // `{action, db_path, ...}` envelope and emits the action string
    // verbatim — the caller is responsible for the canonical
    // `<domain>.<verb>` namespacing every CLI mutation honors.
    assert_eq!(value["action"], "task.complete");
    assert_eq!(value["task_id"], "task-1");
    assert_eq!(value["title"], "Ship it");
}

#[test]
fn render_task_collection_supports_json_output() {
    let rendered = render_task_collection(
        "Today",
        Path::new("/tmp/lorvex.db"),
        vec![TaskSummary {
            id: "task-1".to_string(),
            title: "Write query tests".to_string(),
            status: "open".to_string(),
            due_date: Some(lorvex_domain::Date::parse("2026-03-30").unwrap()),
            planned_date: None,
            priority: Some(2),
            list_id: "inbox".to_string(),
        }],
        OutputFormat::Json,
    )
    .expect("render collection json");
    let value: serde_json::Value =
        serde_json::from_str(&rendered).expect("parse rendered collection json");
    assert_eq!(value["label"], "Today");
    assert_eq!(value["tasks"][0]["id"], "task-1");
}

#[test]
fn render_list_collection_supports_json_output() {
    let list = list_repo::ListWithCounts {
        list: list_repo::ListRow {
            id: "list-1".to_string(),
            name: "Inbox".to_string(),
            color: Some("#fff".to_string()),
            icon: None,
            description: None,
            ai_notes: None,
            created_at: lorvex_domain::time::SyncTimestamp::parse("2026-03-30T00:00:00Z")
                .expect("canonical fixture"),
            updated_at: lorvex_domain::time::SyncTimestamp::parse("2026-03-30T00:00:00Z")
                .expect("canonical fixture"),
            version: "v1".to_string(),
            archived_at: None,
            position: 0,
        },
        open_count: 2,
        total_count: 3,
    };
    let rendered = render_list_collection(Path::new("/tmp/lorvex.db"), &[list], OutputFormat::Json)
        .expect("render list collection");
    let value: serde_json::Value =
        serde_json::from_str(&rendered).expect("parse list collection json");
    assert_eq!(value["lists"][0]["id"], "list-1");
    assert_eq!(value["lists"][0]["open_count"], 2);
}

#[test]
fn render_task_detail_includes_core_fields() {
    let task = read::TaskRow::from_parts(
        read::TaskCore::new(read::TaskCoreFields {
            id: "task-1".to_string(),
            title: "Inspect task".to_string(),
            body: None,
            raw_input: None,
            ai_notes: Some("note".to_string()),
            status: "open".to_string(),
            list_id: "inbox".to_string(),
            priority: Some(1),
            version: "v1".to_string(),
            created_at: "2026-03-30T00:00:00Z".to_string(),
            updated_at: "2026-03-30T00:00:00Z".to_string(),
        }),
        read::TaskScheduling::new(read::TaskSchedulingFields {
            due: lorvex_domain::DueAt::OnDay(lorvex_domain::Date::parse("2026-03-30").unwrap()),
            ..Default::default()
        }),
        read::TaskRecurrenceState::new(read::TaskRecurrenceStateFields::default()),
        read::TaskLifecycleTimestamps::new(read::TaskLifecycleTimestampsFields::default()),
    );
    let rendered = render_task_detail(&task, Path::new("/tmp/lorvex.db"), None);
    assert!(rendered.contains("Inspect task"));
    assert!(rendered.contains("Status: open"));
    assert!(rendered.contains("Notes: note"));
}

#[test]
fn task_row_to_summary_preserves_query_fields() {
    let row = read::TaskRow::from_parts(
        read::TaskCore::new(read::TaskCoreFields {
            id: "task-2".to_string(),
            title: "Summary me".to_string(),
            body: None,
            raw_input: None,
            ai_notes: None,
            status: "open".to_string(),
            list_id: "list-1".to_string(),
            priority: Some(3),
            version: "v1".to_string(),
            created_at: "2026-03-30T00:00:00Z".to_string(),
            updated_at: "2026-03-30T00:00:00Z".to_string(),
        }),
        read::TaskScheduling::new(read::TaskSchedulingFields {
            due: lorvex_domain::DueAt::OnDay(lorvex_domain::Date::parse("2026-03-31").unwrap()),
            planned_date: Some(lorvex_domain::Date::parse("2026-03-30").unwrap()),
            ..Default::default()
        }),
        read::TaskRecurrenceState::new(read::TaskRecurrenceStateFields::default()),
        read::TaskLifecycleTimestamps::new(read::TaskLifecycleTimestampsFields::default()),
    );
    let summary = task_row_to_summary(row);
    assert_eq!(summary.id, "task-2");
    assert_eq!(summary.list_id, "list-1");
    assert_eq!(
        summary.planned_date,
        Some(lorvex_domain::Date::parse("2026-03-30").unwrap())
    );
}

#[test]
fn render_list_detail_shows_priority_dates_and_truncated_id() {
    let list = list_repo::ListRow {
        id: "list-1".to_string(),
        name: "Work".to_string(),
        color: None,
        icon: None,
        description: Some("Work tasks".to_string()),
        ai_notes: None,
        created_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T00:00:00Z")
            .expect("canonical fixture"),
        updated_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T00:00:00Z")
            .expect("canonical fixture"),
        version: "v1".to_string(),
        archived_at: None,
        position: 0,
    };
    let tasks = vec![
        TaskSummary {
            id: "019d5caa-bbcc-7000-aaaa-000000000001".to_string(),
            title: "Ship feature".to_string(),
            status: "open".to_string(),
            due_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
            planned_date: None,
            priority: Some(1),
            list_id: "list-1".to_string(),
        },
        TaskSummary {
            id: "019d5caa-bbcc-7000-aaaa-000000000002".to_string(),
            title: "Review PR".to_string(),
            status: "open".to_string(),
            due_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
            planned_date: Some(lorvex_domain::Date::parse("2026-04-08").unwrap()),
            priority: None,
            list_id: "list-1".to_string(),
        },
        TaskSummary {
            id: "019d5caa-bbcc-7000-aaaa-000000000003".to_string(),
            title: "Plain task".to_string(),
            status: "completed".to_string(),
            due_date: None,
            planned_date: None,
            priority: None,
            list_id: "list-1".to_string(),
        },
    ];
    let rendered = render_list_detail(
        Path::new("/tmp/lorvex.db"),
        &list,
        &tasks,
        OutputFormat::Text,
    )
    .expect("render list detail");

    // Task with priority and due date
    assert!(rendered.contains("Ship feature [open] P1 due:2026-04-10 [019d5caa]"));
    // Task with due + different planned date
    assert!(rendered.contains("Review PR [open] due:2026-04-10 planned:2026-04-08 [019d5caa]"));
    // Task with no priority, no dates
    assert!(rendered.contains("Plain task [completed] [019d5caa]"));
}

#[test]
fn render_list_detail_omits_planned_when_same_as_due() {
    let list = list_repo::ListRow {
        id: "list-1".to_string(),
        name: "Home".to_string(),
        color: None,
        icon: None,
        description: None,
        ai_notes: None,
        created_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T00:00:00Z")
            .expect("canonical fixture"),
        updated_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T00:00:00Z")
            .expect("canonical fixture"),
        version: "v1".to_string(),
        archived_at: None,
        position: 0,
    };
    let tasks = vec![TaskSummary {
        id: "019d5caa-1234-7000-bbbb-000000000001".to_string(),
        title: "Same dates".to_string(),
        status: "open".to_string(),
        due_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
        planned_date: Some(lorvex_domain::Date::parse("2026-04-10").unwrap()),
        priority: Some(2),
        list_id: "list-1".to_string(),
    }];
    let rendered = render_list_detail(
        Path::new("/tmp/lorvex.db"),
        &list,
        &tasks,
        OutputFormat::Text,
    )
    .expect("render list detail");

    // planned date should be omitted when it matches due date
    assert!(rendered.contains("Same dates [open] P2 due:2026-04-10 [019d5caa]"));
    assert!(!rendered.contains("planned:"));
}
