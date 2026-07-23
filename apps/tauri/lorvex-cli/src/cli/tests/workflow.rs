//! clap parse-tree tests for the new workflow / checklist
//! / structured-task-write subcommands. These tests assert that the
//! flag spelling is stable and that the dispatch enum carries the
//! expected variants — they don't open the DB, so they run inline with
//! the rest of the parse-tree suite.

use super::*;

const TASK_UUID: &str = "01949c00-0000-7000-8000-000000000001";
const TASK_UUID_2: &str = "01949c00-0000-7000-8000-000000000002";
const ITEM_UUID: &str = "01949c00-0000-7000-8000-000000000003";
const HABIT_UUID: &str = "01949c00-0000-7000-8000-000000000004";
const LIST_UUID: &str = "01949c00-0000-7000-8000-000000000005";

#[test]
fn parse_overview_default_and_compact() {
    assert_eq!(
        parse(&["overview"]),
        Command::Workflow(WorkflowCommand::Overview {
            compact: false,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["overview", "--compact"]),
        Command::Workflow(WorkflowCommand::Overview {
            compact: true,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_session_context_and_guide_topic() {
    assert_eq!(
        parse(&["session-context"]),
        Command::Workflow(WorkflowCommand::SessionContext {
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["guide", "--topic", "getting_started"]),
        Command::Workflow(WorkflowCommand::Guide {
            topic: Some("getting_started"),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["guide"]),
        Command::Workflow(WorkflowCommand::Guide {
            topic: None,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_recent_logs_with_filters() {
    assert_eq!(
        parse(&[
            "recent-logs",
            "--limit",
            "50",
            "--level",
            "error",
            "--level",
            "warn",
            "--source",
            "ai_changelog",
            "--include-details"
        ]),
        Command::Workflow(WorkflowCommand::RecentLogs {
            limit: Some(50),
            since: None,
            levels: vec!["error".to_string(), "warn".to_string()],
            sources: vec!["ai_changelog".to_string()],
            include_details: true,
            redact: true,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_recent_logs_no_redact_flips_redact_to_false() {
    assert_eq!(
        parse(&["recent-logs", "--no-redact"]),
        Command::Workflow(WorkflowCommand::RecentLogs {
            limit: None,
            since: None,
            levels: vec![],
            sources: vec![],
            include_details: false,
            redact: false,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_analyze_with_window_and_top_n() {
    assert_eq!(
        parse(&["analyze", "--window-days", "30", "--top-n", "10"]),
        Command::Workflow(WorkflowCommand::Analyze {
            window_days: Some(30),
            top_n: Some(10),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_reorganize_priority_strategy() {
    assert_eq!(
        parse(&["reorganize", LIST_UUID, "--strategy", "priority"]),
        Command::Workflow(WorkflowCommand::Reorganize {
            list_id: LIST_UUID.to_string(),
            strategy: "priority",
            task_ids: vec![],
            dry_run: false,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_reorganize_manual_with_task_ids() {
    assert_eq!(
        parse(&[
            "reorganize",
            LIST_UUID,
            "--strategy",
            "manual",
            "--task-id",
            TASK_UUID,
            "--task-id",
            TASK_UUID_2,
            "--dry-run",
        ]),
        Command::Workflow(WorkflowCommand::Reorganize {
            list_id: LIST_UUID.to_string(),
            strategy: "manual",
            task_ids: vec![TASK_UUID.to_string(), TASK_UUID_2.to_string()],
            dry_run: true,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_habit_completions() {
    assert_eq!(
        parse(&["habit-completions", HABIT_UUID, "--days", "60"]),
        Command::Workflow(WorkflowCommand::HabitCompletions {
            habit_id: HABIT_UUID.to_string(),
            days: Some(60),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_checklist_add_with_text_join() {
    assert_eq!(
        parse(&[
            "checklist",
            "add",
            TASK_UUID,
            "Step",
            "one",
            "done",
            "--position",
            "0"
        ]),
        Command::Tasks(TasksCommand::ChecklistAdd {
            task_id: TASK_UUID.to_string(),
            text: "Step one done".to_string(),
            position: Some(0),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_checklist_toggle_explicit_completed_or_uncompleted() {
    assert_eq!(
        parse(&["checklist", "toggle", ITEM_UUID, "--completed"]),
        Command::Tasks(TasksCommand::ChecklistToggle {
            item_id: ITEM_UUID.to_string(),
            completed: true,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["checklist", "toggle", ITEM_UUID, "--uncompleted"]),
        Command::Tasks(TasksCommand::ChecklistToggle {
            item_id: ITEM_UUID.to_string(),
            completed: false,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_checklist_remove_and_reorder() {
    assert_eq!(
        parse(&["checklist", "remove", ITEM_UUID]),
        Command::Tasks(TasksCommand::ChecklistRemove {
            item_id: ITEM_UUID.to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["checklist", "reorder", TASK_UUID, ITEM_UUID]),
        Command::Tasks(TasksCommand::ChecklistReorder {
            task_id: TASK_UUID.to_string(),
            item_ids: vec![ITEM_UUID.to_string()],
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_set_recurrence_weekly_with_byday() {
    assert_eq!(
        parse(&[
            "task",
            "set-recurrence",
            TASK_UUID,
            "--freq",
            "weekly",
            "--byday",
            "MO",
            "--byday",
            "WE",
            "--interval",
            "2"
        ]),
        Command::Tasks(TasksCommand::SetRecurrence {
            task_id: TASK_UUID.to_string(),
            freq: "weekly",
            interval: Some(2),
            byday: vec!["MO".to_string(), "WE".to_string()],
            bymonthday: vec![],
            until: None,
            count: None,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_set_recurrence_monthly_with_multi_bymonthday() {
    assert_eq!(
        parse(&[
            "task",
            "set-recurrence",
            TASK_UUID,
            "--freq",
            "monthly",
            "--bymonthday",
            "1,15,-1",
        ]),
        Command::Tasks(TasksCommand::SetRecurrence {
            task_id: TASK_UUID.to_string(),
            freq: "monthly",
            interval: None,
            byday: vec![],
            bymonthday: vec![1, 15, -1],
            until: None,
            count: None,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_permanent_delete_with_dry_run() {
    assert_eq!(
        parse(&["task", "permanent-delete", TASK_UUID, "--dry-run"]),
        Command::Tasks(TasksCommand::PermanentDelete {
            task_id: TASK_UUID.to_string(),
            dry_run: true,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_create_with_full_structured_shape() {
    assert_eq!(
        parse(&[
            "task",
            "create",
            "Ship",
            "feature",
            "--list",
            LIST_UUID,
            "--priority",
            "1",
            "--due-date",
            "2026-05-01",
            "--tag",
            "Work",
            "--depends-on",
            TASK_UUID,
            "--reminder",
            "2026-05-01T09:00:00Z",
            "--ai-notes",
            "AI authored",
            "--idempotency-key",
            "abc",
        ]),
        Command::Tasks(TasksCommand::Create {
            title: "Ship feature".to_string(),
            list_id: Some(LIST_UUID.to_string()),
            priority: Some(1),
            due_date: Some("2026-05-01".to_string()),
            due_time: None,
            planned_date: None,
            estimated_minutes: None,
            tags: vec!["Work".to_string()],
            body: None,
            ai_notes: Some("AI authored".to_string()),
            depends_on: vec![TASK_UUID.to_string()],
            reminders: vec!["2026-05-01T09:00:00Z".to_string()],
            recurrence: None,
            completed: false,
            idempotency_key: Some("abc".to_string()),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_batch_create_and_batch_update_pass_through_json() {
    assert_eq!(
        parse(&[
            "task",
            "batch-create",
            "--tasks-json",
            r#"[{"title":"X"}]"#,
            "--include-advice"
        ]),
        Command::Tasks(TasksCommand::BatchCreate {
            tasks_json: r#"[{"title":"X"}]"#.to_string(),
            include_advice: true,
            idempotency_key: None,
            dry_run: false,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "task",
            "batch-update",
            "--updates-json",
            r#"[{"id":"x","priority":1}]"#,
            "--dry-run"
        ]),
        Command::Tasks(TasksCommand::BatchUpdate {
            updates_json: r#"[{"id":"x","priority":1}]"#.to_string(),
            dry_run: true,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_task_batch_cancel_in_list_with_status_filter() {
    assert_eq!(
        parse(&[
            "task",
            "batch-cancel-in-list",
            LIST_UUID,
            "--status",
            "open",
            "--status",
            "someday",
            "--series",
        ]),
        Command::Tasks(TasksCommand::BatchCancelInList {
            list_id: LIST_UUID.to_string(),
            statuses: vec!["open".to_string(), "someday".to_string()],
            cancel_series: Some(true),
            dry_run: false,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_rejects_invalid_uuid_for_id_args() {
    assert!(try_parse(&["checklist", "add", "not-a-uuid", "text"]).is_err());
    assert!(try_parse(&["task", "permanent-delete", "abc"]).is_err());
    assert!(try_parse(&["habit-completions", "abc"]).is_err());
}
