use super::*;

#[test]
fn capture_structured_fields_validate_at_parse_time() {
    let cases: &[&[&str]] = &[
        &["capture", "Task", "--priority", "4"],
        &["capture", "Task", "--due-date", "2026-02-30"],
        &["capture", "Task", "--planned-date", "04/30/2026"],
        &["capture", "Task", "--estimated-minutes", "-1"],
        &["capture", "Task", "--estimated-minutes", "1441"],
        &["capture", "Task", "--tag", ""],
    ];

    for args in cases {
        let err = try_parse(args).expect_err("invalid capture field should fail");
        assert_eq!(err.exit_code(), 2, "args were {args:?}");
    }
}

/// clap rejects malformed UUID-shaped IDs at the
/// trust boundary across every CLI surface that takes a `task id`,
/// `list id`, `event id`, `habit id`, `policy id`, `annotation id`,
/// `revision id`, or `reminder id` argument. Pre-fix every site
/// (except `parse_dependency_id`) accepted any string, so a typo
/// flowed all the way to the repository layer where it surfaced as
/// a confusing "task not found" / SQL FK error instead of a clap
/// usage error with a known exit code (2).
///
/// Tests every UUID-validated arg with a representative bad input
/// (`"not-a-uuid"`) so a regression that drops `value_parser =
/// parse_uuid_id(_, "<field>")` from any one of them surfaces here
/// as a missing `expect_err`.
#[test]
fn uuid_id_args_reject_non_uuid_strings_at_parse_time() {
    let cases: &[&[&str]] = &[
        // task.rs
        &["show", "not-a-uuid"],
        &["move", "01900000-0000-7000-8001-000000000001", "not-a-uuid"],
        &["move", "not-a-uuid", "01900000-0000-7000-8000-000000000001"],
        &["update", "not-a-uuid", "--title", "x"],
        &["complete", "not-a-uuid"],
        &["reopen", "not-a-uuid"],
        &["cancel", "not-a-uuid"],
        &["defer", "not-a-uuid", "-d", "1"],
        &["tasks", "--list", "not-a-uuid"],
        &["graph", "--task-id", "not-a-uuid"],
        &["deferred", "--list", "not-a-uuid"],
        &["capture", "Task", "--list", "not-a-uuid"],
        &["append-body", "not-a-uuid", "more"],
        &["add-ai-notes", "not-a-uuid", "more"],
        &["recurrence-exception", "add", "not-a-uuid", "2026-05-01"],
        // calendar.rs
        &["calendar", "show", "not-a-uuid"],
        &["calendar", "delete", "not-a-uuid"],
        &[
            "calendar",
            "link",
            "not-a-uuid",
            "01900000-0000-7000-8000-000000000001",
        ],
        &[
            "calendar",
            "unlink",
            "not-a-uuid",
            "01900000-0000-7000-8000-000000000001",
        ],
        &["calendar", "links-for-task", "not-a-uuid"],
        &["calendar", "add-exception", "not-a-uuid", "2026-05-01"],
        &[
            "calendar",
            "provider-link",
            "not-a-uuid",
            "--provider-kind",
            "eventkit",
            "--provider-event-key",
            "ek-1",
        ],
        &["calendar", "update", "not-a-uuid", "--title", "x"],
        // habit.rs
        &["habit", "update", "not-a-uuid", "-n", "name"],
        &["habit", "delete", "not-a-uuid"],
        &["habit", "complete", "not-a-uuid"],
        &["habit", "batch-complete", "not-a-uuid"],
        &["habit", "uncomplete", "not-a-uuid"],
        &["habit", "stats", "not-a-uuid"],
        &["habit", "reminder", "upsert", "not-a-uuid", "09:00"],
        &["habit", "reminder", "delete", "not-a-uuid"],
        // list.rs
        &["list", "not-a-uuid"],
        &["list", "update", "not-a-uuid"],
        &["list", "delete", "not-a-uuid"],
        // reminder.rs
        &[
            "reminder",
            "set",
            "not-a-uuid",
            "--at",
            "2026-05-01T09:00:00Z",
        ],
        &["reminder", "clear", "not-a-uuid"],
        &["reminder", "add", "not-a-uuid", "2026-05-01T09:00:00Z"],
        &[
            "reminder",
            "remove",
            "not-a-uuid",
            "01900000-0000-7000-8004-000000000001",
        ],
        &[
            "reminder",
            "remove",
            "01900000-0000-7000-8000-000000000001",
            "not-a-uuid",
        ],
        // focus.rs
        &["focus", "set", "not-a-uuid"],
        &["focus", "add", "not-a-uuid"],
        &["focus", "remove", "not-a-uuid"],
        // memory.rs
        &["memory", "restore", "not-a-uuid"],
        // trash.rs
        &["trash", "move", "not-a-uuid"],
        &["trash", "restore", "not-a-uuid"],
        &["trash", "delete", "not-a-uuid", "--dry-run"],
        // review.rs
        &[
            "review",
            "add",
            "--summary",
            "S",
            "--linked-task",
            "not-a-uuid",
        ],
        &[
            "review",
            "add",
            "--summary",
            "S",
            "--linked-list",
            "not-a-uuid",
        ],
        &[
            "review",
            "amend",
            "2026-06-01",
            "--linked-task-set",
            "not-a-uuid",
        ],
    ];

    for args in cases {
        let err = try_parse(args).expect_err("invalid UUID arg should fail at parse time");
        assert_eq!(
            err.exit_code(),
            2,
            "args were {args:?}; expected clap usage error (exit 2)"
        );
    }
}

/// the schema-seeded `inbox` sentinel list id is
/// the canonical default list and must remain accepted by every
/// `list id`-shaped argument even though it is not UUID-shaped.
/// Other ID-shaped fields (`task id`, `event id`, etc.) have no
/// equivalent sentinel and continue to require a UUID.
#[test]
fn list_id_args_accept_inbox_sentinel() {
    let inputs: &[&[&str]] = &[
        &["list", "inbox"],
        &["list", "update", "inbox"],
        &["list", "delete", "inbox"],
        &["tasks", "--list", "inbox"],
        &["deferred", "--list", "inbox"],
        &["capture", "Title", "--list", "inbox"],
        &["review", "add", "--summary", "S", "--linked-list", "inbox"],
    ];

    for args in inputs {
        try_parse(args).unwrap_or_else(|err| {
            panic!("inbox sentinel should be accepted; args {args:?} produced clap error: {err}")
        });
    }
}
