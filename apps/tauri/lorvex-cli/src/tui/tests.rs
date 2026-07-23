use super::*;

#[test]
fn render_tui_dashboard_includes_task_sections_and_ids() {
    let snapshot = DashboardSnapshot {
        db_path: std::path::PathBuf::from("/tmp/lorvex.db"),
        today: "2026-03-30".to_string(),
        device_id: "device-123".to_string(),
        open_tasks: 4,
        overdue_tasks: 1,
        current_focus: Some("Finish proposal".to_string()),
        next_task: Some("Task alpha".to_string()),
        next_task_id: Some("task-a".to_string()),
        due_today: vec![TaskListItem {
            id: "task-a".to_string(),
            title: "Task alpha".to_string(),
            when: Some("2026-03-30".to_string()),
        }],
        upcoming: vec![TaskListItem {
            id: "task-b".to_string(),
            title: "Task beta".to_string(),
            when: Some("2026-04-01".to_string()),
        }],
        recently_completed: vec![TaskListItem {
            id: "task-c".to_string(),
            title: "Task gamma".to_string(),
            when: Some("2026-03-29T10:00:00Z".to_string()),
        }],
    };

    let rendered = render_tui_dashboard_for_snapshot(&snapshot);
    assert!(rendered.contains("Due today"));
    assert!(rendered.contains("task-a"));
    assert!(rendered.contains("Upcoming"));
    assert!(rendered.contains("Recently completed"));
    // Next task line should show truncated ID
    assert!(rendered.contains("Next task: Task alpha [task-a]"));
}

#[test]
fn render_tui_dashboard_truncates_long_next_task_id() {
    let snapshot = DashboardSnapshot {
        db_path: std::path::PathBuf::from("/tmp/lorvex.db"),
        today: "2026-04-01".to_string(),
        device_id: "device-456".to_string(),
        open_tasks: 1,
        overdue_tasks: 0,
        current_focus: None,
        next_task: Some("My important task".to_string()),
        next_task_id: Some("019d5caa-bbcc-7000-aaaa-000000000001".to_string()),
        due_today: vec![],
        upcoming: vec![],
        recently_completed: vec![],
    };

    let rendered = render_tui_dashboard_for_snapshot(&snapshot);
    assert!(rendered.contains("Next task: My important task [019d5caa]"));
}
