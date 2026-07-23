use super::*;
use lorvex_domain::Patch;
#[test]
fn parse_habit_tree() {
    assert_eq!(
        parse(&["habits"]),
        Command::Habits(HabitsCommand::List {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["habit", "complete", "01900000-0000-7000-8002-000000000001"]),
        Command::Habits(HabitsCommand::Complete {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            date: None,
            note: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "complete",
            "01900000-0000-7000-8002-000000000001",
            "--date",
            "2026-04-24",
            "--note",
            "Done",
        ]),
        Command::Habits(HabitsCommand::Complete {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            date: Some("2026-04-24".to_string()),
            note: Some("Done".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "batch-complete",
            "01900000-0000-7000-8002-000000000001",
            "01900000-0000-7000-8002-000000000002",
            "--date",
            "2026-04-24",
        ]),
        Command::Habits(HabitsCommand::BatchComplete {
            habit_ids: vec![
                "01900000-0000-7000-8002-000000000001".to_string(),
                "01900000-0000-7000-8002-000000000002".to_string()
            ],
            date: Some("2026-04-24".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "uncomplete",
            "01900000-0000-7000-8002-000000000001",
            "--date",
            "2026-04-24"
        ]),
        Command::Habits(HabitsCommand::Uncomplete {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            date: Some("2026-04-24".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "create",
            "Morning",
            "pages",
            "--icon",
            "M",
            "--color",
            "#A1b2C3",
            "--cue",
            "After coffee",
            "--frequency-type",
            "weekly",
            "--weekday",
            "mon",
            "--weekday",
            "wed",
            "--target-count",
            "2",
        ]),
        Command::Habits(HabitsCommand::Create {
            name: "Morning pages".to_string(),
            icon: Some("M".to_string()),
            color: Some("#A1b2C3".to_string()),
            cue: Some("After coffee".to_string()),
            frequency_type: Some("weekly".to_string()),
            weekdays: vec!["mon".to_string(), "wed".to_string()],
            per_period_target: None,
            day_of_month: None,
            target_count: Some(2),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "update",
            "01900000-0000-7000-8002-000000000001",
            "--name",
            "Walk",
            "--clear-icon",
            "--frequency-type",
            "times_per_week",
            "--per-period-target",
            "3",
            "--archive",
        ]),
        Command::Habits(HabitsCommand::Update {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            name: Some("Walk".to_string()),
            icon: Patch::Clear,
            color: Patch::Unset,
            cue: Patch::Unset,
            frequency_type: Some("times_per_week".to_string()),
            weekdays: vec![],
            per_period_target: Some(3),
            day_of_month: None,
            target_count: None,
            archived: Some(true),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["habit", "delete", "01900000-0000-7000-8002-000000000001"]),
        Command::Habits(HabitsCommand::Delete {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "stats",
            "01900000-0000-7000-8002-000000000001",
            "-d",
            "14"
        ]),
        Command::Habits(HabitsCommand::Stats {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            days: Some(14),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["habit", "reminder", "list"]),
        Command::Habits(HabitsCommand::ReminderList {
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "reminder",
            "upsert",
            "01900000-0000-7000-8002-000000000001",
            "07:30",
            "--id",
            "01900000-0000-7000-8005-000000000001",
            "--disabled",
        ]),
        Command::Habits(HabitsCommand::ReminderUpsert {
            habit_id: "01900000-0000-7000-8002-000000000001".to_string(),
            reminder_time: "07:30".to_string(),
            policy_id: Some("01900000-0000-7000-8005-000000000001".to_string()),
            enabled: false,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "habit",
            "reminder",
            "delete",
            "01900000-0000-7000-8005-000000000001"
        ]),
        Command::Habits(HabitsCommand::ReminderDelete {
            policy_id: "01900000-0000-7000-8005-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
}
