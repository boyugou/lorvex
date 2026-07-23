use super::*;

#[test]
fn cleanup_task_dependency_refs_removes_edges() {
    let conn = setup_sync_test_conn();
    let now = "2026-03-06T12:00:00Z";

    // seed via the canonical [`TEST_VERSION`] so a future
    // LWW gate added to `cleanup_task_dependency_refs_after_removal`
    // (or any of the join paths it touches) cannot silently drop the
    // dependency edges this test asserts on. The constant lex-sorts
    // strictly below every realistic post-update HLC.
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    for (id, title) in [
        ("01966a3f-7c8b-7d4e-8f3a-00000000d001", "Task A"),
        ("01966a3f-7c8b-7d4e-8f3a-00000000d002", "Task B"),
        ("01966a3f-7c8b-7d4e-8f3a-00000000d003", "Task C"),
    ] {
        TaskBuilder::new(id)
            .title(title)
            .version(TEST_VERSION)
            .created_at(now)
            .insert(&conn);
    }

    // a depends on b
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000d001', '01966a3f-7c8b-7d4e-8f3a-00000000d002', ?1, '2026-03-01T00:00:00Z')",
        params![TEST_VERSION],
    )
    .unwrap();
    // c depends on a and b
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000d003', '01966a3f-7c8b-7d4e-8f3a-00000000d001', ?1, '2026-03-01T00:00:00Z')",
        params![TEST_VERSION],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000d003', '01966a3f-7c8b-7d4e-8f3a-00000000d002', ?1, '2026-03-01T00:00:00Z')",
        params![TEST_VERSION],
    )
    .unwrap();

    let affected = cleanup_task_dependency_refs_after_removal(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000d001".to_string()),
        "2026-03-06T12:00:00Z",
    )
    .unwrap();
    assert!(
        affected.contains(&"01966a3f-7c8b-7d4e-8f3a-00000000d003".to_string()),
        "Task C should be affected (it depended on '01966a3f-7c8b-7d4e-8f3a-00000000d001')"
    );

    // Verify '01966a3f-7c8b-7d4e-8f3a-00000000d001' is no longer in c's dependencies
    let c_deps: Vec<String> = conn
        .prepare("SELECT depends_on_task_id FROM task_dependencies WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-00000000d003'")
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect();
    assert_eq!(
        c_deps,
        vec!["01966a3f-7c8b-7d4e-8f3a-00000000d002".to_string()]
    );
}
