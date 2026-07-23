use super::*;

/// Insert a minimal task for provider link tests.
fn insert_task_for_provider_test(conn: &Connection, id: &str) {
    // lift to canonical TaskBuilder.
    let title = format!("task-{id}");
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(&title)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-20T09:00:00Z")
        .insert(conn);
}

/// Insert a provider calendar event into the cache.
fn insert_provider_event(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
    title: &str,
) {
    conn.execute(
        "INSERT INTO provider_calendar_events (
            provider_kind, provider_scope, provider_event_key, title,
            start_date, all_day, last_seen_at, last_refreshed_at
        ) VALUES (?1, ?2, ?3, ?4, '2026-03-25', 0, ?5, ?5)",
        params![
            provider_kind,
            provider_scope,
            provider_event_key,
            title,
            "2026-03-25T09:00:00Z",
        ],
    )
    .expect("insert provider calendar event");
}

/// Insert a task-provider-event link.
fn insert_provider_link(
    conn: &Connection,
    task_id: &str,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) {
    conn.execute(
        "INSERT INTO task_provider_event_links (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
        params![task_id, provider_kind, provider_scope, provider_event_key, "2026-03-20T10:00:00Z"],
    )
    .expect("insert task_provider_event_links row");
}

/// Count rows in task_provider_event_links for a given task.
fn count_links(conn: &Connection, task_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM task_provider_event_links WHERE task_id = ?1",
        params![task_id],
        |row| row.get(0),
    )
    .expect("count links")
}

/// Run the same resolution query used by get_provider_event_links_for_task.
fn query_resolution_state(conn: &Connection, task_id: &str) -> Vec<(String, String)> {
    let mut stmt = conn
        .prepare(
            "SELECT tpl.provider_event_key,
                    CASE WHEN pce.provider_event_key IS NOT NULL THEN 'resolved' ELSE 'unresolved' END
             FROM task_provider_event_links tpl
             LEFT JOIN provider_calendar_events pce
               ON tpl.provider_kind = pce.provider_kind
              AND tpl.provider_scope = pce.provider_scope
              AND tpl.provider_event_key = pce.provider_event_key
             WHERE tpl.task_id = ?1
             ORDER BY tpl.created_at",
        )
        .expect("prepare resolution query");

    stmt.query_map(params![task_id], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })
    .expect("execute resolution query")
    .collect::<Result<Vec<_>, _>>()
    .expect("collect resolution rows")
}

// ─── Test 1: Provider links survive disable/enable + cache rebuild ───

#[test]
fn provider_links_survive_disable_enable_cache_rebuild() {
    let conn = setup_sync_test_conn();

    // 1. Insert a task
    insert_task_for_provider_test(&conn, "task-pl-1");

    // 2. Insert a provider event into cache
    insert_provider_event(&conn, "eventkit", "", "test-event-1", "Morning standup");

    // 3. Insert a link between task and provider event
    insert_provider_link(&conn, "task-pl-1", "eventkit", "", "test-event-1");

    // Verify initial state: link exists and resolves
    assert_eq!(count_links(&conn, "task-pl-1"), 1);
    let resolved = query_resolution_state(&conn, "task-pl-1");
    assert_eq!(resolved.len(), 1);
    assert_eq!(resolved[0].1, "resolved");

    // 4. Simulate "disable provider": DELETE all provider events for eventkit
    conn.execute(
        "DELETE FROM provider_calendar_events WHERE provider_kind = 'eventkit'",
        [],
    )
    .expect("delete provider events (simulate disable)");

    // 5. Verify: link row STILL exists (no FK cascade from provider cache to links)
    assert_eq!(
        count_links(&conn, "task-pl-1"),
        1,
        "Link must survive provider cache deletion — no FK cascade"
    );

    // The LEFT JOIN should now show 'unresolved'
    let after_delete = query_resolution_state(&conn, "task-pl-1");
    assert_eq!(after_delete.len(), 1);
    assert_eq!(after_delete[0].1, "unresolved");

    // 6. Simulate "re-enable provider": INSERT the same event back
    insert_provider_event(
        &conn,
        "eventkit",
        "",
        "test-event-1",
        "Morning standup (restored)",
    );

    // 7. Verify: LEFT JOIN resolves the link again
    let after_restore = query_resolution_state(&conn, "task-pl-1");
    assert_eq!(after_restore.len(), 1);
    assert_eq!(
        after_restore[0].1, "resolved",
        "Link must resolve again when provider event is re-inserted into cache"
    );
}
