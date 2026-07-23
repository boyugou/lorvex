use super::support::column_set;
use lorvex_store::open_db_in_memory;

/// pin the `tasks` column set so a schema refactor that
/// accidentally drops a column (say, `ai_notes` or `priority`) fails
/// at CI with a precise diff instead of silently losing user data.
#[test]
fn tasks_column_set_is_pinned() {
    let conn = open_db_in_memory().unwrap();
    let actual = column_set(&conn, "tasks");
    let expected: std::collections::BTreeSet<String> = [
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "due_date",
        "due_time",
        "priority",
        "estimated_minutes",
        "version",
        "recurrence",
        "recurrence_instance_key",
        "recurrence_group_id",
        "spawned_from",
        "canonical_occurrence_date",
        "created_at",
        "updated_at",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        // soft-delete / Trash. NULL = active, non-NULL ISO
        // timestamp = in Trash. Every read path filters `archived_at IS NULL`
        // inline so archived rows never surface outside the Trash view.
        "archived_at",
        // defer-until: NULL = always visible, else a date the task is
        // hidden from active lanes until (unless overdue).
        "available_from",
    ]
    .iter()
    .map(|s| (*s).to_string())
    .collect();
    assert_eq!(
        actual,
        expected,
        "tasks column set drifted. Missing: {missing:?}. Extra: {extra:?}. \
         Adding a column: update this test. Dropping a column: verify it's intentional \
         and migrate user data before shipping.",
        missing = expected.difference(&actual).collect::<Vec<_>>(),
        extra = actual.difference(&expected).collect::<Vec<_>>(),
    );
}

#[test]
fn ai_changelog_column_set_is_pinned() {
    let conn = open_db_in_memory().unwrap();
    let actual = column_set(&conn, "ai_changelog");
    let expected: std::collections::BTreeSet<String> = [
        "id",
        "timestamp",
        "operation",
        "entity_type",
        "entity_id",
        "summary",
        "initiated_by",
        "mcp_tool",
        "source_device_id",
        "before_json",
        "after_json",
        "undo_token",
        // typed boolean discriminator on preview-vs-real audit rows.
        "is_preview",
    ]
    .iter()
    .map(|s| (*s).to_string())
    .collect();
    assert_eq!(
        actual,
        expected,
        "ai_changelog column set drifted. Missing: {missing:?}. Extra: {extra:?}.",
        missing = expected.difference(&actual).collect::<Vec<_>>(),
        extra = actual.difference(&expected).collect::<Vec<_>>(),
    );
}
