use super::*;
#[test]
fn parse_review_tree() {
    assert_eq!(
        parse(&["review", "get", "--date", "2026-06-01"]),
        Command::Review(ReviewCommand::Get {
            date: Some("2026-06-01".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["review", "history", "--since", "2026-06-01", "--limit", "7"]),
        Command::Review(ReviewCommand::History {
            since: Some("2026-06-01".to_string()),
            limit: 7,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "review",
            "weekly",
            "--completed-limit",
            "10",
            "--stalled-limit",
            "4",
            "--deferred-limit",
            "6",
            "--someday-limit",
            "8"
        ]),
        Command::Review(ReviewCommand::Weekly {
            completed_limit: 10,
            stalled_lists_limit: 4,
            deferred_limit: 6,
            someday_limit: 8,
            format: OutputFormat::Text,
        })
    );
    // `lorvex review brief` mirrors MCP `get_weekly_review_brief`.
    // Defaults must match the MCP `WEEKLY_BRIEF_*_DEFAULT` constants
    // (50 / 50 / 10 / 20) so cross-surface invocations agree.
    assert_eq!(
        parse(&["review", "brief"]),
        Command::Review(ReviewCommand::Brief {
            completed_limit: 50,
            stalled_lists_limit: 50,
            deferred_limit: 10,
            someday_limit: 20,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "review",
            "brief",
            "--completed-limit",
            "25",
            "--stalled-limit",
            "5",
            "--deferred-limit",
            "8",
            "--someday-limit",
            "12"
        ]),
        Command::Review(ReviewCommand::Brief {
            completed_limit: 25,
            stalled_lists_limit: 5,
            deferred_limit: 8,
            someday_limit: 12,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "review",
            "add",
            "--date",
            "2026-06-01",
            "--summary",
            "Shipped CLI review support",
            "--mood",
            "4",
            "--energy",
            "3",
            "--win",
            "Useful parity",
            "--blocker",
            "None",
            "--learning",
            "Keep slices bounded",
            "--ai-synthesis",
            "Momentum is good",
            "--linked-task",
            "01900000-0000-7000-8000-000000000001",
            "--linked-list",
            "01900000-0000-7000-8001-000000000099"
        ]),
        Command::Review(ReviewCommand::Add {
            date: Some("2026-06-01".to_string()),
            summary: "Shipped CLI review support".to_string(),
            mood: Some(4),
            energy_level: Some(3),
            wins: Some("Useful parity".to_string()),
            blockers: Some("None".to_string()),
            learnings: Some("Keep slices bounded".to_string()),
            ai_synthesis: Some("Momentum is good".to_string()),
            linked_task_ids: vec!["01900000-0000-7000-8000-000000000001".to_string()],
            linked_list_ids: vec!["01900000-0000-7000-8001-000000000099".to_string()],
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "review",
            "amend",
            "2026-06-01",
            "--summary",
            "Updated summary",
            "--linked-task-set",
            "01900000-0000-7000-8000-000000000002",
            "--linked-list-set",
            "01900000-0000-7000-8001-000000000099"
        ]),
        Command::Review(ReviewCommand::Amend {
            date: "2026-06-01".to_string(),
            summary: Some("Updated summary".to_string()),
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: Some(vec!["01900000-0000-7000-8000-000000000002".to_string()]),
            linked_list_ids: Some(vec!["01900000-0000-7000-8001-000000000099".to_string()]),
            format: OutputFormat::Text,
        })
    );
}
