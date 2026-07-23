use super::*;
use crate::commands::tasks::{
    apply_single_undo_for_tests, complete_task_with_conn_inner, quick_capture_with_conn,
    update_task_inner_with_conn, QuickCaptureRequest, UndoToken,
};

#[test]
fn create_update_complete_undo_restores_post_edit_state_and_keeps_sync_projections_consistent() {
    let conn = setup_sync_test_conn();

    let created = quick_capture_with_conn(
        &conn,
        QuickCaptureRequest {
            title: "Draft spec".to_string(),
            priority: Some(3),
            body: Some("Initial body".to_string()),
            ..QuickCaptureRequest::default()
        },
    )
    .expect("create task through command body");
    let created_version = created.version.clone();

    let updated = update_task_inner_with_conn(
        &conn,
        &created.id,
        &json!({
            "title": "Finalize spec",
            "body": "Edited body",
            "due_date": "2026-04-30",
            "priority": 1
        }),
    )
    .expect("update task through command body");
    assert!(
        !updated.undo_token.is_empty(),
        "update should emit an undo token"
    );
    let updated_task = updated.task;
    let updated_version = updated_task.version.clone();
    let _update_undo: UndoToken =
        serde_json::from_str(&updated.undo_token).expect("parse update undo token");
    // The undo token cache is keyed by task id, so the freshly minted
    // update token is discoverable for the task right after the update.
    assert_eq!(
        crate::commands::diagnostics::undo_token_cache::lookup(&created.id),
        Some(updated.undo_token.clone()),
        "update undo token should be discoverable by task id while the window is live"
    );

    let (completed, _spotlight_ids) = complete_task_with_conn_inner(&conn, &created.id)
        .expect("complete task through command body");
    assert!(
        !completed.undo_token.is_empty(),
        "complete should emit an undo token"
    );
    let completed_task = completed.task;
    let completed_version = completed_task.version;
    let undo: UndoToken =
        serde_json::from_str(&completed.undo_token).expect("parse completion undo token");
    // Completing the same task overwrites the cache entry: the task-id
    // key now resolves to the completion token, matching the single
    // "undo the latest mutation" affordance the toast offers.
    assert_eq!(
        crate::commands::diagnostics::undo_token_cache::lookup(&created.id),
        Some(completed.undo_token.clone()),
        "completion undo token should replace the update token for the same task id"
    );
    let ai_changelog_count_before_undo: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count ai_changelog rows before undo");
    assert_eq!(
        ai_changelog_count_before_undo, 0,
        "Tauri lifecycle writes should not persist AI changelog rows"
    );

    let restored = apply_single_undo_for_tests(&conn, &undo, "2026-04-19T12:00:05.000000Z")
        .expect("undo completion through command body");
    let restored_version = restored.version.clone();

    assert!(
        created_version < updated_version
            && updated_version < completed_version
            && completed_version < restored_version,
        "task versions should remain strictly monotonic across create -> update -> complete -> undo"
    );

    assert_eq!(restored.id, updated_task.id);
    assert_eq!(restored.title, updated_task.title);
    assert_eq!(restored.body, updated_task.body);
    assert_eq!(restored.priority, updated_task.priority);
    assert_eq!(restored.due_date, updated_task.due_date);
    assert_eq!(restored.status, updated_task.status);
    assert_eq!(restored.completed_at, None);
    assert_eq!(restored.list_id, updated_task.list_id);

    let stored = fetch_task_by_id(&conn, &created.id).expect("reload restored task");
    assert_eq!(stored.title, updated_task.title);
    assert_eq!(stored.body, updated_task.body);
    assert_eq!(stored.priority, updated_task.priority);
    assert_eq!(stored.due_date, updated_task.due_date);
    assert_eq!(stored.status, "open");
    assert_eq!(stored.completed_at, None);

    let ai_changelog_count_after_undo: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count ai_changelog rows after undo");
    assert_eq!(
        ai_changelog_count_after_undo, 0,
        "undoing a Tauri lifecycle mutation should also leave AI changelog empty"
    );

    let fts_projection: (String, String, Option<String>) = conn
        .query_row(
            "SELECT t.title, f.title, t.body
             FROM tasks t
             JOIN tasks_fts f ON f.rowid = t.rowid
             WHERE t.id = ?1",
            params![created.id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("fts projection for restored task");
    assert_eq!(
        fts_projection.0, fts_projection.1,
        "tasks_fts title should stay aligned with tasks after undo"
    );
    assert_eq!(
        fts_projection.0, restored.title,
        "fts row should index the restored title"
    );
    assert_eq!(
        fts_projection.2,
        Some("Edited body".to_string()),
        "stored body should match the post-edit state restored by undo"
    );

    let task_outbox_rows: Vec<(i64, String)> = {
        let mut stmt = conn
            .prepare(
                "SELECT id, version
                 FROM sync_outbox
                 WHERE entity_type = 'task' AND entity_id = ?1 AND synced_at IS NULL
                 ORDER BY id ASC",
            )
            .expect("prepare outbox query");
        let rows: rusqlite::Result<Vec<_>> = stmt
            .query_map(params![created.id], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .expect("query task outbox rows")
            .collect();
        rows.expect("collect task outbox rows")
    };
    assert_eq!(
        task_outbox_rows.len(),
        1,
        "coalescing + undo should leave one live task outbox row, not a stack of stale task upserts"
    );
    assert_eq!(
        task_outbox_rows[0].1, restored.version,
        "live task outbox row should carry the restored version"
    );
}
