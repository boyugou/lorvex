use super::*;

#[test]
fn delete_list_internal_rejects_assigned_tasks() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-a', 'List A', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-03T08:00:00Z', '2026-03-03T08:00:00Z')",
        [],
    )
    .expect("insert list");
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new("task-a1")
        .title("Task A1")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-03T08:01:00Z")
        .list_id(Some("list-a"))
        .insert(&conn);
    TaskBuilder::new("task-a2")
        .title("Task A2")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-03T08:02:00Z")
        .list_id(Some("list-a"))
        .insert(&conn);

    let error = delete_list_internal(&conn, "list-a").expect_err("delete should be blocked");
    assert!(error.to_string().contains("Reassign or permanently delete"));
}

#[test]
fn delete_list_internal_rejects_cancelled_only_assigned_tasks() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-cancelled', 'Cancelled List', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-03T08:00:00Z', '2026-03-03T08:00:00Z')",
        [],
    )
    .expect("insert list");
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-cancelled-1")
        .title("Task Cancelled")
        .status("cancelled")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-03T08:01:00Z")
        .list_id(Some("list-cancelled"))
        .insert(&conn);

    let error =
        delete_list_internal(&conn, "list-cancelled").expect_err("delete should be blocked");
    assert!(error.to_string().contains("Reassign or permanently delete"));
}
