use super::*;
use crate::commands::shared::test_support::seed_task;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TAG, ENTITY_TASK, OP_DELETE, OP_UPSERT};
use lorvex_store::repositories::tag_repo;

const TASK_RENAME_TAG: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a101";
const TASK_ALPHA_ONLY: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a102";
const TASK_BOTH_TAGS: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a103";
const TASK_BETA_ONLY: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a104";
const TASK_MERGE_1: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a105";
const TASK_MERGE_2: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a106";
const TASK_MERGE_3: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a107";
const TASK_INPLACE_1: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a108";
const TASK_INPLACE_2: &str = "01966a3f-7c8b-7d4e-8f3a-00000000a109";

#[test]
fn rename_tag_with_conn_renames_tag_and_syncs_affected_tasks() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_RENAME_TAG, "Tagged", "open");
    let (tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Deep Work",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000002_0000_0000000000000000', '2026-03-30T00:00:00Z')",
        rusqlite::params![TASK_RENAME_TAG, &tag_id],
    )
    .expect("seed task tag");

    let result = rename_tag_with_conn(&mut conn, "Deep Work", "Focus").expect("rename tag");

    assert_eq!(
        result,
        TagRenameResult {
            old_name: "Deep Work".to_string(),
            new_name: "Focus".to_string(),
            tasks_updated: 1,
            task_ids: vec![TASK_RENAME_TAG.to_string()],
        }
    );
    assert!(tag_repo::get_tag_by_name(&conn, "Deep Work")
        .expect("find old tag")
        .is_none());
    let renamed = tag_repo::get_tag_by_name(&conn, "focus")
        .expect("find renamed tag")
        .expect("renamed tag");
    assert_eq!(renamed.id, tag_id);
    assert_eq!(renamed.display_name, "Focus");

    let task_upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            rusqlite::params![ENTITY_TASK, TASK_RENAME_TAG],
            |row| row.get(0),
        )
        .expect("count task outbox");
    assert_eq!(task_upsert_count, 1);
    let tag_upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TAG, tag_id, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("count tag outbox");
    assert_eq!(tag_upsert_count, 1);
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'rename_tag'",
            [],
            |row| row.get(0),
        )
        .expect("count changelog");
    assert_eq!(changelog_count, 1);
}

