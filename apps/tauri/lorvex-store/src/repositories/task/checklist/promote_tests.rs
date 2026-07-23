use super::*;
use crate::open_db_in_memory;
use crate::test_support::TaskBuilder;

/// when a peer or a prior run already stamped
/// `tasks.version` strictly greater than the migration's
/// `migration_version(physical_ms, 0, ...)`, the promotion's
/// UPDATE must no-op rather than silently roll the row's HLC
/// backwards. The per-item INSERTs are skipped too so body and
/// checklist-items stay consistent.
#[test]
fn promote_skips_when_local_version_is_strictly_newer() {
    let conn = open_db_in_memory().unwrap();

    // Seed a task with markdown checklist body AND a version that
    // sorts above any plausible `migration_version` for this run
    // (use a far-future physical_ms — well above wall-clock now).
    let future_version = "9999999999999_0000_ffffffffffffffff";
    TaskBuilder::new("t1")
        .title("has checklist")
        .body(Some("- [ ] item one\n- [ ] item two"))
        .version(future_version)
        .created_at("2026-04-20T00:00:00.000Z")
        .insert(&conn);

    promote_markdown_task_checklists(&conn).unwrap();

    // Body must be untouched — the LWW guard refused the UPDATE.
    let body: Option<String> = conn
        .query_row("SELECT body FROM tasks WHERE id = 't1'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        body.as_deref(),
        Some("- [ ] item one\n- [ ] item two"),
        "body must NOT be rewritten when LWW guard refuses the UPDATE"
    );

    // Version must NOT have been rolled back.
    let version: String = conn
        .query_row("SELECT version FROM tasks WHERE id = 't1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(
        version, future_version,
        "tasks.version must NOT roll backwards under M4 LWW guard"
    );

    // No checklist items should have been inserted (consistency
    // with the un-rewritten body).
    let item_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_checklist_items WHERE task_id = 't1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        item_count, 0,
        "per-item INSERTs must be skipped when the body rewrite is rejected"
    );
}

/// Sanity check: with a normally-aged version, the promotion still
/// runs end-to-end (body rewrite + per-item inserts).
#[test]
fn promote_runs_when_local_version_is_older() {
    let conn = open_db_in_memory().unwrap();

    let old_version = "0000000000001_0000_0000000000000000";
    TaskBuilder::new("t1")
        .title("has checklist")
        .body(Some("- [ ] item one\n- [ ] item two"))
        .version(old_version)
        .created_at("2026-04-20T00:00:00.000Z")
        .insert(&conn);

    promote_markdown_task_checklists(&conn).unwrap();

    let item_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_checklist_items WHERE task_id = 't1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(item_count, 2, "promotion must materialize both items");

    let version: String = conn
        .query_row("SELECT version FROM tasks WHERE id = 't1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert!(
        version.as_str() > old_version,
        "tasks.version must advance to the migration_version stamp"
    );
}
