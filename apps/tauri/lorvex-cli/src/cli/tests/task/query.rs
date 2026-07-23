use super::*;
#[test]
fn parse_tasks_filters() {
    assert_eq!(
        parse(&[
            "tasks",
            "--list",
            "01900000-0000-7000-8001-000000000001",
            "--status",
            "all",
            "--priority",
            "1",
            "--due-from",
            "2026-04-01",
            "--due-to",
            "2026-04-30",
            "--planned-from",
            "2026-04-02",
            "--planned-to",
            "2026-04-29",
            "--completed-from",
            "2026-04-03",
            "--completed-to",
            "2026-04-28",
            "--created-from",
            "2026-04-04",
            "--created-to",
            "2026-04-27",
            "--has-due-date",
            "--no-planned-date",
            "--tag",
            "Work",
            "--text",
            "roadmap",
            "--blocked-only",
            "--blocking-others",
            "--sort-by",
            "updated_at",
            "--sort-direction",
            "desc",
            "-l",
            "12",
        ]),
        Command::Tasks(TasksCommand::List {
            list_id: Some("01900000-0000-7000-8001-000000000001".to_string()),
            status: "all".to_string(),
            priority: Some(1),
            due_from: Some("2026-04-01".to_string()),
            due_to: Some("2026-04-30".to_string()),
            planned_from: Some("2026-04-02".to_string()),
            planned_to: Some("2026-04-29".to_string()),
            completed_from: Some("2026-04-03".to_string()),
            completed_to: Some("2026-04-28".to_string()),
            created_from: Some("2026-04-04".to_string()),
            created_to: Some("2026-04-27".to_string()),
            has_due_date: Some(true),
            has_planned_date: Some(false),
            tags: vec!["Work".to_string()],
            text: Some("roadmap".to_string()),
            blocked_only: true,
            blocking_others: true,
            sort_by: "updated_at".to_string(),
            sort_direction: "desc".to_string(),
            limit: 12,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_dependency_graph_query() {
    assert_eq!(
        parse(&[
            "graph",
            "--task-id",
            "01900000-0000-7000-8000-000000000001",
            "--list",
            "01900000-0000-7000-8001-000000000001",
            "--include-inactive",
            "--limit-nodes",
            "25",
            "--limit-edges",
            "40",
        ]),
        Command::Tasks(TasksCommand::DependencyGraph {
            task_id: Some("01900000-0000-7000-8000-000000000001".to_string()),
            list_id: Some("01900000-0000-7000-8001-000000000001".to_string()),
            include_inactive: true,
            limit_nodes: 25,
            limit_edges: 40,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_today_overdue_upcoming() {
    assert_eq!(
        parse(&["today", "-l", "5"]),
        Command::Tasks(TasksCommand::Today {
            limit: 5,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["overdue", "--limit", "3"]),
        Command::Tasks(TasksCommand::Overdue {
            limit: 3,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["upcoming", "-d", "14", "-l", "7"]),
        Command::Tasks(TasksCommand::Upcoming {
            days: 14,
            limit: 7,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&[
            "deferred",
            "--list",
            "01900000-0000-7000-8001-000000000001",
            "-l",
            "9"
        ]),
        Command::Tasks(TasksCommand::Deferred {
            list_id: Some("01900000-0000-7000-8001-000000000001".to_string()),
            limit: 9,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["reminder", "due", "-l", "8"]),
        Command::Reminders(RemindersCommand::Due {
            limit: 8,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["reminder", "upcoming", "--hours", "48", "-l", "9"]),
        Command::Reminders(RemindersCommand::Upcoming {
            hours: 48,
            limit: 9,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "reminder",
            "set",
            "01900000-0000-7000-8000-000000000001",
            "--at",
            "2026-05-01T09:00:00Z",
            "--at",
            "2026-05-01T17:00:00Z",
        ]),
        Command::Reminders(RemindersCommand::Set {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            reminders: vec![
                "2026-05-01T09:00:00Z".to_string(),
                "2026-05-01T17:00:00Z".to_string(),
            ],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["reminder", "clear", "01900000-0000-7000-8000-000000000001"]),
        Command::Reminders(RemindersCommand::Clear {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "reminder",
            "add",
            "01900000-0000-7000-8000-000000000001",
            "2026-05-01T09:00:00Z"
        ]),
        Command::Reminders(RemindersCommand::Add {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            reminder_at: "2026-05-01T09:00:00Z".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "reminder",
            "remove",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8004-000000000001"
        ]),
        Command::Reminders(RemindersCommand::Remove {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            reminder_id: "01900000-0000-7000-8004-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
}
