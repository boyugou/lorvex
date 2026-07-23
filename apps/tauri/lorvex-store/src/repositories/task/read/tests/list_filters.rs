use super::support::{
    get_list_tasks_with_recent_completed, insert_list, insert_task, insert_task_with_completed,
    list_tasks, test_conn, BlockingFilter, DateFilter, ListTasksQuery, SortDirection,
    TaskListSortBy, TaskStatusListFilter,
};
use lorvex_domain::ListId;

fn lid(id: &str) -> ListId {
    ListId::from_trusted(id.to_string())
}

#[test]
fn list_tasks_filters_status_tags_text_and_counts_total() {
    let conn = test_conn();
    insert_task(
        &conn,
        "alpha",
        "Alpha roadmap",
        "open",
        Some("2026-03-24"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "beta",
        "Beta roadmap",
        "completed",
        Some("2026-03-25"),
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "gamma",
        "Gamma",
        "open",
        Some("2026-03-26"),
        None,
        Some(3),
        None,
    );
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-work', 'Work', 'work', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    for task_id in ["alpha", "beta"] {
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
             VALUES (?1, 'tag-work', \
                     '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
            [task_id],
        )
        .unwrap();
    }

    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            tags: vec!["work".to_string()],
            text: Some("road".to_string()),
            limit: 1,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();

    assert_eq!(result.total_matching, 2);
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].core.id, "alpha");
}

/// M4 regression — `list_tasks` text filter binds three positional
/// `?` placeholders for the same pattern (title / body / ai_notes
/// LIKE-fan). This test pins the contract that:
///   * each of the three columns matches against the SAME pattern
///     (a future SQL edit that swapped operands across the placeholders
///     would silently mis-bind without a test to catch it),
///   * matches are case-insensitive for ASCII (SQLite's `LIKE` is
///     ASCII-case-insensitive by default — the LIKE-fan does not need
///     to lowercase its operand because the SQL operator already does
///     so for the ASCII range),
///   * the LIKE pattern uses `\` as the escape character, and
///   * special LIKE metacharacters in the user input (`%`, `_`, `\`)
///     are escaped before being wrapped — a literal `100%` query must
///     not match arbitrary 100-prefixed text.
///
/// The text filter is the only LIKE-fan in `list_tasks`, so this test
/// is also the regression net for any future refactor that touches the
/// three-bind structure (e.g. switching to a single CTE, adding a
/// fourth column, or moving to a virtual table).
#[test]
fn list_tasks_text_filter_matches_title_body_and_ai_notes_with_escape() {
    let conn = test_conn();
    insert_task(
        &conn,
        "title-hit",
        "needle in title",
        "open",
        None,
        None,
        None,
        None,
    );
    insert_task(&conn, "body-hit", "boring", "open", None, None, None, None);
    conn.execute(
        "UPDATE tasks SET body = 'has a needle inside the body' WHERE id = 'body-hit'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "ainotes-hit",
        "boring",
        "open",
        None,
        None,
        None,
        None,
    );
    conn.execute(
        "UPDATE tasks SET ai_notes = 'AI sees a needle' WHERE id = 'ainotes-hit'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "miss",
        "haystack only",
        "open",
        None,
        None,
        None,
        None,
    );

    // Each of the three columns matches the same pattern.
    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            text: Some("needle".to_string()),
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let mut ids: Vec<String> = result.rows.iter().map(|r| r.core.id.clone()).collect();
    ids.sort();
    assert_eq!(
        ids,
        vec![
            "ainotes-hit".to_string(),
            "body-hit".to_string(),
            "title-hit".to_string(),
        ]
    );
    assert_eq!(result.total_matching, 3);

    // SQLite LIKE is ASCII-case-insensitive by default, so an
    // upper-case query must surface the same three rows.
    let upper = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            text: Some("NEEDLE".to_string()),
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert_eq!(upper.total_matching, 3);

    // Whitespace-only text input is treated as no filter (trim+empty).
    insert_task(&conn, "extra", "extra", "open", None, None, None, None);
    let blank = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            text: Some("   ".to_string()),
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert!(blank.rows.len() >= 4, "blank text must not filter");
}

