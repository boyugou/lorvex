use super::*;
use lorvex_domain::Patch;
#[test]
fn parse_setup_variants() {
    assert_eq!(
        parse(&["setup"]),
        Command::System(SystemCommand::Setup {
            install_target: None
        })
    );
    assert_eq!(
        parse(&["setup", "--install-mcp-for", "all"]),
        Command::System(SystemCommand::Setup {
            install_target: Some(McpInstallTarget::All)
        })
    );
}
#[test]
fn parse_doctor_and_status() {
    assert_eq!(
        parse(&["doctor"]),
        Command::System(SystemCommand::Doctor {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["status"]),
        Command::System(SystemCommand::Status {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["sync", "outbox", "--limit", "25"]),
        Command::Sync(SyncCommand::Outbox {
            limit: 25,
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&["sync", "status"]),
        Command::Sync(SyncCommand::Status {
            format: OutputFormat::Text
        })
    );
    assert_eq!(
        parse(&[
            "changelog",
            "--entity-type",
            "task",
            "--operation",
            "update",
            "--entity-id",
            "01900000-0000-7000-8000-000000000001",
            "--since",
            "2026-01-01T00:00:00.000000Z",
            "-l",
            "12",
        ]),
        Command::System(SystemCommand::Changelog {
            limit: 12,
            entity_type: Some("task".to_string()),
            operation: Some("update".to_string()),
            entity_id: Some("01900000-0000-7000-8000-000000000001".to_string()),
            since: Some("2026-01-01T00:00:00.000000Z".to_string()),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn rejects_removed_per_command_json_aliases() {
    for args in [
        &["doctor", "--json"][..],
        &["doctor", "-j"][..],
        &["tasks", "--json"][..],
        &["focus", "schedule", "get", "-j"][..],
    ] {
        let err = try_parse(args).expect_err("per-command JSON aliases should be removed");
        assert_eq!(err.kind(), clap::error::ErrorKind::UnknownArgument);
    }
}
#[test]
fn parse_search_joins_multi_word_query_and_supports_short_limit() {
    assert_eq!(
        parse(&["search", "deep", "work", "-l", "7"]),
        Command::Tasks(TasksCommand::Search {
            query: "deep work".to_string(),
            limit: 7,
            format: OutputFormat::Text,
        })
    );
}
#[test]
fn parse_tui_and_mcp() {
    assert_eq!(parse(&["tui"]), Command::System(SystemCommand::Tui));
    assert_eq!(
        parse(&["tui", "--watch"]),
        Command::System(SystemCommand::TuiWatch)
    );
    assert_eq!(
        parse(&["mcp", "serve"]),
        Command::System(SystemCommand::McpServe)
    );
    assert_eq!(
        parse(&["mcp", "install", "--for", "all"]),
        Command::System(SystemCommand::McpInstall {
            target: McpInstallTarget::All,
        })
    );
}

// --- clap-provided behavior: help / version / errors ----------

#[test]
fn empty_args_displays_help() {
    // Pre-clap behavior: bare `lorvex` printed the help text and
    // exited 0. Clap prints help on missing-subcommand as well
    // but uses exit code 2 (standard "usage error"). The user
    // must type `lorvex --help` for the zero-exit path — a
    // minor shift but consistent with every clap-based CLI.
    let err = try_parse(&[]).expect_err("bare `lorvex` triggers clap help display");
    assert_eq!(
        err.kind(),
        clap::error::ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand,
        "got {:?}",
        err.kind()
    );
    assert_eq!(err.exit_code(), 2);
}

#[test]
fn unknown_command_is_rejected() {
    let err = try_parse(&["weird"]).expect_err("unknown subcommands must fail parsing");
    assert_eq!(err.kind(), clap::error::ErrorKind::InvalidSubcommand);
}

#[test]
fn help_flag_exits_zero_with_help_display() {
    let err = try_parse(&["--help"]).expect_err("--help is a clap-emitted error");
    assert_eq!(err.kind(), clap::error::ErrorKind::DisplayHelp);
    assert!(err.exit_code() == 0);
}

#[test]
fn per_subcommand_help_is_available() {
    let err = try_parse(&["focus", "--help"]).expect_err("focus --help is clap DisplayHelp");
    assert_eq!(err.kind(), clap::error::ErrorKind::DisplayHelp);
    let rendered = err.to_string();
    // Per-subcommand help must mention the subcommand name, its
    // verbs, and at least one concrete example.
    assert!(
        rendered.contains("focus"),
        "missing 'focus' in help:\n{rendered}"
    );
    assert!(
        rendered.contains("set"),
        "missing 'set' in help:\n{rendered}"
    );
    assert!(
        rendered.contains("EXAMPLES:"),
        "missing EXAMPLES: in help:\n{rendered}"
    );
}

#[test]
fn version_flag_exits_zero() {
    let err = try_parse(&["--version"]).expect_err("--version is a clap-emitted error");
    assert_eq!(err.kind(), clap::error::ErrorKind::DisplayVersion);
    assert_eq!(err.exit_code(), 0);
}

#[test]
fn parse_completions_subcommand_accepts_each_shell() {
    // the `completions` subcommand must parse every
    // shell clap_complete supports. Clap's derive for `Shell`
    // exposes zsh/bash/fish/powershell/elvish — assert each
    // round-trips through the dispatch enum.
    assert_eq!(
        parse(&["completions", "zsh"]),
        Command::System(SystemCommand::Completions { shell: Shell::Zsh })
    );
    assert_eq!(
        parse(&["completions", "bash"]),
        Command::System(SystemCommand::Completions { shell: Shell::Bash })
    );
    assert_eq!(
        parse(&["completions", "fish"]),
        Command::System(SystemCommand::Completions { shell: Shell::Fish })
    );
    assert_eq!(
        parse(&["completions", "powershell"]),
        Command::System(SystemCommand::Completions {
            shell: Shell::PowerShell
        })
    );
    assert_eq!(
        parse(&["completions", "elvish"]),
        Command::System(SystemCommand::Completions {
            shell: Shell::Elvish
        })
    );
}

#[test]
fn completions_generate_emits_expected_shell_headers() {
    // Issue #2307 smoke test: the dispatcher in `main.rs` feeds
    // `ClapCli::command()` to `clap_complete::generate`. Reproduce
    // the same call here against a byte buffer so we can assert
    // each shell emits a recognizable header. This protects the
    // `main.rs` wiring from silently regressing (e.g. if someone
    // swapped the bin name or dropped the CommandFactory impl).
    use clap_complete::generate;

    let cases: &[(Shell, &[&str])] = &[
        // zsh: `#compdef <bin>` is the autoload header.
        (Shell::Zsh, &["#compdef lorvex"]),
        // bash: `complete -F _lorvex -o nosort -o bashdefault -o default lorvex`
        // lives near the bottom, but the generated script always
        // references the `_lorvex` completion function.
        (Shell::Bash, &["_lorvex"]),
        // fish: `complete -c lorvex` is emitted on every line.
        (Shell::Fish, &["complete -c lorvex"]),
        // powershell: the block opens with `Register-ArgumentCompleter`.
        (Shell::PowerShell, &["Register-ArgumentCompleter"]),
    ];

    for (shell, needles) in cases {
        let mut cmd = ClapCli::command();
        let mut buf: Vec<u8> = Vec::new();
        generate(*shell, &mut cmd, "lorvex", &mut buf);
        let script = String::from_utf8(buf).expect("completion script is UTF-8");
        for needle in *needles {
            assert!(
                script.contains(needle),
                "{shell:?} script missing needle {needle:?}:\n{script}"
            );
        }
    }
}

#[test]
fn short_flags_coverage() {
    // -l / -d / -n all parse identically to their long forms.
    assert_eq!(
        parse(&["today", "-l", "10"]),
        Command::Tasks(TasksCommand::Today {
            limit: 10,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["today"]),
        Command::Tasks(TasksCommand::Today {
            limit: 20,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["upcoming", "-d", "3"]),
        Command::Tasks(TasksCommand::Upcoming {
            days: 3,
            limit: 20,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "list",
            "update",
            "01900000-0000-7000-8001-000000000001",
            "-n",
            "Later"
        ]),
        Command::Lists(ListsCommand::Update {
            list_id: "01900000-0000-7000-8001-000000000001".to_string(),
            name: Some("Later".to_string()),
            color: Patch::Unset,
            icon: Patch::Unset,
            description: Patch::Unset,
            ai_notes: Patch::Unset,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn numeric_options_reject_zero_at_parse_time() {
    let cases: &[&[&str]] = &[
        &["search", "deep", "-l", "0"],
        &["today", "-l", "0"],
        &["overdue", "--limit", "0"],
        &["upcoming", "-d", "0"],
        &["upcoming", "-l", "0"],
        &["tasks", "-l", "0"],
        &["graph", "--limit-nodes", "0"],
        &["graph", "--limit-edges", "0"],
        &["deferred", "-l", "0"],
        &["changelog", "-l", "0"],
        &["reminder", "due", "-l", "0"],
        &["reminder", "upcoming", "--hours", "0"],
        &["reminder", "upcoming", "-l", "0"],
        &["list", "01900000-0000-7000-8001-000000000001", "-l", "0"],
        &["calendar", "list", "-l", "0"],
        &["defer", "01900000-0000-7000-8000-000000000001", "-d", "0"],
        &[
            "habit",
            "stats",
            "01900000-0000-7000-8002-000000000001",
            "-d",
            "0",
        ],
        &["habit", "create", "Run", "--target-count", "0"],
        &[
            "habit",
            "update",
            "01900000-0000-7000-8002-000000000001",
            "--target-count",
            "0",
        ],
    ];

    for args in cases {
        let err = try_parse(args).expect_err("non-positive numeric option should fail");
        assert_eq!(err.exit_code(), 2, "args were {args:?}");
        let rendered = err.to_string();
        assert!(
            rendered.contains("value must be >= 1"),
            "args were {args:?}; error was:\n{rendered}"
        );
    }
}

#[test]
fn top_level_help_mentions_verbose_and_format_flags() {
    // Issues #2309 + #2328: the new global flags MUST be discoverable
    // via `lorvex --help`. Without this check a future refactor that
    // trimmed the `after_help` string would silently regress the
    // user-facing documentation, leaving the flags undocumented.
    let err = try_parse(&["--help"]).expect_err("--help is a clap DisplayHelp");
    assert_eq!(err.kind(), clap::error::ErrorKind::DisplayHelp);
    let rendered = err.to_string();
    // Verbosity (#2309)
    assert!(
        rendered.contains("-v / --verbose"),
        "help missing -v / --verbose:\n{rendered}"
    );
    assert!(
        rendered.contains("-q / --quiet"),
        "help missing -q / --quiet:\n{rendered}"
    );
    assert!(
        rendered.contains("RUST_LOG"),
        "help missing RUST_LOG note:\n{rendered}"
    );
    // Format (#2328)
    assert!(
        rendered.contains("--format"),
        "help missing --format:\n{rendered}"
    );
    assert!(
        !rendered.contains("ndjson"),
        "help advertises unsupported ndjson format:\n{rendered}"
    );
    // Exit-code convention must be documented.
    assert!(
        rendered.contains("Exit codes"),
        "help missing Exit codes section:\n{rendered}"
    );
}

// --- parse coverage for the new MCP-mirror commands. -------

#[test]
fn parse_append_body_joins_multi_word_text() {
    assert_eq!(
        parse(&[
            "append-body",
            "01900000-0000-7000-8000-000000000001",
            "Reviewed",
            "the",
            "spec"
        ]),
        Command::Tasks(TasksCommand::AppendBody {
            task_id: "01900000-0000-7000-8000-000000000001".to_string(),
            text: "Reviewed the spec".to_string(),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_add_ai_notes_joins_multi_word_text() {
    assert_eq!(
        parse(&[
            "add-ai-notes",
            "01900000-0000-7000-8000-000000000002",
            "Plan",
            "revised"
        ]),
        Command::Tasks(TasksCommand::AddAiNotes {
            task_id: "01900000-0000-7000-8000-000000000002".to_string(),
            notes: "Plan revised".to_string(),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_recurrence_exception_add_and_remove() {
    assert_eq!(
        parse(&[
            "recurrence-exception",
            "add",
            "01900000-0000-7000-8000-000000000003",
            "2026-05-07"
        ]),
        Command::Tasks(TasksCommand::AddRecurrenceException {
            task_id: "01900000-0000-7000-8000-000000000003".to_string(),
            date: "2026-05-07".to_string(),
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "recurrence-exception",
            "remove",
            "01900000-0000-7000-8000-000000000003",
            "2026-05-07"
        ]),
        Command::Tasks(TasksCommand::RemoveRecurrenceException {
            task_id: "01900000-0000-7000-8000-000000000003".to_string(),
            date: "2026-05-07".to_string(),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_recurrence_exception_rejects_bad_date_at_parse_time() {
    let err = try_parse(&[
        "recurrence-exception",
        "add",
        "01900000-0000-7000-8000-000000000003",
        "not-a-date",
    ])
    .expect_err("malformed date");
    assert_eq!(err.kind(), clap::error::ErrorKind::ValueValidation);
}

#[test]
fn parse_error_logs_supports_source_and_limit() {
    assert_eq!(
        parse(&["error-logs"]),
        Command::System(SystemCommand::ErrorLogs {
            source: None,
            limit: 25,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["error-logs", "--source", "sync", "-l", "50"]),
        Command::System(SystemCommand::ErrorLogs {
            source: Some("sync".to_string()),
            limit: 50,
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_setup_status_and_setup_complete() {
    assert_eq!(
        parse(&["setup-status"]),
        Command::System(SystemCommand::SetupStatus {
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["setup-status"]),
        Command::System(SystemCommand::SetupStatus {
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&["setup-complete", "Onboarding", "complete"]),
        Command::System(SystemCommand::SetupComplete {
            summary: "Onboarding complete".to_string(),
            format: OutputFormat::Text,
        })
    );
}

#[test]
fn parse_calendar_search_threads_query_and_optional_range() {
    assert_eq!(
        parse(&["calendar", "search", "design", "review"]),
        Command::Calendar(CalendarCommand::Search {
            query: "design review".to_string(),
            from: None,
            to: None,
            limit: 25,
            format: OutputFormat::Text,
        })
    );
    assert_eq!(
        parse(&[
            "calendar",
            "search",
            "design",
            "--from",
            "2026-05-01",
            "--to",
            "2026-05-31",
            "-l",
            "10",
        ]),
        Command::Calendar(CalendarCommand::Search {
            query: "design".to_string(),
            from: Some("2026-05-01".to_string()),
            to: Some("2026-05-31".to_string()),
            limit: 10,
            format: OutputFormat::Text,
        })
    );
}
