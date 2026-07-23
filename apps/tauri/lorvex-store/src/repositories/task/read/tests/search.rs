use super::support::{
    insert_task, search_tasks, search_tasks_with_fallback, test_conn, Pagination, SearchPredicate,
};

#[test]
fn search_finds_by_title() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Buy groceries",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Write report",
        "open",
        None,
        None,
        Some(1),
        None,
    );

    let pred = SearchPredicate {
        query: "groceries".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let tasks = search_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].core.id, "t1");
}

#[test]
fn search_empty_query_returns_empty() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Buy groceries",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    let pred = SearchPredicate {
        query: String::new(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let tasks = search_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert!(tasks.is_empty());
}

#[test]
fn search_with_status_filter() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Buy groceries",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Buy milk",
        "completed",
        None,
        None,
        Some(1),
        None,
    );

    let pred = SearchPredicate {
        query: "Buy".into(),
        status_filter: Some(vec!["open".into()]),
        list_filter: None,
        tag_filter: None,
    };
    let tasks = search_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].core.id, "t1");
}

/// pin the ranking contract documented on
/// `search_tasks`. Status IS the primary sort; BM25 is the
/// within-bucket tiebreaker. A completed task with a perfect
/// title match must still rank BELOW an open task whose match
/// is weaker. If a future change flips to `bm25 * multiplier`
/// this test and the docstring must update together.
#[test]
fn search_ranks_status_primary_over_bm25() {
    let conn = test_conn();
    // Completed task: the title is a perfect exact-term match
    // for the query ("weekly-report"). Under a pure-BM25 ranking
    // this would score higher than the open task.
    insert_task(
        &conn,
        "completed-exact",
        "weekly-report",
        "completed",
        None,
        None,
        Some(1),
        None,
    );
    // Open task: the title only mentions the query term once
    // alongside other text, so its BM25 score is weaker.
    insert_task(
        &conn,
        "open-diluted",
        "Misc notes and the weekly-report attachment link",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    let pred = SearchPredicate {
        query: "weekly-report".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let tasks = search_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(tasks.len(), 2);
    assert_eq!(
        tasks[0].core.id, "open-diluted",
        "status-open must rank before status-completed regardless of BM25; \
         the docstring's 'status primary, BM25 secondary' contract is pinned here",
    );
    assert_eq!(tasks[1].core.id, "completed-exact");
}

/// the LIKE fallback — the only search path available
/// for CJK queries — used to return matches in whatever incidental
/// ORDER BY the caller supplied, so a title-exact match was
/// indistinguishable from a hit buried in a long body. Pin that an
/// exact title match (weight 100) outranks a body-only hit
/// (weight 10) for a CJK query. Exercises the fallback end-to-end
/// via `search_tasks_with_fallback`: "草莓" contains no ASCII
/// alphanumerics, so `should_use_like_fallback` returns true and
/// FTS is skipped entirely.
#[test]
fn search_like_fallback_ranks_exact_title_match_above_body_match() {
    let conn = test_conn();
    // Loser: body mentions the query, title does not.
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
        "UPDATE tasks SET body = '周末去市场买草莓和其他水果' WHERE id = 't-body'",
        [],
    )
    .unwrap();
    // Winner: title is exactly the query (score 100 + 50).
    insert_task(&conn, "t-title", "草莓", "open", None, None, Some(2), None);

    let pred = SearchPredicate {
        query: "草莓".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.total_matching, 2);
    assert_eq!(result.rows.len(), 2);
    assert_eq!(
        result.rows[0].core.id, "t-title",
        "exact title match (weight 100) must outrank body-only match (weight 10)",
    );
    assert_eq!(result.rows[1].core.id, "t-body");
}

/// title substring (weight 50) must rank above an
/// `ai_notes`-only substring (weight 5). Uses a CJK query so the
/// fallback path is guaranteed — and because `ai_notes` is AI-only
/// content (core rule 6), users searching their own task titles
/// must not be drowned out by long AI notes on unrelated tasks.
#[test]
fn search_like_fallback_ranks_title_above_ai_notes() {
    let conn = test_conn();
    // Loser: ai_notes mentions the query, title and body do not.
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
        "UPDATE tasks SET ai_notes = 'User mentioned 項目 priorities during standup.' \
         WHERE id = 't-ai'",
        [],
    )
    .unwrap();
    // Winner: title contains the query as a substring (score 50).
    insert_task(
        &conn,
        "t-title",
        "項目 kickoff agenda",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    let pred = SearchPredicate {
        query: "項目".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.total_matching, 2);
    assert_eq!(result.rows.len(), 2);
    assert_eq!(
        result.rows[0].core.id, "t-title",
        "title substring (weight 50) must outrank ai_notes substring (weight 5)",
    );
    assert_eq!(result.rows[1].core.id, "t-ai");
}

/// tag display_names are now an indexed FTS column,
/// so a Latin-script query that matches ONLY through a task's tag
/// (not its title/body/ai_notes) must still hit the FTS path.
///
/// This test asserts two things in tandem:
///  1. `search_tasks_with_fallback` returns the tagged task.
///  2. It returns it via FTS (not the LIKE fallback). The FTS
///     path is gated on `should_use_like_fallback(query) == false`,
///     which for the pure-ASCII query `"budget"` is always false
///     — so reaching a result through `search_tasks` (which is
///     the FTS-only entrypoint) proves the tag made it into the
///     FTS shadow.
#[test]
fn search_fts_matches_tag_display_name() {
    let conn = test_conn();
    // Task whose title/body/ai_notes contain no "budget" — only
    // the tag does.
    insert_task(
        &conn,
        "t1",
        "Q2 planning session",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    // Seed a tag and link it to the task. The display_name is
    // what we expect FTS to index.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-budget', 'budget', 'budget', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES ('t1', 'tag-budget', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    // FTS-only entrypoint: if `search_tasks` returns the row,
    // the tag display_name made it into the FTS shadow.
    let pred = SearchPredicate {
        query: "budget".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let rows = search_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(
        rows.len(),
        1,
        "FTS should find the task via its #budget tag"
    );
    assert_eq!(rows[0].core.id, "t1");

    // And the public fallback-aware entrypoint agrees (and goes
    // through FTS for a pure-ASCII query).
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].core.id, "t1");
    assert_eq!(result.total_matching, 1);
}

/// drift guard for #3307 T2-3 — the trigram FTS shadow indexes only
/// task title/body/ai_notes, so a CJK substring that matches ONLY a
/// tag's display_name has to come back through the tag-LIKE OR
/// branch in `trigram.rs::search_tasks_trigram_counted`. Without this
/// branch the user could attach `预算` as a tag, then search for
/// `预算` and get an empty result while their tagged task hides.
///
/// This test walks the same end-to-end seam as the FTS-side
/// `search_fts_matches_tag_display_name` (above) but on the trigram
/// path so the CJK + tag-only-match shape is also pinned.
#[test]
fn search_trigram_matches_cjk_tag_display_name() {
    let conn = test_conn();
    // Task whose title/body/ai_notes contain no CJK character —
    // only the tag does.
    insert_task(
        &conn,
        "t1",
        "Q2 planning session",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    // Seed a tag with a 3+ character CJK display_name so the trigram
    // tokenizer has enough characters to index. SQLite's trigram
    // tokenizer drops shorter strings; the tag-LIKE OR branch of the
    // trigram path is the surface that covers the tag-name match.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-budget-cjk', '预算管理', '预算管理', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES ('t1', 'tag-budget-cjk', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    // CJK substring — 3 chars satisfies the trigram tokenizer's
    // minimum and `should_use_like_fallback` would otherwise leave
    // CJK in the LIKE path. The fallback-aware entrypoint must
    // return the task via the trigram tag-LIKE OR branch.
    let pred = SearchPredicate {
        query: "预算管".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(
        result.rows.len(),
        1,
        "CJK substring of tag display_name must surface the tagged task via the trigram path"
    );
    assert_eq!(result.rows[0].core.id, "t1");
    assert_eq!(result.total_matching, 1);
}

/// renaming a tag must re-index the FTS column so
/// searches for the new name start hitting, and searches for the
/// old name stop hitting.
#[test]
fn fts_tag_rename_refreshes_indexed_text() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Planning session",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-old', 'oldname', 'oldname', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES ('t1', 'tag-old', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let pred_old = SearchPredicate {
        query: "oldname".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert_eq!(
        search_tasks(&conn, &pred_old, Pagination::default())
            .unwrap()
            .len(),
        1,
        "initial tag name should be indexed"
    );

    // Rename the tag.
    conn.execute(
        "UPDATE tags SET display_name = 'newname' WHERE id = 'tag-old'",
        [],
    )
    .unwrap();

    // Old name no longer matches.
    assert_eq!(
        search_tasks(&conn, &pred_old, Pagination::default())
            .unwrap()
            .len(),
        0,
        "renamed tag must no longer match the old name via FTS"
    );
    // New name matches.
    let pred_new = SearchPredicate {
        query: "newname".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert_eq!(
        search_tasks(&conn, &pred_new, Pagination::default())
            .unwrap()
            .len(),
        1,
        "renamed tag must match the new name via FTS"
    );
}

/// unlinking a tag must remove it from the FTS
/// column so the task no longer matches the tag name.
#[test]
fn fts_tag_unlink_removes_from_index() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Planning session",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-budget', 'budget', 'budget', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES ('t1', 'tag-budget', \
                 '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let pred = SearchPredicate {
        query: "budget".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert_eq!(
        search_tasks(&conn, &pred, Pagination::default())
            .unwrap()
            .len(),
        1,
        "task should match via tag before unlink"
    );

    conn.execute(
        "DELETE FROM task_tags WHERE task_id = 't1' AND tag_id = 'tag-budget'",
        [],
    )
    .unwrap();

    assert_eq!(
        search_tasks(&conn, &pred, Pagination::default())
            .unwrap()
            .len(),
        0,
        "task should no longer match via tag after unlink"
    );
}

#[test]
fn search_cjk_uses_like_fallback() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "写一个中文任务",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Buy groceries",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    // Substring search for "中文" should find t1 via LIKE fallback.
    let pred = SearchPredicate {
        query: "中文".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].core.id, "t1");
    assert_eq!(result.total_matching, 1);
}

#[test]
fn search_cjk_mixed_script_query() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "完成 report",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Buy groceries",
        "open",
        None,
        None,
        Some(2),
        None,
    );

    // Mixed CJK+Latin query routes through LIKE.
    let pred = SearchPredicate {
        query: "完成".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    let result = search_tasks_with_fallback(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(result.rows.len(), 1);
    assert_eq!(result.rows[0].core.id, "t1");
}
