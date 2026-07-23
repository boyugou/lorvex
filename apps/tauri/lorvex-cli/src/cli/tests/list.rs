use super::*;
use lorvex_domain::Patch;
#[test]
fn parse_bare_list_id_routes_to_list_show() {
    assert_eq!(
        parse(&["list", "01900000-0000-7000-8001-000000000001", "-l", "9"]),
        Command::Lists(ListsCommand::Show {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            limit: 9,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_list_create_update_delete() {
    assert_eq!(
        parse(&["list", "create", "Work", "Queue", "--color", "#00ff00"]),
        Command::Lists(ListsCommand::Create {
            name: "Work Queue".to_string(),
            color: Some("#00ff00".to_string()),
            icon: None,
            description: None,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "-n",
            "Later",
            "--description",
            "Cold storage",
        ]),
        Command::Lists(ListsCommand::Update {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            name: Some("Later".to_string()),
            color: Patch::Unset,
            icon: Patch::Unset,
            description: Patch::Set("Cold storage".to_string()),
            ai_notes: Patch::Unset,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["list", "delete", "01900000-0000-7000-8001-000000000001"]),
        Command::Lists(ListsCommand::Delete {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["list", "health", "--limit", "7"]),
        Command::Lists(ListsCommand::Health {
            limit: 7,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_move_command() {
    assert_eq!(
        parse(&[
            "move",
            "01900000-0000-7000-8001-000000000001",
            "01900000-0000-7000-8000-000000000001",
            "01900000-0000-7000-8000-000000000002"
        ]),
        Command::Tasks(TasksCommand::Move {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            task_ids: vec![
                "01900000-0000-7000-8000-000000000001".to_string(),
                "01900000-0000-7000-8000-000000000002".to_string()
            ],
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn list_color_options_accept_canonical_hex() {
    // 6-digit form is canonical.
    assert_eq!(
        parse(&[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "--color",
            "#A1b2C3",
        ]),
        Command::Lists(ListsCommand::Update {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            name: None,
            color: Patch::Set("#A1b2C3".to_string()),
            icon: Patch::Unset,
            description: Patch::Unset,
            ai_notes: Patch::Unset,
            format: OutputFormat::Text,
        })
    );

    // 3-digit CSS short form (`#FFF`) is also valid. The shared
    // `lorvex_domain::validation::validate_hex_color` is the single
    // source of truth for both the CLI parser and the calendar
    // writer's acceptance set.
    assert_eq!(
        parse(&["list", "create", "Work", "--color", "#fff"]),
        Command::Lists(ListsCommand::Create {
            name: "Work".to_string(),
            color: Some("#fff".to_string()),
            icon: None,
            description: None,
            format: OutputFormat::Text,
        })
    );

    // Reject everything that fails the shared validator: missing `#`,
    // non-hex digits, wrong length.
    let cases: &[&[&str]] = &[
        &["list", "create", "Work", "--color", "00ff00"],
        &[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "--color",
            "#xyzxyz",
        ],
        &["list", "create", "Work", "--color", "#FFFF"],
    ];
    for args in cases {
        let err = try_parse(args).expect_err("invalid color should fail at parse time");
        assert_eq!(err.exit_code(), 2, "args were {args:?}");
        let rendered = err.to_string();
        assert!(
            rendered.contains("expected hex color like #4A90D9 or #FFF"),
            "args were {args:?}; error was:\n{rendered}"
        );
    }
}

/// The new `--clear-color`/`--clear-icon`/`--clear-description`/
/// `--clear-ai-notes` flags collapse to `Patch::Clear` in the canonical
/// `Patch<String>` tri-state. Setting and clearing the same column at
/// once is rejected by clap.
#[test]
fn list_update_supports_set_and_clear_flags_for_every_nullable_column() {
    assert_eq!(
        parse(&[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "--clear-color",
            "--clear-icon",
            "--clear-description",
            "--clear-ai-notes",
        ]),
        Command::Lists(ListsCommand::Update {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            name: None,
            color: Patch::Clear,
            icon: Patch::Clear,
            description: Patch::Clear,
            ai_notes: Patch::Clear,
            format: OutputFormat::Text,
        })
    );

    assert_eq!(
        parse(&[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "--ai-notes",
            "Worth revisiting next month",
        ]),
        Command::Lists(ListsCommand::Update {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            name: None,
            color: Patch::Unset,
            icon: Patch::Unset,
            description: Patch::Unset,
            ai_notes: Patch::Set("Worth revisiting next month".to_string()),
            format: OutputFormat::Text,
        })
    );

    let err = try_parse(&[
        "list",
        "update",
        "01900000-0000-7000-8001-000000000001",
        "--color",
        "#abcdef",
        "--clear-color",
    ])
    .expect_err("set and clear must conflict at parse time");
    assert_eq!(err.exit_code(), 2);
}
