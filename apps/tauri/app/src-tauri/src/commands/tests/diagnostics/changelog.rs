use super::support::*;

// The dedicated feedback IPC surface
// (`get_feedback_entries`, `clear_feedback_entries`,
// `export_feedback_entries`) was removed because no caller in the
// renderer ever wired up to it. Feedback is handled through GitHub issues;
// app diagnostics now use the generic changelog surface only. The
// `feedback_filters_match_only_structured_feedback_rows` test that pinned
// the now-deleted helpers + WHERE-clause sentinel is gone
// with them.

#[test]
fn ai_changelog_filters_human_actor_aliases() {
    let conn = setup_sync_test_conn();
    let insert_sql =
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
         VALUES (?1, ?2, 'update', 'task', NULL, ?3, ?4, NULL)";

    conn.execute(
        insert_sql,
        params!["ai-1", "2026-03-03T10:00:00Z", "AI entry", "codex"],
    )
    .expect("insert ai entry");
    conn.execute(
        insert_sql,
        params!["human-1", "2026-03-03T10:01:00Z", "Human entry", "human"],
    )
    .expect("insert human entry");
    conn.execute(
        insert_sql,
        params!["user-1", "2026-03-03T10:02:00Z", "User entry", "user"],
    )
    .expect("insert user entry");
    conn.execute(
        insert_sql,
        params!["manual-1", "2026-03-03T10:03:00Z", "Manual entry", "manual"],
    )
    .expect("insert manual entry");
    conn.execute(
        insert_sql,
        params!["ai-2", "2026-03-03T10:04:00Z", "AI entry 2", "kimi"],
    )
    .expect("insert second ai entry");

    let rows = read_ai_changelog_entries(&conn, 50).expect("read ai changelog");
    let ids: Vec<String> = rows
        .iter()
        .filter_map(|row| {
            row.get("id")
                .and_then(|value| value.as_str())
                .map(std::string::ToString::to_string)
        })
        .collect();

    assert_eq!(ids, vec!["ai-2".to_string(), "ai-1".to_string()]);
}

/// #2513: per-task History section. Asserts the `entity_id` filter on
/// `read_ai_changelog_entries_filtered` narrows the result set to rows
/// mutating the specified entity only, preserves newest-first ordering,
/// and treats empty / whitespace inputs as "no filter" (mirrors the
/// since_iso and source_device_id filters' contract).
#[test]
fn ai_changelog_entity_id_filter_narrows_to_one_entity() {
    let conn = setup_sync_test_conn();
    let insert_sql =
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
         VALUES (?1, ?2, 'update', 'task', ?3, ?4, 'codex', NULL)";

    conn.execute(
        insert_sql,
        params!["a-older", "2026-04-01T10:00:00Z", "task-a", "older A"],
    )
    .expect("insert older task-a entry");
    conn.execute(
        insert_sql,
        params!["b-middle", "2026-04-02T10:00:00Z", "task-b", "task-b entry"],
    )
    .expect("insert task-b entry");
    conn.execute(
        insert_sql,
        params!["a-newer", "2026-04-03T10:00:00Z", "task-a", "newer A"],
    )
    .expect("insert newer task-a entry");

    // Narrow to task-a: only matching rows, newest first.
    let rows =
        read_ai_changelog_entries_for_entity(&conn, 50, "task-a").expect("filter by entity_id");
    let ids: Vec<String> = rows
        .iter()
        .filter_map(|row| {
            row.get("id")
                .and_then(|value| value.as_str())
                .map(std::string::ToString::to_string)
        })
        .collect();
    assert_eq!(
        ids,
        vec!["a-newer".to_string(), "a-older".to_string()],
        "entity_id filter must return only task-a rows, newest first"
    );

    // Empty / whitespace filter is a no-op: returns every row.
    let all = read_ai_changelog_entries_for_entity(&conn, 50, "   ").expect("empty filter no-op");
    assert_eq!(
        all.len(),
        3,
        "empty filter must return all rows, got {}",
        all.len()
    );

    // A never-written entity_id yields zero rows.
    let none = read_ai_changelog_entries_for_entity(&conn, 50, "task-zzz").expect("unknown entity");
    assert!(none.is_empty(), "unknown entity_id should return no rows");
}
