use super::*;

/// Insert a list directly for test setup.
fn insert_test_list(conn: &Connection, id: &str, name: &str, color: Option<&str>) {
    conn.execute(
        "INSERT INTO lists (id, name, color, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z')",
        params![id, name, color, TEST_VERSION],
    )
    .expect("insert test list");
}

/// Insert a task assigned to a list for test setup.
fn insert_test_task(conn: &Connection, id: &str, list_id: Option<&str>, status: &str) {
    // lift to canonical TaskBuilder.
    let title = format!("Task {id}");
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(&title)
        .status(status)
        .list_id(list_id)
        .priority(Some(3))
        .version(TEST_VERSION)
        .created_at("2026-03-01T08:00:00Z")
        .insert(conn);
}

fn outbox_payload_for(conn: &Connection, entity_id: &str) -> serde_json::Value {
    let payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox WHERE entity_type = 'list' AND entity_id = ?1",
            params![entity_id],
            |row| row.get(0),
        )
        .expect("load list outbox payload");
    serde_json::from_str(&payload).expect("parse list outbox payload")
}

// ---------------------------------------------------------------------------
// create_list (via lorvex_store repo + Tauri list_from_row mapper)
// ---------------------------------------------------------------------------

#[test]
fn create_list_returns_expected_struct() {
    let conn = setup_sync_test_conn();

    let list_id = "list-create-1";
    lorvex_store::repositories::list_repo::create_list(
        &conn,
        &lorvex_domain::ListId::from_trusted(list_id.to_string()),
        "Shopping",
        Some("#ff0000"),
        Some("cart"),
        Some("Groceries and stuff"),
        TEST_VERSION,
    )
    .expect("repo create_list");

    // Re-read through the Tauri mapper to verify the IPC-contract struct.
    let task_list: TaskList = conn
        .query_row(
            &format!("SELECT {LIST_COLS} FROM lists WHERE id = ?1"),
            params![list_id],
            list_from_row,
        )
        .expect("reload list via Tauri mapper");

    assert_eq!(task_list.id, list_id);
    assert_eq!(task_list.name, "Shopping");
    assert_eq!(task_list.color.as_deref(), Some("#ff0000"));
    assert_eq!(task_list.icon.as_deref(), Some("cart"));
    assert_eq!(
        task_list.description.as_deref(),
        Some("Groceries and stuff")
    );
    assert!(task_list.ai_notes.is_none());
    assert!(!task_list.created_at.is_empty());
    assert_eq!(task_list.created_at, task_list.updated_at);
}

#[test]
fn create_list_minimal_fields() {
    let conn = setup_sync_test_conn();

    lorvex_store::repositories::list_repo::create_list(
        &conn,
        &lorvex_domain::ListId::from_trusted("list-min".to_string()),
        "Minimal",
        None,
        None,
        None,
        TEST_VERSION,
    )
    .expect("repo create_list minimal");

    let task_list: TaskList = conn
        .query_row(
            &format!("SELECT {LIST_COLS} FROM lists WHERE id = ?1"),
            params!["list-min"],
            list_from_row,
        )
        .expect("reload minimal list");

    assert_eq!(task_list.name, "Minimal");
    assert!(task_list.color.is_none());
    assert!(task_list.icon.is_none());
    assert!(task_list.description.is_none());
}

// ---------------------------------------------------------------------------
// get_all_lists (via lorvex_store repo + Tauri model conversion)
// ---------------------------------------------------------------------------

#[test]
fn get_all_lists_returns_all_with_task_counts() {
    let conn = setup_sync_test_conn();

    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Home",
        Some("#00ff00"),
    );
    insert_test_list(&conn, "l2", "Work", None);

    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001201",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001202",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001203",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "completed",
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001204",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "cancelled",
    );
    insert_test_task(&conn, "t5", Some("l2"), "open");

    let rows = lorvex_store::repositories::list_repo::get_all_lists_with_counts(&conn)
        .expect("get_all_lists_with_counts");

    let lists: Vec<ListWithCount> = rows
        .into_iter()
        .map(|r| ListWithCount {
            list: task_list_from_list_row(r.list),
            open_count: r.open_count,
        })
        .collect();

    // The schema seeds an Inbox list automatically, so we have 3 lists total.
    assert_eq!(lists.len(), 3);

    let home = lists
        .iter()
        .find(|l| l.list.name == "Home")
        .expect("Home list");
    assert_eq!(home.list.color.as_deref(), Some("#00ff00"));
    assert_eq!(home.open_count, 2);

    let work = lists
        .iter()
        .find(|l| l.list.name == "Work")
        .expect("Work list");
    assert_eq!(work.open_count, 1);
}

#[test]
fn get_all_lists_empty_database() {
    let conn = setup_sync_test_conn();

    let rows = lorvex_store::repositories::list_repo::get_all_lists_with_counts(&conn)
        .expect("get_all_lists_with_counts on empty db");
    // Schema seeds the Inbox list automatically, so an "empty" DB has 1 list.
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].list.name, "Inbox");
}

