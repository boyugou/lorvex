use super::*;
#[test]
fn parse_bare_focus_routes_to_focus_show() {
    assert_eq!(
        parse(&["focus"]),
        Command::Focus(FocusCommand::Show {
            date: None,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["focus"]),
        Command::Focus(FocusCommand::Show {
            date: None,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["focus"]),
        Command::Focus(FocusCommand::Show {
            date: None,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["focus", "--date", "2026-06-01"]),
        Command::Focus(FocusCommand::Show {
            date: Some("2026-06-01".to_string()),
            format: OutputFormat::Text
        })
    );
}

#[test]
fn parse_focus_tree() {
    assert_eq!(
        parse(&[
            "focus",
            "set",
            "01900000-0000-7000-8000-00000000000a",
            "01900000-0000-7000-8000-00000000000b",
            "--briefing",
            "Deep work",
            "--date",
            "2026-06-01"
        ]),
        Command::Focus(FocusCommand::Set {
            date: Some("2026-06-01".to_string()),
            task_ids: vec![
                "01900000-0000-7000-8000-00000000000a".to_string(),
                "01900000-0000-7000-8000-00000000000b".to_string()
            ],
            briefing: Some("Deep work".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["focus", "add", "01900000-0000-7000-8000-00000000000c"]),
        Command::Focus(FocusCommand::Add {
            date: None,
            task_ids: vec!["01900000-0000-7000-8000-00000000000c".to_string()],
            briefing: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "focus",
            "remove",
            "01900000-0000-7000-8000-00000000000a",
            "--date",
            "2026-06-02"
        ]),
        Command::Focus(FocusCommand::Remove {
            date: Some("2026-06-02".to_string()),
            task_id: "01900000-0000-7000-8000-00000000000a".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["focus", "clear", "--date", "2026-06-03"]),
        Command::Focus(FocusCommand::Clear {
            date: Some("2026-06-03".to_string()),
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["focus", "schedule", "get", "--date", "2026-06-04"]),
        Command::Focus(FocusCommand::ScheduleGet {
            date: Some("2026-06-04".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["focus", "schedule", "propose", "--date", "2026-06-04"]),
        Command::Focus(FocusCommand::SchedulePropose {
            date: Some("2026-06-04".to_string()),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
            parse(&[
                "focus",
                "schedule",
                "save",
                "--date",
                "2026-06-04",
                "--blocks-json",
                r#"[{"block_type":"task","task_id":"01900000-0000-7000-8000-00000000000a","start_time":"09:00","end_time":"10:00"}]"#,
                "--rationale",
                "Protect maker time",
            ]),
            Command::Focus(FocusCommand::ScheduleSave {
                date: Some("2026-06-04".to_string()),
                blocks_json: r#"[{"block_type":"task","task_id":"01900000-0000-7000-8000-00000000000a","start_time":"09:00","end_time":"10:00"}]"#.to_string(),
                rationale: Some("Protect maker time".to_string()),
                format: OutputFormat::Text,
            })
        );
}