/// M4 — LIKE metacharacters (`%`, `_`, `\`) in the user's text input
/// must be escaped before being wrapped in `%...%`, otherwise a
/// literal `100%` query would match every row whose body contains
/// "100" anywhere. The LIKE pattern carries `ESCAPE '\\'` in the SQL,
/// and `escape_like` prefixes the metacharacters with `\`.
#[test]
fn list_tasks_text_filter_escapes_like_metacharacters() {
    let conn = test_conn();
    insert_task(
        &conn,
        "exact",
        "we hit 100% coverage",
        "open",
        None,
        None,
        None,
        None,
    );
    insert_task(
        &conn,
        "false-positive",
        "we hit 1000 lines",
        "open",
        None,
        None,
        None,
        None,
    );

    // Literal "100%" must match only the row with the literal percent
    // character; the wildcard expansion must not trick "1000 lines" into
    // matching.
    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            text: Some("100%".to_string()),
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let ids: Vec<String> = result.rows.iter().map(|r| r.core.id.clone()).collect();
    assert_eq!(ids, vec!["exact".to_string()]);
    assert_eq!(result.total_matching, 1);
}

#[test]
fn list_tasks_filters_dependency_direction() {
    let conn = test_conn();
    insert_task(
        &conn,
        "blocker",
        "Blocker",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "blocked",
        "Blocked",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
         VALUES ('blocked', 'blocker', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let blocked = list_tasks(
        &conn,
        &ListTasksQuery {
            blocking: BlockingFilter::BlockedOnly,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let blockers = list_tasks(
        &conn,
        &ListTasksQuery {
            blocking: BlockingFilter::BlockingOthers,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();

    assert_eq!(blocked.rows[0].core.id, "blocked");
    assert_eq!(blockers.rows[0].core.id, "blocker");
}

#[test]
fn list_tasks_dependency_filters_ignore_archived_endpoints() {
    let conn = test_conn();
    insert_task(
        &conn,
        "archived-blocker",
        "Hidden blocker",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "blocked-visible",
        "Blocked visible",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "visible-blocker",
        "Visible blocker",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "archived-dependent",
        "Hidden dependent",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
         VALUES \
         ('blocked-visible', 'archived-blocker', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z'), \
         ('archived-dependent', 'visible-blocker', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-25T12:00:00.000Z' \
         WHERE id IN ('archived-blocker', 'archived-dependent')",
        [],
    )
    .unwrap();

    let blocked = list_tasks(
        &conn,
        &ListTasksQuery {
            blocking: BlockingFilter::BlockedOnly,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let blockers = list_tasks(
        &conn,
        &ListTasksQuery {
            blocking: BlockingFilter::BlockingOthers,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();

    assert!(
        blocked.rows.is_empty(),
        "visible tasks should not be blocked by Trash rows"
    );
    assert!(
        blockers.rows.is_empty(),
        "visible tasks should not count hidden Trash dependents"
    );
}

// -- DateFilter / BlockingFilter typed enum coverage

#[test]
fn list_tasks_due_presence_present_returns_only_dated_rows() {
    let conn = test_conn();
    insert_task(
        &conn,
        "with-due",
        "With due",
        "open",
        Some("2026-04-01"),
        None,
        Some(2),
        None,
    );
    insert_task(&conn, "no-due", "No due", "open", None, None, Some(2), None);

    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            due_presence: DateFilter::Present,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert_eq!(result.total_matching, 1);
    assert_eq!(result.rows[0].core.id, "with-due");
}

#[test]
fn list_tasks_due_presence_absent_returns_only_undated_rows() {
    let conn = test_conn();
    insert_task(
        &conn,
        "with-due",
        "With due",
        "open",
        Some("2026-04-01"),
        None,
        Some(2),
        None,
    );
    insert_task(&conn, "no-due", "No due", "open", None, None, Some(2), None);

    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            due_presence: DateFilter::Absent,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert_eq!(result.total_matching, 1);
    assert_eq!(result.rows[0].core.id, "no-due");
}

#[test]
fn list_tasks_planned_presence_filters_independently_of_due() {
    let conn = test_conn();
    insert_task(
        &conn,
        "planned",
        "Planned",
        "open",
        None,
        Some("2026-04-01"),
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "unplanned",
        "Unplanned",
        "open",
        Some("2026-04-01"),
        None,
        Some(2),
        None,
    );
    let present = list_tasks(
        &conn,
        &ListTasksQuery {
            planned_presence: DateFilter::Present,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let absent = list_tasks(
        &conn,
        &ListTasksQuery {
            planned_presence: DateFilter::Absent,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert_eq!(present.rows.len(), 1);
    assert_eq!(present.rows[0].core.id, "planned");
    assert_eq!(absent.rows.len(), 1);
    assert_eq!(absent.rows[0].core.id, "unplanned");
}

#[test]
fn list_tasks_blocking_filter_blocked_and_blocking_intersects_predicates() {
    // Create a 3-task chain: middle is BOTH blocked-by `top`
    // and a blocker-of `bottom`. Confirms the typed
    // `BlockingFilter::BlockedAndBlocking` arm intersects
    // (rather than unions) the two predicates.
    let conn = test_conn();
    insert_task(&conn, "top", "Top", "open", None, None, Some(1), None);
    insert_task(&conn, "middle", "Middle", "open", None, None, Some(2), None);
    insert_task(&conn, "bottom", "Bottom", "open", None, None, Some(3), None);
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES \
         ('middle', 'top', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z'), \
         ('bottom', 'middle', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let intersection = list_tasks(
        &conn,
        &ListTasksQuery {
            blocking: BlockingFilter::BlockedAndBlocking,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    assert_eq!(intersection.total_matching, 1);
    assert_eq!(intersection.rows[0].core.id, "middle");
}

#[test]
fn blocking_filter_from_flags_normalizes_legacy_pair() {
    assert_eq!(
        BlockingFilter::from_flags(false, false),
        BlockingFilter::Any
    );
    assert_eq!(
        BlockingFilter::from_flags(true, false),
        BlockingFilter::BlockedOnly
    );
    assert_eq!(
        BlockingFilter::from_flags(false, true),
        BlockingFilter::BlockingOthers
    );
    assert_eq!(
        BlockingFilter::from_flags(true, true),
        BlockingFilter::BlockedAndBlocking
    );
}

// -- get_today_tasks --

#[test]
fn list_tasks_includes_open_and_recent_completed() {
    let conn = test_conn();
    insert_list(&conn, "l1", "Work");
    insert_task_with_completed(&conn, "t1", "Open task", "open", "l1", None);
    insert_task_with_completed(
        &conn,
        "t2",
        "Completed in window",
        "completed",
        "l1",
        Some("2026-03-05T10:00:00Z"),
    );
    insert_task_with_completed(
        &conn,
        "t3",
        "Completed before window",
        "completed",
        "l1",
        Some("2026-02-25T10:00:00Z"),
    );
    insert_task_with_completed(&conn, "t4", "Cancelled task", "cancelled", "l1", None);
    insert_task_with_completed(&conn, "t5", "Someday task", "someday", "l1", None);

    let result = get_list_tasks_with_recent_completed(
        &conn,
        &lid("l1"),
        "2026-03-01T00:00:00Z",
        "2026-03-08T00:00:00Z",
        1000,
    )
    .unwrap();
    let ids: Vec<&str> = result.rows.iter().map(|t| t.core.id.as_str()).collect();

    assert!(ids.contains(&"t1"), "open task should appear");
    assert!(ids.contains(&"t2"), "recently completed should appear");
    assert!(!ids.contains(&"t3"), "old completed should not appear");
    assert!(!ids.contains(&"t4"), "cancelled should not appear");
    assert!(ids.contains(&"t5"), "someday task should appear");
    assert_eq!(
        result.total_matching, 3,
        "total_matching must reflect the predicate count, not the limit"
    );
}

/// when the row count exceeds the cap, `rows.len() <=
/// limit` must hold while `total_matching` keeps reporting the full
/// predicate count. Without this, a 50k-task list would re-marshal
/// every row over IPC on every list-detail open. The repository must
/// trim before serialization, and the UI gets the budget separately.
#[test]
fn list_tasks_trims_rows_to_limit_and_reports_full_count() {
    let conn = test_conn();
    insert_list(&conn, "l-big", "Big list");
    for i in 0..5 {
        insert_task_with_completed(
            &conn,
            &format!("t-big-{i}"),
            &format!("Open {i}"),
            "open",
            "l-big",
            None,
        );
    }

    let result = get_list_tasks_with_recent_completed(
        &conn,
        &lid("l-big"),
        "2026-03-01T00:00:00Z",
        "2026-03-08T00:00:00Z",
        2,
    )
    .unwrap();
    assert_eq!(result.rows.len(), 2, "rows must be trimmed to limit");
    assert_eq!(
        result.total_matching, 5,
        "total_matching must report full predicate count for load-more"
    );
}

#[test]
fn list_tasks_excludes_other_lists() {
    let conn = test_conn();
    insert_list(&conn, "l1", "Work");
    insert_list(&conn, "l2", "Home");
    insert_task_with_completed(&conn, "t1", "Work task", "open", "l1", None);
    insert_task_with_completed(&conn, "t2", "Home task", "open", "l2", None);

    let result = get_list_tasks_with_recent_completed(
        &conn,
        &lid("l1"),
        "2026-03-01T00:00:00Z",
        "2026-03-08T00:00:00Z",
        1000,
    )
    .unwrap();
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].core.id, "t1");
    assert_eq!(result.total_matching, 1);
}

// ------------------------------------------------------------------
// trigram FTS index for CJK search

// ----------------------------------------------------------------------
// `priority_effective DESC` must keep unprioritized
// tasks LAST. The generated column carries sentinel `4` for NULL
// priority; under DESC the sentinel sorted FIRST pre-fix, putting
// every unprioritized task ahead of the most important real-priority
// rows. The fix wraps the column in `NULLIF(_, 4)` so `NULLS LAST`
// sweeps the sentinel to the tail under either direction.
// ----------------------------------------------------------------------

#[test]
fn priority_due_desc_pushes_unprioritized_last() {
    let conn = test_conn();
    insert_task(&conn, "p1", "P1", "open", None, None, Some(1), None);
    insert_task(&conn, "p2", "P2", "open", None, None, Some(2), None);
    insert_task(&conn, "p3", "P3", "open", None, None, Some(3), None);
    insert_task(&conn, "px", "PX", "open", None, None, None, None);

    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            sort_by: TaskListSortBy::PriorityDue,
            sort_direction: SortDirection::Desc,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();

    let ids: Vec<&str> = result.rows.iter().map(|t| t.core.id.as_str()).collect();
    // DESC: priority 3 first (highest numeric value), then 2, then 1,
    // then unprioritized (px) — never first. Pre-fix, the sentinel
    // value 4 placed `px` at the head of the list.
    assert_eq!(
        ids,
        vec!["p3", "p2", "p1", "px"],
        "unprioritized must sort last under DESC, but \
         the priority_effective sentinel `4` was pushing it first",
    );
}

#[test]
fn priority_due_asc_keeps_unprioritized_last() {
    // Sanity check: ASC ordering — which already worked pre-fix —
    // must remain stable under the `NULLIF` rewrite.
    let conn = test_conn();
    insert_task(&conn, "p1", "P1", "open", None, None, Some(1), None);
    insert_task(&conn, "p2", "P2", "open", None, None, Some(2), None);
    insert_task(&conn, "px", "PX", "open", None, None, None, None);

    let result = list_tasks(
        &conn,
        &ListTasksQuery {
            status: TaskStatusListFilter::All,
            sort_by: TaskListSortBy::PriorityDue,
            sort_direction: SortDirection::Asc,
            ..ListTasksQuery::default()
        },
    )
    .unwrap();
    let ids: Vec<&str> = result.rows.iter().map(|t| t.core.id.as_str()).collect();
    assert_eq!(ids, vec!["p1", "p2", "px"]);
}