// ---------------------------------------------------------------------------
// get_list_with_tasks (via query_list_tasks_with_recent_completed)
// ---------------------------------------------------------------------------

#[test]
fn get_list_with_tasks_returns_list_and_open_tasks() {
    let conn = setup_sync_test_conn();

    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Project X",
        None,
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001201",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001202",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );
    // A cancelled task should not appear (it is not open or recently-completed).
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001203",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "cancelled",
    );

    // Verify the list itself can be fetched.
    let list = fetch_list_by_id(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001101")
        .expect("fetch_list_by_id")
        .expect("list should exist");
    assert_eq!(list.name, "Project X");

    // Query tasks with a window that includes no recently-completed tasks.
    let result = query_list_tasks_with_recent_completed(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001101".to_string()),
        "2026-03-01T00:00:00Z",
        "2026-03-02T00:00:00Z",
        1000,
    )
    .expect("query_list_tasks_with_recent_completed");

    // Only the two open tasks should be returned (cancelled tasks are excluded by
    // the repository query).
    assert_eq!(result.tasks.len(), 2);
    assert_eq!(result.total_matching, 2);
    let task_ids: HashSet<String> = result.tasks.iter().map(|t| t.id.clone()).collect();
    assert!(task_ids.contains("01966a3f-7c8b-7d4e-8f3a-000000001201"));
    assert!(task_ids.contains("01966a3f-7c8b-7d4e-8f3a-000000001202"));
}

#[test]
fn get_list_with_tasks_includes_recently_completed() {
    let conn = setup_sync_test_conn();

    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Sprint",
        None,
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001201",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );

    // Insert a completed task with a completion timestamp inside the window.
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000001202")
        .title("Done recently")
        .status("completed")
        .version(TEST_VERSION)
        .created_at("2026-03-01T08:00:00Z")
        .updated_at("2026-03-01T10:00:00Z")
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000001101"))
        .priority(Some(3))
        .completed_at(Some("2026-03-01T09:30:00Z"))
        .insert(&conn);

    let result = query_list_tasks_with_recent_completed(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001101".to_string()),
        "2026-03-01T00:00:00Z",
        "2026-03-02T00:00:00Z",
        1000,
    )
    .expect("query with recent completed window");

    let task_ids: HashSet<String> = result.tasks.iter().map(|t| t.id.clone()).collect();
    assert!(
        task_ids.contains("01966a3f-7c8b-7d4e-8f3a-000000001201"),
        "open task should appear"
    );
    assert!(
        task_ids.contains("01966a3f-7c8b-7d4e-8f3a-000000001202"),
        "recently-completed task should appear"
    );
    assert_eq!(result.total_matching, 2);
}

#[test]
fn get_list_with_tasks_not_found() {
    let conn = setup_sync_test_conn();

    let result = fetch_list_by_id(&conn, "nonexistent").expect("fetch should not error");
    assert!(result.is_none(), "missing list should return None");
}

// ---------------------------------------------------------------------------
// update_list (via lorvex_store repo + Tauri mapper)
// ---------------------------------------------------------------------------

#[test]
fn update_list_changes_name_and_color() {
    let conn = setup_sync_test_conn();
    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Old Name",
        Some("#000000"),
    );

    let now = "2026-03-02T12:00:00.000Z";
    lorvex_store::repositories::list_repo::update_list(
        &conn,
        lorvex_store::repositories::list_repo::ListUpdateParams {
            id: &lorvex_domain::ListId::from_trusted(
                "01966a3f-7c8b-7d4e-8f3a-000000001101".to_string(),
            ),
            name: Some("New Name"),
            color: Some("#ffffff"),
            icon: None,
            description: None,
            now,
            version: "ver-2",
        },
    )
    .expect("update_list");

    let updated: TaskList = conn
        .query_row(
            &format!("SELECT {LIST_COLS} FROM lists WHERE id = ?1"),
            params!["01966a3f-7c8b-7d4e-8f3a-000000001101"],
            list_from_row,
        )
        .expect("reload updated list");

    assert_eq!(updated.name, "New Name");
    assert_eq!(updated.color.as_deref(), Some("#ffffff"));
    assert_eq!(updated.updated_at, now);
}

