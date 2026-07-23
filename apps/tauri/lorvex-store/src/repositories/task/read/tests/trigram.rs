use super::support::{
    insert_list, insert_task, search_tasks_with_fallback, test_conn, Pagination, SearchPredicate,
};

/// Functional: a 3+ character CJK substring query must go through
/// the trigram FTS5 table and still return every row whose title,
/// body or ai_notes contains the substring. The pin is parity
/// with the prior LIKE fallback, not a new match semantic.
///
/// Trigram note: the SQLite `trigram` tokenizer emits no tokens
/// for inputs shorter than 3 characters, so 1-2 character CJK
/// queries continue through the LIKE path; those are covered by
/// `search_cjk_uses_like_fallback` below.
#[test]
fn search_trigram_finds_cjk_substring_across_indexed_columns() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t-title",
        "写一个中文任务说明",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "t-body",
        "Shopping list",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "UPDATE tasks SET body = '周末去市场买草莓和其他水果 中文任务说明' WHERE id = 't-body'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "t-ai",
        "Weekly review",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "UPDATE tasks SET ai_notes = '中文任务说明 AI 备注' WHERE id = 't-ai'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "t-miss",
        "Unrelated",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    let pred = SearchPredicate {
        query: "中文任务".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    let ids: std::collections::HashSet<&str> =
        result.rows.iter().map(|r| r.core.id.as_str()).collect();
    assert_eq!(result.total_matching, 3);
    assert!(ids.contains("t-title"));
    assert!(ids.contains("t-body"));
    assert!(ids.contains("t-ai"));
    assert!(!ids.contains("t-miss"));
}

/// Ranking parity: the trigram path must preserve the existing
/// LIKE-path score order (exact title > title substring > body >
/// ai_notes). Without this, the CJK search UX would change visibly
/// when users upgrade past the fix.
#[test]
fn search_trigram_ranks_exact_title_above_body_above_ai_notes() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t-ai",
        "Weekly review",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "UPDATE tasks SET ai_notes = '项目进度 AI 备注' WHERE id = 't-ai'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "t-body",
        "Shopping list",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "UPDATE tasks SET body = '周末讨论项目进度' WHERE id = 't-body'",
        [],
    )
    .unwrap();
    insert_task(
        &conn,
        "t-title",
        "项目进度",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    let pred = SearchPredicate {
        query: "项目进度".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.rows.len(), 3);
    assert_eq!(result.rows[0].core.id, "t-title");
    assert_eq!(result.rows[1].core.id, "t-body");
    assert_eq!(result.rows[2].core.id, "t-ai");
}

/// Incremental sync: after a CJK task's title is updated through
/// the normal `UPDATE tasks ...` path, the trigram index triggers
/// must delete the stale trigram postings so the old text stops
/// matching and the new text starts matching.
#[test]
fn trigram_update_trigger_reindexes_on_title_change() {
    let conn = test_conn();
    insert_task(&conn, "t1", "周末买苹果", "open", None, None, Some(2), None);

    // 3+ char query routes through trigram so this test
    // exercises the index path specifically.
    let old_pred = SearchPredicate {
        query: "买苹果".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert_eq!(
        search_tasks_with_fallback(&conn, &old_pred, Pagination::default())
            .unwrap()
            .rows
            .len(),
        1,
    );

    conn.execute("UPDATE tasks SET title = '周末买香蕉' WHERE id = 't1'", [])
        .unwrap();

    // Old substring no longer matches.
    assert_eq!(
        search_tasks_with_fallback(&conn, &old_pred, Pagination::default())
            .unwrap()
            .rows
            .len(),
        0,
    );
    // New substring matches.
    let new_pred = SearchPredicate {
        query: "买香蕉".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert_eq!(
        search_tasks_with_fallback(&conn, &new_pred, Pagination::default())
            .unwrap()
            .rows
            .len(),
        1,
    );
}

/// Performance: issue #2288's headline claim is that CJK search
/// uses an index instead of a full table scan. With 5000 CJK-
/// titled tasks the old LIKE path was O(N) and visibly paused the
/// search bar per keystroke; the trigram index should complete
/// well inside one frame. We cap the assertion at 150 ms to
/// survive cold caches and loaded CI hosts while still catching
/// the regression where a bug reroutes CJK through the LIKE
/// fallback.
#[test]
fn search_trigram_handles_5000_cjk_tasks_quickly() {
    let conn = test_conn();
    // Seed 5000 CJK-titled tasks inside a single transaction with a
    // reused prepared statement so the test setup stays under a
    // second. Re-preparing the INSERT per row was the bulk of the
    // prior cost (debug-build trigram trigger fires on every insert).
    conn.execute_batch("BEGIN").unwrap();
    insert_list(&conn, "bench-list", "Bench");
    // Pool of distinct ideographs used round-robin so rows have
    // varied trigram postings (not a single repeated substring).
    let pool: Vec<char> = "任务项目计划想法笔记会议日程提醒目标工作学习练习阅读整理"
        .chars()
        .collect();
    {
        let mut stmt = conn
            .prepare(
                "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count) \
                 VALUES (?1, ?2, 'open', 'bench-list', '0000000000000_0000_0000000000000000', \
                         '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
            )
            .unwrap();
        for i in 0..5000u32 {
            let base = (i as usize) % pool.len();
            let title: String = (0..6).map(|j| pool[(base + j) % pool.len()]).collect();
            let id = format!("bench-{i:05}");
            stmt.execute(rusqlite::params![id, title]).unwrap();
        }
    }
    // Plant one title that deterministically contains the query.
    conn.execute(
        "UPDATE tasks SET title = '独特查询标记' WHERE id = 'bench-02500'",
        [],
    )
    .unwrap();
    conn.execute_batch("COMMIT").unwrap();

    // 3+ char query routes through trigram (the index whose
    // presence this test is meant to verify).
    let pred = SearchPredicate {
        query: "独特查询".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    // Warm up the statement cache: the first call pays prepare
    // cost, which is irrelevant to the scan-vs-index contract.
    let _ = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();

    let start = std::time::Instant::now();
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    let elapsed = start.elapsed();

    assert_eq!(result.total_matching, 1);
    assert_eq!(result.rows[0].core.id, "bench-02500");
    assert!(
        elapsed < std::time::Duration::from_millis(150),
        "trigram CJK search over 5000 rows should be index-backed, not full-scan; took {elapsed:?}",
    );
}