#[test]
fn rename_tag_with_conn_merges_existing_target_and_syncs_edge_rewrites() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_ALPHA_ONLY, "Alpha only", "open");
    seed_task(&conn, TASK_BOTH_TAGS, "Both tags", "open");
    seed_task(&conn, TASK_BETA_ONLY, "Beta only", "open");
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
    for (task_id, tag_id) in [
        (TASK_ALPHA_ONLY, old_tag_id.as_str()),
        (TASK_BOTH_TAGS, old_tag_id.as_str()),
        (TASK_BOTH_TAGS, target_tag_id.as_str()),
        (TASK_BETA_ONLY, target_tag_id.as_str()),
    ] {
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, version, created_at)
             VALUES (?1, ?2, '0000000000003_0000_0000000000000000', '2026-03-30T00:00:00Z')",
            rusqlite::params![task_id, tag_id],
        )
        .expect("seed task tag");
    }
    let beta_only_version_before: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = ?1",
            [TASK_BETA_ONLY],
            |row| row.get(0),
        )
        .expect("read beta-only version before");

    let result = rename_tag_with_conn(&mut conn, "Alpha", "Beta").expect("merge tag");

    assert_eq!(result.tasks_updated, 2);
    assert_eq!(
        result.task_ids,
        vec![TASK_ALPHA_ONLY.to_string(), TASK_BOTH_TAGS.to_string()]
    );
    assert!(tag_repo::get_tag_by_name(&conn, "Alpha")
        .expect("find old tag")
        .is_none());
    let target_edges: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE tag_id = ?1",
            [&target_tag_id],
            |row| row.get(0),
        )
        .expect("count target edges");
    assert_eq!(target_edges, 3);
    let beta_only_version_after: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = ?1",
            [TASK_BETA_ONLY],
            |row| row.get(0),
        )
        .expect("read beta-only version after");
    assert_eq!(beta_only_version_after, beta_only_version_before);

    for task_id in [TASK_ALPHA_ONLY, TASK_BOTH_TAGS] {
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

    let moved_entity_id = format!("{TASK_ALPHA_ONLY}:{target_tag_id}");
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

/// every moved `task_tags` row in the
/// merge-rename path must carry its OWN `version` HLC, not one
/// shared across the bulk UPDATE. Pre-fix the bulk
/// `UPDATE task_tags SET tag_id=?, version=? WHERE tag_id=?`
/// stamped every moved row with one identical version, so peer
/// LWW reconciliation could not distinguish later legitimate
/// per-row updates from a noisy re-broadcast and silently
/// dropped genuine downstream edits.
#[test]
fn rename_tag_merge_assigns_distinct_version_to_each_moved_edge() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_MERGE_1, "Merge task 1", "open");
    seed_task(&conn, TASK_MERGE_2, "Merge task 2", "open");
    seed_task(&conn, TASK_MERGE_3, "Merge task 3", "open");
    let (old_tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "OldName",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed old tag");
    let (target_tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "NewName",
        "0000000000002_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed target tag");
    for task_id in [TASK_MERGE_1, TASK_MERGE_2, TASK_MERGE_3] {
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, version, created_at)
             VALUES (?1, ?2, '0000000000003_0000_0000000000000000', '2026-03-30T00:00:00Z')",
            rusqlite::params![task_id, &old_tag_id],
        )
        .expect("seed old edge");
    }

    let result = rename_tag_with_conn(&mut conn, "OldName", "NewName").expect("merge rename");
    assert_eq!(result.tasks_updated, 3);

    // Every moved task_tags row must now carry its own distinct
    // HLC version, NOT a shared moved_edge_version.
    let mut stmt = conn
        .prepare(
            "SELECT version FROM task_tags WHERE tag_id = ?1 AND task_id IN
             (?2, ?3, ?4) ORDER BY task_id ASC",
        )
        .expect("prepare");
    let versions: Vec<String> = stmt
        .query_map(
            rusqlite::params![&target_tag_id, TASK_MERGE_1, TASK_MERGE_2, TASK_MERGE_3],
            |row| row.get::<_, String>(0),
        )
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect");
    assert_eq!(versions.len(), 3, "expected 3 moved edges");
    let unique: std::collections::HashSet<_> = versions.iter().collect();
    assert_eq!(
        unique.len(),
        3,
        "every moved edge must carry a distinct version; got {versions:?}"
    );
    // Each version must be strictly greater than the seed
    // baseline so peer LWW gates accept the rewrite.
    for version in &versions {
        assert!(
            version.as_str() > "0000000000003_0000_0000000000000000",
            "version {version:?} must exceed seed baseline"
        );
    }

    // CL-H9: every renamed-tag-touching task row also gets its
    // own version, not a shared task_version.
    let mut stmt = conn
        .prepare(
            "SELECT version FROM tasks WHERE id IN
             (?1, ?2, ?3) ORDER BY id ASC",
        )
        .expect("prepare");
    let task_versions: Vec<String> = stmt
        .query_map(
            rusqlite::params![TASK_MERGE_1, TASK_MERGE_2, TASK_MERGE_3],
            |row| row.get::<_, String>(0),
        )
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect");
    assert_eq!(task_versions.len(), 3);
    let unique_task_versions: std::collections::HashSet<_> = task_versions.iter().collect();
    assert_eq!(
        unique_task_versions.len(),
        3,
        "every task carrying the renamed tag must get a distinct version; got {task_versions:?}"
    );
}

/// Issue #2981 CL-H9 (non-merge variant): even when the rename
/// renames-in-place (no target tag exists), every task that
/// carries the tag must receive its own per-row HLC version.
#[test]
fn rename_tag_inplace_assigns_distinct_version_to_each_task() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_INPLACE_1, "Inplace 1", "open");
    seed_task(&conn, TASK_INPLACE_2, "Inplace 2", "open");
    let (tag_id, _) = tag_repo::resolve_or_create_tag(
        &conn,
        "Original",
        "0000000000001_0000_0000000000000000",
        "2026-01-01T00:00:00.000Z",
    )
    .expect("seed tag");
    for task_id in [TASK_INPLACE_1, TASK_INPLACE_2] {
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, version, created_at)
             VALUES (?1, ?2, '0000000000002_0000_0000000000000000', '2026-03-30T00:00:00Z')",
            rusqlite::params![task_id, &tag_id],
        )
        .expect("seed edge");
    }

    let _result = rename_tag_with_conn(&mut conn, "Original", "Renamed").expect("inplace rename");

    let mut stmt = conn
        .prepare(
            "SELECT version FROM tasks WHERE id IN (?1, ?2)
             ORDER BY id ASC",
        )
        .expect("prepare");
    let versions: Vec<String> = stmt
        .query_map(rusqlite::params![TASK_INPLACE_1, TASK_INPLACE_2], |row| {
            row.get::<_, String>(0)
        })
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect");
    assert_eq!(versions.len(), 2);
    assert_ne!(
        versions[0], versions[1],
        "in-place rename must give each task its own version; got {versions:?}"
    );
}