#[test]
fn update_list_partial_update_preserves_other_fields() {
    let conn = setup_sync_test_conn();

    // Insert a list with all fields populated.
    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, archived_at, position, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001101', 'Full', '#aabbcc', 'star', 'desc', 'ai note', '2026-03-03T00:00:00.000Z', 42, ?1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z')",
        params![TEST_VERSION],
    )
    .expect("insert full list");

    // Update only the name.
    lorvex_store::repositories::list_repo::update_list(
        &conn,
        lorvex_store::repositories::list_repo::ListUpdateParams {
            id: &lorvex_domain::ListId::from_trusted(
                "01966a3f-7c8b-7d4e-8f3a-000000001101".to_string(),
            ),
            name: Some("Renamed"),
            color: None,
            icon: None,
            description: None,
            now: "2026-03-02T00:00:00.000Z",
            version: "ver-2",
        },
    )
    .expect("partial update_list");

    let updated: TaskList = conn
        .query_row(
            &format!("SELECT {LIST_COLS} FROM lists WHERE id = ?1"),
            params!["01966a3f-7c8b-7d4e-8f3a-000000001101"],
            list_from_row,
        )
        .expect("reload partially updated list");

    assert_eq!(updated.name, "Renamed");
    // Other fields should be untouched.
    assert_eq!(updated.color.as_deref(), Some("#aabbcc"));
    assert_eq!(updated.icon.as_deref(), Some("star"));
    assert_eq!(updated.description.as_deref(), Some("desc"));
    assert_eq!(updated.ai_notes.as_deref(), Some("ai note"));
}

#[test]
fn update_list_typed_args_clear_null_fields_and_preserve_omitted_fields() {
    let conn = setup_sync_test_conn();

    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, archived_at, position, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001101', 'Full', '#aabbcc', 'star', 'desc', 'ai note', '2026-03-03T00:00:00.000Z', 42, ?1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z')",
        params![TEST_VERSION],
    )
    .expect("insert full list");

    let args: UpdateListArgs = serde_json::from_value(json!({
        "id": "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "color": null,
        "icon": "moon"
    }))
    .expect("deserialize typed update_list args");

    let updated = update_list_with_conn(&conn, args).expect("update list through typed args");

    assert_eq!(updated.name, "Full");
    assert_eq!(updated.color, None, "explicit null must clear color");
    assert_eq!(updated.icon.as_deref(), Some("moon"));
    assert_eq!(
        updated.description.as_deref(),
        Some("desc"),
        "omitted description must be preserved"
    );

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'list' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000001101'",
            [],
            |row| row.get(0),
        )
        .expect("count list outbox rows");
    assert_eq!(outbox_count, 1);

    let payload = outbox_payload_for(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001101");
    assert_eq!(payload["name"], "Full");
    assert_eq!(payload["archived_at"], "2026-03-03T00:00:00.000Z");
    assert_eq!(payload["position"], 42);
    assert!(
        payload.get("version").and_then(|v| v.as_str()).is_some(),
        "list upsert payload must carry the freshly minted HLC version"
    );
}

// ---------------------------------------------------------------------------
// delete_list (via delete_list_internal)
// ---------------------------------------------------------------------------

#[test]
fn delete_list_rejects_lists_with_assigned_tasks() {
    let conn = setup_sync_test_conn();

    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Doomed List",
        None,
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001201",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "open",
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001202",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "completed",
    );
    // Task in a different list should not be affected.
    insert_test_list(&conn, "l2", "Safe List", None);
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001203",
        Some("l2"),
        "open",
    );

    let error = delete_list_internal(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001101")
        .expect_err("delete should be blocked");
    assert!(
        error.to_string().contains("Reassign or permanently delete"),
        "unexpected error: {error}"
    );
}

#[test]
fn delete_list_rejects_lists_with_cancelled_only_assigned_tasks() {
    let conn = setup_sync_test_conn();

    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001101",
        "Cancelled-only List",
        None,
    );
    insert_test_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001201",
        Some("01966a3f-7c8b-7d4e-8f3a-000000001101"),
        "cancelled",
    );
    insert_test_list(&conn, "l2", "Safe List", None);

    let error = delete_list_internal(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001101")
        .expect_err("delete should be blocked");
    assert!(
        error.to_string().contains("Reassign or permanently delete"),
        "unexpected error: {error}"
    );
}

#[test]
fn delete_list_not_found_returns_error() {
    let conn = setup_sync_test_conn();

    let error = delete_list_internal(&conn, "nonexistent").expect_err("should return NotFound");
    let msg = error.to_string();
    assert!(
        msg.contains("nonexistent"),
        "error message should reference the missing list id: {msg}"
    );
}

#[test]
fn delete_list_with_no_tasks_returns_deleted_list_id() {
    let conn = setup_sync_test_conn();
    insert_test_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001102",
        "Empty List",
        None,
    );
    conn.execute(
        "UPDATE lists SET archived_at = '2026-03-04T00:00:00.000Z', position = 73 \
         WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000001102'",
        [],
    )
    .expect("decorate list sync fields");

    let result = delete_list_internal(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001102")
        .expect("delete empty list");

    assert_eq!(
        result.deleted_list_id,
        "01966a3f-7c8b-7d4e-8f3a-000000001102"
    );

    let list_gone = fetch_list_by_id(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001102")
        .expect("fetch after delete")
        .is_none();
    assert!(list_gone, "empty list should be deleted");

    let payload = outbox_payload_for(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001102");
    assert_eq!(payload["name"], "Empty List");
    assert_eq!(payload["archived_at"], "2026-03-04T00:00:00.000Z");
    assert_eq!(payload["position"], 73);
    assert_eq!(payload["version"], TEST_VERSION);
}
