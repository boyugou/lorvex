use super::*;
use lorvex_domain::naming::EDGE_TASK_TAG;

fn seed_task(conn: &Connection, id: &str, title: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .list_id(Some("inbox"))
        .created_at("2026-03-01T00:00:00Z")
        .insert(conn);
}

fn seed_task_tag(conn: &Connection, task_id: &str, tag_id: &str) {
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
        rusqlite::params![task_id, tag_id],
    )
    .expect("seed task tag");
}

#[test]
#[serial_test::serial(hlc)]
fn rename_tag_conflict_merge_enqueues_task_tag_edge_rewrites() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d01", "Alpha only");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d02", "Both tags");
    let (old_tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Alpha",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed old tag");
    let (target_tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Beta",
        "0000000000002_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed target tag");
    seed_task_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d01", &old_tag_id);
    seed_task_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d02", &old_tag_id);
    seed_task_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000d02",
        &target_tag_id,
    );

    rename_tag(
        &conn,
        RenameTagArgs {
            old_name: "Alpha".to_string(),
            new_name: "Beta".to_string(),
            idempotency_key: None,
        },
    )
    .expect("rename tag");

    let old_edges: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE tag_id = ?1",
            [&old_tag_id],
            |row| row.get(0),
        )
        .expect("count old edges");
    assert_eq!(old_edges, 0);
    let target_edges: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE tag_id = ?1",
            [&target_tag_id],
            |row| row.get(0),
        )
        .expect("count target edges");
    assert_eq!(target_edges, 2);

    for task_id in [
        "01966a3f-7c8b-7d4e-8f3a-000000000d01",
        "01966a3f-7c8b-7d4e-8f3a-000000000d02",
    ] {
        let old_entity_id = format!("{task_id}:{old_tag_id}");
        let delete_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![EDGE_TASK_TAG, old_entity_id, OP_DELETE],
                |row| row.get(0),
            )
            .expect("count old edge delete");
        assert_eq!(delete_count, 1, "missing old edge delete for {task_id}");
    }

    let moved_entity_id = format!("01966a3f-7c8b-7d4e-8f3a-000000000d01:{target_tag_id}");
    let moved_upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![EDGE_TASK_TAG, moved_entity_id, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("count moved edge upsert");
    assert_eq!(moved_upsert_count, 1);
}

/// the rename batch UPDATE writes a fresh
/// `(version, updated_at)` to every affected task row, but the
/// pre-fix code emitted no per-task sync envelopes — the funnel
/// call below opted out via `skip_sync_enqueue: true` to avoid
/// double-sending the surviving tag, and neither rename branch
/// (simple rename, conflict merge) iterated the touched tasks.
/// Peers received the tag rename and edge rewrites but never
/// saw the bumped task HLCs. Pin one upsert envelope per
/// affected task.
#[test]
#[serial_test::serial(hlc)]
fn rename_tag_emits_per_task_upsert_envelopes() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d03", "Alpha doc");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d04", "Beta doc");
    let (tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Old",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed tag");
    seed_task_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d03", &tag_id);
    seed_task_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d04", &tag_id);

    rename_tag(
        &conn,
        RenameTagArgs {
            old_name: "Old".to_string(),
            new_name: "New".to_string(),
            idempotency_key: None,
        },
    )
    .expect("rename tag");

    for task_id in [
        "01966a3f-7c8b-7d4e-8f3a-000000000d03",
        "01966a3f-7c8b-7d4e-8f3a-000000000d04",
    ] {
        let upsert_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![lorvex_domain::naming::ENTITY_TASK, task_id, OP_UPSERT],
                |row| row.get(0),
            )
            .expect("count task upserts");
        assert_eq!(
            upsert_count, 1,
            "rename_tag must emit a task upsert envelope for {task_id} (#2975-H6)"
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rename_tag_rejects_stale_affected_task_before_tag_changes() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    seed_task(&conn, "task-stale-tag-rename", "Owner");
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 'task-stale-tag-rename'",
        [stale_barrier],
    )
    .expect("force stale task version");
    let (tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Old",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed tag");
    seed_task_tag(&conn, "task-stale-tag-rename", &tag_id);

    let err = rename_tag(
        &conn,
        RenameTagArgs {
            old_name: "Old".to_string(),
            new_name: "New".to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("stale affected task must reject tag rename");

    match err {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_TASK);
            assert_eq!(id, "task-stale-tag-rename");
        }
        other => panic!("expected stale-version error, got {other:?}"),
    }

    let (display_name, task_version): (String, String) = conn
        .query_row(
            "SELECT
                (SELECT display_name FROM tags WHERE id = ?1),
                (SELECT version FROM tasks WHERE id = 'task-stale-tag-rename')",
            [&tag_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read state after rejected tag rename");
    assert_eq!(display_name, "Old");
    assert_eq!(task_version, stale_barrier);
}

/// the rename audit row must classify the tag as
/// the primary entity, not the cascaded tasks. Pre-fix the row
/// recorded `entity_type='task'` with `entity_ids=[task_ids]` and
/// dropped the post-rename row entirely, which made the changelog
/// indistinguishable from a bulk task update and lost the renamed
/// tag's new display_name from the structured slot.
#[test]
#[serial_test::serial(hlc)]
fn rename_tag_logs_tag_entity_with_before_after_snapshots() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d05", "Owner");
    let (tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Old",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed tag");
    seed_task_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000d05", &tag_id);

    rename_tag(
        &conn,
        RenameTagArgs {
            old_name: "Old".to_string(),
            new_name: "New".to_string(),
            idempotency_key: None,
        },
    )
    .expect("rename tag");

    let (entity_type, entity_id, before_json, after_json): (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT entity_type, entity_id, before_json, after_json
             FROM ai_changelog WHERE mcp_tool = 'rename_tag'
             ORDER BY timestamp DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("query rename_tag changelog");
    assert_eq!(entity_type, ENTITY_TAG, "primary entity must be the tag");
    assert_eq!(entity_id.as_deref(), Some(tag_id.as_str()));
    let before: serde_json::Value =
        serde_json::from_str(&before_json.expect("before_json populated"))
            .expect("parse before_json");
    assert_eq!(
        before.get("display_name").and_then(|v| v.as_str()),
        Some("Old")
    );
    let after: serde_json::Value =
        serde_json::from_str(&after_json.expect("after_json populated")).expect("parse after_json");
    assert_eq!(
        after.get("display_name").and_then(|v| v.as_str()),
        Some("New")
    );

    // entity_ids slot must NOT carry the per-task fan-out: the
    // affected tasks already get task envelopes via their own
    // version bumps, so listing them here would double-classify.
    // The funnel populates entity_ids from {entity_id} ∪ entity_ids,
    // so the column carries the single tag id (fan-out merged from
    // `entity_id`), not the affected task ids that pre-fix code put
    // there.
    let changelog_id: String = conn
        .query_row(
            "SELECT id FROM ai_changelog WHERE mcp_tool = 'rename_tag'
             ORDER BY timestamp DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("query changelog id");
    let parsed_ids = lorvex_store::changelog::load_changelog_entity_ids(&conn, &changelog_id)
        .expect("load entity_ids");
    assert_eq!(
        parsed_ids,
        vec![tag_id],
        "entity_ids must reflect the tag id only — not the cascaded task ids"
    );
}
