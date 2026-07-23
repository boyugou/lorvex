use super::*;
use lorvex_domain::Patch;

#[test]
fn parse_capture_complete_reopen() {
    assert_eq!(
        parse(&["capture", "Write", "tests"]),
        Command::Tasks(TasksCommand::Capture {
            title: "Write tests".to_string(),
            list: None,
            priority: None,
            due_date: None,
            planned_date: None,
            estimated_minutes: None,
            tags: Vec::new(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "capture",
            "Write",
            "tests",
            "--list",
            "01900000-0000-7000-8001-000000000001"
        ]),
        Command::Tasks(TasksCommand::Capture {
            title: "Write tests".to_string(),
            list: Some("01900000-0000-7000-8001-000000000001".to_string()),
            priority: None,
            due_date: None,
            planned_date: None,
            estimated_minutes: None,
            tags: Vec::new(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "capture",
            "Write",
            "tests",
            "--priority",
            "2",
            "--due-date",
            "2026-05-01",
            "--planned-date",
            "2026-04-30",
            "--estimated-minutes",
            "45",
            "--tag",
            "work",
            "--tag",
            "Deep Work",
        ]),
        Command::Tasks(TasksCommand::Capture {
            title: "Write tests".to_string(),
            list: None,
            priority: Some(2),
            due_date: Some("2026-05-01".to_string()),
            planned_date: Some("2026-04-30".to_string()),
            estimated_minutes: Some(45),
            tags: vec!["work".to_string(), "Deep Work".to_string()],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["complete", "01900000-0000-7000-8000-000000000001"]),
        Command::Tasks(TasksCommand::Complete {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "complete",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002"
        ]),
        Command::Tasks(TasksCommand::Complete {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["reopen", "01900000-0000-7000-8000-000000000001"]),
        Command::Tasks(TasksCommand::Reopen {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "reopen",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002"
        ]),
        Command::Tasks(TasksCommand::Reopen {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_update_task_fields_and_clears() {
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--title",
            "Review PR",
            "--body",
            "Notes",
            "--ai-notes",
            "Assistant context",
            "--list",
            "01900000-0000-7000-8001-000000000001",
            "--priority",
            "1",
            "--due-date",
            "2026-05-01",
            "--due-time",
            "09:30",
            "--planned-date",
            "2026-04-30",
            "--estimated-minutes",
            "45",
            "--tag-set",
            "work",
            "--tag-set",
            "Deep Work",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: Some("Review PR".to_string()),
            body: Patch::Set("Notes".to_string()),
            ai_notes: Patch::Set("Assistant context".to_string()),
            status: None,
            raw_input: None,
            list_id: Some("01900000-0000-7000-8001-000000000001".to_string()),
            priority: Patch::Set(1),
            due_date: Patch::Set("2026-05-01".to_string()),
            due_time: Patch::Set("09:30".to_string()),
            planned_date: Patch::Set("2026-04-30".to_string()),
            estimated_minutes: Patch::Set(45),
            tags_set: Some(vec!["work".to_string(), "Deep Work".to_string()]),
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Unset,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--clear-body",
            "--clear-ai-notes",
            "--clear-priority",
            "--clear-due-date",
            "--clear-due-time",
            "--clear-planned-date",
            "--clear-estimated-minutes",
            "--clear-tags",
            "--clear-depends-on",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Clear,
            ai_notes: Patch::Clear,
            status: None,
            raw_input: None,
            list_id: None,
            priority: Patch::Clear,
            due_date: Patch::Clear,
            due_time: Patch::Clear,
            planned_date: Patch::Clear,
            estimated_minutes: Patch::Clear,
            tags_set: Some(Vec::new()),
            tags_add: None,
            tags_remove: None,
            depends_on_set: Some(Vec::new()),
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Unset,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--tag-add",
            "work",
            "--tag-remove",
            "old",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Unset,
            ai_notes: Patch::Unset,
            status: None,
            raw_input: None,
            list_id: None,
            priority: Patch::Unset,
            due_date: Patch::Unset,
            due_time: Patch::Unset,
            planned_date: Patch::Unset,
            estimated_minutes: Patch::Unset,
            tags_set: None,
            tags_add: Some(vec!["work".to_string()]),
            tags_remove: Some(vec!["old".to_string()]),
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Unset,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );
    // dependency task ids must parse as canonical
    // UUIDv7. Update fixture to a real UUID rather than the legacy
    // `blocker-1` literal.
    let blocker_uuid = "01928f55-0000-7000-8000-000000000001";
    let removed_uuid = "01928f55-0000-7000-8000-000000000002";
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--depends-on-add",
            blocker_uuid,
            "--depends-on-remove",
            removed_uuid,
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Unset,
            ai_notes: Patch::Unset,
            status: None,
            raw_input: None,
            list_id: None,
            priority: Patch::Unset,
            due_date: Patch::Unset,
            due_time: Patch::Unset,
            planned_date: Patch::Unset,
            estimated_minutes: Patch::Unset,
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: Some(vec![blocker_uuid.to_string()]),
            depends_on_remove: Some(vec![removed_uuid.to_string()]),
            recurrence: Patch::Unset,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );
}

/// `--status` patches the lifecycle status column;
/// `--raw-input` writes through to `tasks.raw_input`. Both bring the
/// CLI into surface parity with MCP's `update_task` contract.
#[test]
fn task_update_supports_status_and_raw_input_flags() {
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--status",
            "someday",
            "--raw-input",
            "park this for later",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Unset,
            ai_notes: Patch::Unset,
            status: Some("someday".to_string()),
            raw_input: Some("park this for later".to_string()),
            list_id: None,
            priority: Patch::Unset,
            due_date: Patch::Unset,
            due_time: Patch::Unset,
            planned_date: Patch::Unset,
            estimated_minutes: Patch::Unset,
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Unset,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );

    let err = try_parse(&[
        "update",
        "01900000-0000-7000-8000-000000000001",
        "--status",
        "in-progress",
    ])
    .expect_err("non-allowlist status must be rejected at parse time");
    assert_eq!(err.exit_code(), 2);
    assert!(
        err.to_string()
            .contains("status must be one of: open, completed, cancelled, someday"),
        "unexpected error: {err}",
    );
}

/// `--recurrence` carries a JSON object describing a recurrence rule
/// patch (mirrors MCP `update_task`); `--clear-recurrence` sets the
/// canonical `Patch::Clear`; `--idempotency-key` threads through to
/// the shared CLI idempotency cache.
#[test]
fn task_update_supports_recurrence_and_idempotency_flags() {
    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--recurrence",
            r#"{"freq":"weekly","interval":2,"byday":["MO"]}"#,
            "--idempotency-key",
            "retry-token-1",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Unset,
            ai_notes: Patch::Unset,
            status: None,
            raw_input: None,
            list_id: None,
            priority: Patch::Unset,
            due_date: Patch::Unset,
            due_time: Patch::Unset,
            planned_date: Patch::Unset,
            estimated_minutes: Patch::Unset,
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Set(r#"{"freq":"weekly","interval":2,"byday":["MO"]}"#.to_string(),),
            idempotency_key: Some("retry-token-1".to_string()),
            format: OutputFormat::Text,
        })
    );

    assert_eq!(
        parse(&[
            "update",
            "01900000-0000-7000-8000-000000000001",
            "--clear-recurrence",
        ]),
        Command::Tasks(TasksCommand::Update {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            title: None,
            body: Patch::Unset,
            ai_notes: Patch::Unset,
            status: None,
            raw_input: None,
            list_id: None,
            priority: Patch::Unset,
            due_date: Patch::Unset,
            due_time: Patch::Unset,
            planned_date: Patch::Unset,
            estimated_minutes: Patch::Unset,
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: Patch::Clear,
            idempotency_key: None,
            format: OutputFormat::Text,
        })
    );

    let err = try_parse(&[
        "update",
        "01900000-0000-7000-8000-000000000001",
        "--recurrence",
        "{}",
        "--clear-recurrence",
    ])
    .expect_err("--recurrence and --clear-recurrence must not be combined");
    assert_eq!(err.exit_code(), 2);
}

#[test]
fn parse_cancel_preserves_series_tristate() {
    // No flag → None (not Some(false)).
    assert_eq!(
        parse(&["cancel", "01900000-0000-7000-8000-000000000001"]),
        Command::Tasks(TasksCommand::Cancel {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            cancel_series: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["cancel", "01900000-0000-7000-8000-000000000001", "--series"]),
        Command::Tasks(TasksCommand::Cancel {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            cancel_series: Some(true),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "cancel",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002",
            "--series"
        ]),
        Command::Tasks(TasksCommand::Cancel {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            cancel_series: Some(true),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_trash_lifecycle_tree() {
    assert_eq!(
        parse(&[
            "trash",
            "move",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002"
        ]),
        Command::Trash(TrashCommand::Move {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["trash", "restore", "01900000-0000-7000-8000-000000000001"]),
        Command::Trash(TrashCommand::Restore {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "trash",
            "delete",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002",
            "--dry-run"
        ]),
        Command::Trash(TrashCommand::Delete {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            dry_run: true,
            format: OutputFormat::Text,
        })
    );

    let err = try_parse(&[
        "trash",
        "delete",
        "01900000-0000-7000-8000-000000000001",
        "01900000-0000-7000-8000-000000000002",
    ])
    .expect_err("batch permanent delete must be dry-run only");
    assert_eq!(err.exit_code(), 2);
}

#[test]
fn parse_defer_all_fields() {
    assert_eq!(
        parse(&[
            "defer",
            "01900000-0000-7000-8000-000000000001",
            "-d",
            "3",
            "--reason",
            "Heads down",
            "--structured-reason",
            "needs_info",
        ]),
        Command::Tasks(TasksCommand::Defer {
            task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            days: Some(3),
            reason: Some("Heads down".to_string()),
            structured_reason: Some("needs_info".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "defer",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002",
            "--days",
            "3",
            "--reason",
            "Heads down",
            "--structured-reason",
            "needs_info",
        ]),
        Command::Tasks(TasksCommand::Defer {
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            days: Some(3),
            reason: Some("Heads down".to_string()),
            structured_reason: Some("needs_info".to_string()),
            format: OutputFormat::Text,
        })
    );
}
