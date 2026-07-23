//! Checklist mutations (#2975-H4): every checklist write tool must
//! mint a fresh HLC version on the parent task so peer LWW does not
//! silently drop the upsert envelope.

use super::support::*;

fn add_checklist_item_for_test(conn: &Connection, task_id: &str, text: &str) -> String {
    let payload = add_task_checklist_item(
        conn,
        AddTaskChecklistItemArgs {
            id: task_id.to_string(),
            text: text.to_string(),
            position: None,
            idempotency_key: None,
        },
    )
    .expect("add checklist item for test");
    let task: Value = serde_json::from_str(&payload).expect("parse task after checklist add");
    task["checklist_items"]
        .as_array()
        .expect("checklist_items array")
        .iter()
        .find(|item| item["text"].as_str() == Some(text))
        .and_then(|item| item["id"].as_str())
        .expect("new checklist item id")
        .to_string()
}

fn reset_hlc_for_checklist_test() -> std::sync::MutexGuard<'static, ()> {
    let guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex poisoned");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    guard
}

fn count_changelog_for_tool(conn: &Connection, tool: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = ?1",
        [tool],
        |row| row.get::<_, i64>(0),
    )
    .expect("count checklist changelog rows")
}

/// pre-fix `touch_task_timestamp` (called by every
/// checklist mutation) wrote only `updated_at`, leaving `version`
/// stale. The Tauri side already had the fix (#2970-H1); MCP didn't.
/// Walk the five surfaces and pin a version bump on each.
#[test]
#[serial_test::serial(hlc)]
fn checklist_mutations_bump_parent_task_version() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let now = "2026-04-02T00:00:00Z";
    let initial_version = "0000000000000_0000_0000000000000000";
    seed_task_with_version(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000011a",
        "Task H4",
        initial_version,
        now,
    );

    // 1. add_task_checklist_item
    let (v_before, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    add_task_checklist_item(
        &conn,
        AddTaskChecklistItemArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011a".to_string(),
            text: "step one".to_string(),
            position: None,
            idempotency_key: None,
        },
    )
    .expect("add checklist item");
    let (v_after_add, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    assert_ne!(
        v_before, v_after_add,
        "add_task_checklist_item must bump parent task version"
    );

    // Resolve the freshly-added item id.
    let item_id: String = conn
        .query_row(
            "SELECT id FROM task_checklist_items WHERE task_id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-00000000011a"],
            |row| row.get(0),
        )
        .expect("checklist item id");

    // 2. update_task_checklist_item
    let (v_before, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    update_task_checklist_item(
        &conn,
        UpdateTaskChecklistItemArgs {
            item_id: item_id.clone(),
            text: "step one revised".to_string(),
            idempotency_key: None,
        },
    )
    .expect("update checklist item");
    let (v_after_update, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    assert_ne!(
        v_before, v_after_update,
        "update_task_checklist_item must bump parent task version"
    );

    // 3. toggle_task_checklist_item
    let (v_before, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    toggle_task_checklist_item(
        &conn,
        ToggleTaskChecklistItemArgs {
            item_id: item_id.clone(),
            completed: true,
            idempotency_key: None,
        },
    )
    .expect("toggle checklist item");
    let (v_after_toggle, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    assert_ne!(
        v_before, v_after_toggle,
        "toggle_task_checklist_item must bump parent task version"
    );

    // 4. reorder_task_checklist_items — needs at least 2 items to be a
    // meaningful reorder, but the version-bump invariant fires even
    // for a single-item reorder.
    add_task_checklist_item(
        &conn,
        AddTaskChecklistItemArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011a".to_string(),
            text: "step two".to_string(),
            position: None,
            idempotency_key: None,
        },
    )
    .expect("add second checklist item");
    let item_ids: Vec<String> = {
        let mut stmt = conn
            .prepare("SELECT id FROM task_checklist_items WHERE task_id = ?1 ORDER BY position ASC")
            .expect("prepare");
        stmt.query_map(["01966a3f-7c8b-7d4e-8f3a-00000000011a"], |row| {
            row.get::<_, String>(0)
        })
        .expect("query")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect")
    };
    let reversed: Vec<String> = item_ids.iter().rev().cloned().collect();
    let (v_before, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    reorder_task_checklist_items(
        &conn,
        ReorderTaskChecklistItemsArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011a".to_string(),
            item_ids: reversed,
            idempotency_key: None,
        },
    )
    .expect("reorder checklist items");
    let (v_after_reorder, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    assert_ne!(
        v_before, v_after_reorder,
        "reorder_task_checklist_items must bump parent task version"
    );

    // 5. remove_task_checklist_item
    let (v_before, _) = read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    remove_task_checklist_item(
        &conn,
        RemoveTaskChecklistItemArgs {
            item_id,
            idempotency_key: None,
        },
    )
    .expect("remove checklist item");
    let (v_after_remove, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011a");
    assert_ne!(
        v_before, v_after_remove,
        "remove_task_checklist_item must bump parent task version"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn add_task_checklist_item_rejects_stale_parent_version_without_child_insert() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let now = "2026-04-02T00:00:00Z";
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000061a";
    seed_task_with_version(&conn, task_id, "Task stale checklist", stale_barrier, now);

    let err = add_task_checklist_item(
        &conn,
        AddTaskChecklistItemArgs {
            id: task_id.to_string(),
            text: "must not insert".to_string(),
            position: None,
            idempotency_key: None,
        },
    )
    .expect_err("stale checklist insert must reject");

    match err {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_TASK);
            assert_eq!(id, task_id);
        }
        other => panic!("expected stale-version error, got {other:?}"),
    }

    let (item_count, version): (i64, String) = conn
        .query_row(
            "SELECT
                (SELECT COUNT(*) FROM task_checklist_items WHERE task_id = ?1),
                (SELECT version FROM tasks WHERE id = ?1)",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read checklist after rejected insert");
    assert_eq!(item_count, 0);
    assert_eq!(version, stale_barrier);
}

#[test]
#[serial_test::serial(hlc)]
fn update_task_checklist_item_with_idempotency_key_returns_cached_on_retry() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000071a";
    seed_task_with_version(
        &conn,
        task_id,
        "Retry-safe checklist update",
        "0000000000000_0000_0000000000000000",
        "2026-04-02T00:00:00Z",
    );
    let item_id = add_checklist_item_for_test(&conn, task_id, "draft");

    let args = || UpdateTaskChecklistItemArgs {
        item_id: item_id.clone(),
        text: "revised".to_string(),
        idempotency_key: Some("checklist-update-retry".to_string()),
    };
    let first = update_task_checklist_item(&conn, args()).expect("first checklist update");
    let changelog_after_first = count_changelog_for_tool(&conn, "update_task_checklist_item");
    let second = update_task_checklist_item(&conn, args()).expect("retry checklist update");

    assert_eq!(first, second);
    assert_eq!(
        count_changelog_for_tool(&conn, "update_task_checklist_item"),
        changelog_after_first,
        "retry must not write a second update changelog row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn toggle_task_checklist_item_with_idempotency_key_returns_cached_on_retry() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000071b";
    seed_task_with_version(
        &conn,
        task_id,
        "Retry-safe checklist toggle",
        "0000000000000_0000_0000000000000000",
        "2026-04-02T00:00:00Z",
    );
    let item_id = add_checklist_item_for_test(&conn, task_id, "toggle me");

    let args = || ToggleTaskChecklistItemArgs {
        item_id: item_id.clone(),
        completed: true,
        idempotency_key: Some("checklist-toggle-retry".to_string()),
    };
    let first = toggle_task_checklist_item(&conn, args()).expect("first checklist toggle");
    let changelog_after_first = count_changelog_for_tool(&conn, "toggle_task_checklist_item");
    let second = toggle_task_checklist_item(&conn, args()).expect("retry checklist toggle");

    assert_eq!(first, second);
    assert_eq!(
        count_changelog_for_tool(&conn, "toggle_task_checklist_item"),
        changelog_after_first,
        "retry must not write a second toggle changelog row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn remove_task_checklist_item_with_idempotency_key_returns_cached_on_retry() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000071c";
    seed_task_with_version(
        &conn,
        task_id,
        "Retry-safe checklist remove",
        "0000000000000_0000_0000000000000000",
        "2026-04-02T00:00:00Z",
    );
    let item_id = add_checklist_item_for_test(&conn, task_id, "remove me");

    let args = || RemoveTaskChecklistItemArgs {
        item_id: item_id.clone(),
        idempotency_key: Some("checklist-remove-retry".to_string()),
    };
    let first = remove_task_checklist_item(&conn, args()).expect("first checklist remove");
    let changelog_after_first = count_changelog_for_tool(&conn, "remove_task_checklist_item");
    let second = remove_task_checklist_item(&conn, args())
        .expect("retry should replay instead of returning NotFound");

    assert_eq!(first, second);
    assert_eq!(
        count_changelog_for_tool(&conn, "remove_task_checklist_item"),
        changelog_after_first,
        "retry must not write a second remove changelog row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn reorder_task_checklist_items_with_idempotency_key_returns_cached_on_retry() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000071d";
    seed_task_with_version(
        &conn,
        task_id,
        "Retry-safe checklist reorder",
        "0000000000000_0000_0000000000000000",
        "2026-04-02T00:00:00Z",
    );
    let first_id = add_checklist_item_for_test(&conn, task_id, "one");
    let second_id = add_checklist_item_for_test(&conn, task_id, "two");

    let args = || ReorderTaskChecklistItemsArgs {
        id: task_id.to_string(),
        item_ids: vec![second_id.clone(), first_id.clone()],
        idempotency_key: Some("checklist-reorder-retry".to_string()),
    };
    let first = reorder_task_checklist_items(&conn, args()).expect("first checklist reorder");
    let changelog_after_first = count_changelog_for_tool(&conn, "reorder_task_checklist_items");
    let second = reorder_task_checklist_items(&conn, args()).expect("retry checklist reorder");

    assert_eq!(first, second);
    assert_eq!(
        count_changelog_for_tool(&conn, "reorder_task_checklist_items"),
        changelog_after_first,
        "retry must not write a second reorder changelog row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn checklist_idempotency_rejects_payload_drift_under_same_key() {
    let _hlc_guard = reset_hlc_for_checklist_test();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000071e";
    seed_task_with_version(
        &conn,
        task_id,
        "Checklist collision",
        "0000000000000_0000_0000000000000000",
        "2026-04-02T00:00:00Z",
    );
    let item_id = add_checklist_item_for_test(&conn, task_id, "draft");

    update_task_checklist_item(
        &conn,
        UpdateTaskChecklistItemArgs {
            item_id: item_id.clone(),
            text: "first revision".to_string(),
            idempotency_key: Some("checklist-update-collision".to_string()),
        },
    )
    .expect("first checklist update");

    let err = update_task_checklist_item(
        &conn,
        UpdateTaskChecklistItemArgs {
            item_id,
            text: "different revision".to_string(),
            idempotency_key: Some("checklist-update-collision".to_string()),
        },
    )
    .expect_err("checksum mismatch must be rejected");

    assert!(
        err.to_string()
            .contains("idempotency_key 'checklist-update-collision'"),
        "diagnostic should name the colliding key, got: {err}"
    );
    assert!(
        err.to_string().contains("different request payload"),
        "diagnostic should explain the collision, got: {err}"
    );
}
