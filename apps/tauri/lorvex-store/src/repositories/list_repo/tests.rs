//! Tests for `list_repo`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::test_support::test_conn;
use rusqlite::{params, Connection};

// Issue #3285: tests bypass the trust-boundary parser via
// `from_trusted` because the seeded FK rows use short labels
// (`l1`, `l2`, …) rather than UUIDs.
fn lid(id: &str) -> ListId {
    ListId::from_trusted(id.to_string())
}

fn insert_list(conn: &Connection, id: &str, name: &str, color: Option<&str>) {
    conn.execute(
        "INSERT INTO lists (id, name, color, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
        params![id, name, color],
    )
    .expect("insert list");
}

// -- get_all_lists --

#[test]
fn get_all_lists_returns_all_ordered_by_name() {
    let conn = test_conn();
    insert_list(&conn, "l2", "Work", None);
    insert_list(&conn, "l1", "Home", Some("#ff0000"));
    insert_list(&conn, "l3", "Personal", None);

    let lists = get_all_lists(&conn).unwrap();
    // 3 explicitly inserted + 1 schema-seeded 'inbox' = 4
    assert_eq!(lists.len(), 4);
    assert_eq!(lists[0].name, "Home");
    assert_eq!(lists[1].name, "Inbox");
    assert_eq!(lists[2].name, "Personal");
    assert_eq!(lists[3].name, "Work");
}

#[test]
fn get_all_lists_fresh_db_contains_seeded_inbox() {
    let conn = test_conn();
    let lists = get_all_lists(&conn).unwrap();
    assert_eq!(lists.len(), 1);
    assert_eq!(lists[0].id, "inbox");
    assert_eq!(lists[0].name, "Inbox");
}

// -- get_list --

#[test]
fn get_list_by_id() {
    let conn = test_conn();
    insert_list(&conn, "l1", "Home", Some("#ff0000"));

    let list = get_list(&conn, &lid("l1")).unwrap();
    assert!(list.is_some());
    let list = list.unwrap();
    assert_eq!(list.id, "l1");
    assert_eq!(list.name, "Home");
    assert_eq!(list.color.as_deref(), Some("#ff0000"));
}

#[test]
fn get_list_returns_none_for_missing() {
    let conn = test_conn();
    let list = get_list(&conn, &lid("nonexistent")).unwrap();
    assert!(list.is_none());
}

// -- get_all_lists_with_counts --

fn insert_task(conn: &Connection, id: &str, list_id: Option<&str>, status: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count) \
         VALUES (?1, ?2, ?3, ?4, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
        params![id, format!("Task {id}"), status, list_id],
    )
    .expect("insert task");
}

#[test]
fn get_all_lists_with_counts_returns_correct_counts() {
    let conn = test_conn();
    insert_list(&conn, "l1", "Home", None);
    insert_list(&conn, "l2", "Work", None);
    insert_task(&conn, "t1", Some("l1"), "open");
    insert_task(&conn, "t2", Some("l1"), "open");
    insert_task(&conn, "t3", Some("l1"), "completed");
    insert_task(&conn, "t4", Some("l1"), "cancelled");
    insert_task(&conn, "t5", Some("l2"), "open");

    let lists = get_all_lists_with_counts(&conn).unwrap();
    // 2 explicit + 1 seeded inbox = 3
    assert_eq!(lists.len(), 3);
    let home = lists
        .iter()
        .find(|l| l.list.name == "Home")
        .expect("Home list");
    assert_eq!(home.open_count, 2);
    assert_eq!(home.total_count, 4); // includes every assigned task row
    let work = lists
        .iter()
        .find(|l| l.list.name == "Work")
        .expect("Work list");
    assert_eq!(work.open_count, 1);
    assert_eq!(work.total_count, 1);
}

#[test]
fn get_all_lists_with_counts_empty_list() {
    let conn = test_conn();
    insert_list(&conn, "l1", "Empty", None);

    let lists = get_all_lists_with_counts(&conn).unwrap();
    // 1 explicit + 1 seeded inbox = 2
    assert_eq!(lists.len(), 2);
    let empty = lists
        .iter()
        .find(|l| l.list.id == "l1")
        .expect("Empty list");
    assert_eq!(empty.open_count, 0);
    assert_eq!(empty.total_count, 0);
}

// -- field mapping --

#[test]
fn list_row_maps_all_fields() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO lists
            (id, name, color, icon, description, ai_notes, version, created_at, updated_at,
             archived_at, position) \
         VALUES ('l1', 'Full List', '#00ff00', 'star', 'A description', 'AI notes here', \
         '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z',
         '2026-01-02T00:00:00.000Z', '2026-01-03T00:00:00.000Z', 9)",
        [],
    )
    .expect("insert full list");

    let list = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert_eq!(list.id, "l1");
    assert_eq!(list.name, "Full List");
    assert_eq!(list.color.as_deref(), Some("#00ff00"));
    assert_eq!(list.icon.as_deref(), Some("star"));
    assert_eq!(list.description.as_deref(), Some("A description"));
    assert_eq!(list.ai_notes.as_deref(), Some("AI notes here"));
    assert_eq!(list.created_at.as_string(), "2026-01-01T00:00:00.000Z");
    assert_eq!(list.updated_at.as_string(), "2026-01-02T00:00:00.000Z");
    assert_eq!(
        list.archived_at.map(|ts| ts.as_string()).as_deref(),
        Some("2026-01-03T00:00:00.000Z")
    );
    assert_eq!(list.position, 9);
}

// -- create_list --

#[test]
fn create_list_returns_inserted_row() {
    let conn = test_conn();
    let row = create_list(
        &conn,
        &lid("l1"),
        "New List",
        Some("#aabb00"),
        Some("folder"),
        Some("My desc"),
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    assert_eq!(row.id, "l1");
    assert_eq!(row.name, "New List");
    assert_eq!(row.color.as_deref(), Some("#aabb00"));
    assert_eq!(row.icon.as_deref(), Some("folder"));
    assert_eq!(row.description.as_deref(), Some("My desc"));
    assert!(row.ai_notes.is_none());
    assert!(!row.created_at.as_string().is_empty());
    assert_eq!(row.created_at, row.updated_at);
}

#[test]
fn create_list_minimal_fields() {
    let conn = test_conn();
    let row = create_list(
        &conn,
        &lid("l1"),
        "Minimal",
        None,
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    assert_eq!(row.name, "Minimal");
    assert!(row.color.is_none());
    assert!(row.icon.is_none());
    assert!(row.description.is_none());
}

// -- update_list --

#[test]
fn update_list_single_field() {
    let conn = test_conn();
    create_list(
        &conn,
        &lid("l1"),
        "Before",
        None,
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    update_list(
        &conn,
        ListUpdateParams {
            id: &lid("l1"),
            name: Some("After"),
            color: None,
            icon: None,
            description: None,
            now: "2026-03-27T00:00:00.000Z",
            version: "v2",
        },
    )
    .unwrap();
    let row = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert_eq!(row.name, "After");
}

#[test]
fn update_list_no_fields_is_noop() {
    let conn = test_conn();
    create_list(
        &conn,
        &lid("l1"),
        "Same",
        Some("#ff0000"),
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    update_list(
        &conn,
        ListUpdateParams {
            id: &lid("l1"),
            name: None,
            color: None,
            icon: None,
            description: None,
            now: "2026-03-27T00:00:00.000Z",
            version: "v2",
        },
    )
    .unwrap();
}

#[test]
fn update_list_delegates_to_patched() {
    let conn = test_conn();
    create_list(&conn, &lid("l1"), "Before", None, None, None, "v1").unwrap();
    update_list(
        &conn,
        ListUpdateParams {
            id: &lid("l1"),
            name: Some("After"),
            color: None,
            icon: None,
            description: None,
            now: "2026-03-27T12:00:00.000Z",
            version: "v2",
        },
    )
    .unwrap();
    let row = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert_eq!(row.name, "After");
    assert_eq!(row.version, "v2");
}

// -- delete_list --

#[test]
fn delete_list_returns_one_on_success() {
    let conn = test_conn();
    create_list(
        &conn,
        &lid("l1"),
        "Doomed",
        None,
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    assert_eq!(delete_list(&conn, &lid("l1")).unwrap(), 1);
    assert!(get_list(&conn, &lid("l1")).unwrap().is_none());
}

#[test]
fn delete_list_returns_zero_for_missing() {
    let conn = test_conn();
    assert_eq!(delete_list(&conn, &lid("nonexistent")).unwrap(), 0);
}

// -- update_list_patched --

#[test]
fn update_list_patched_sets_nullable_fields() {
    let conn = test_conn();
    create_list_with_ai_notes(
        &conn,
        ListCreateParams {
            id: &lid("l1"),
            name: "Test",
            color: Some("#ff0000"),
            icon: Some("star"),
            description: Some("desc"),
            ai_notes: Some("ai"),
            version: "0000000000000_0000_0000000000000000",
        },
    )
    .unwrap();

    // Clear color and icon to NULL, update description
    let patch = ListUpdatePatch {
        color: Patch::Clear,
        icon: Patch::Clear,
        description: Patch::Set("new desc"),
        ..Default::default()
    };
    update_list_patched(&conn, &lid("l1"), &patch, "v2", "2026-03-27T00:00:00.000Z").unwrap();

    let row = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert!(row.color.is_none());
    assert!(row.icon.is_none());
    assert_eq!(row.description.as_deref(), Some("new desc"));
    assert_eq!(row.ai_notes.as_deref(), Some("ai")); // untouched
    assert_eq!(row.name, "Test"); // untouched
}

#[test]
fn update_list_patched_empty_patch_is_noop() {
    let conn = test_conn();
    create_list(
        &conn,
        &lid("l1"),
        "Test",
        None,
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    update_list_patched(
        &conn,
        &lid("l1"),
        &ListUpdatePatch::default(),
        "v2",
        "2026-03-27T00:00:00.000Z",
    )
    .unwrap();
}

#[test]
fn update_list_patched_updates_name() {
    let conn = test_conn();
    create_list(
        &conn,
        &lid("l1"),
        "Before",
        None,
        None,
        None,
        "0000000000000_0000_0000000000000000",
    )
    .unwrap();
    let patch = ListUpdatePatch {
        name: Some("After"),
        ..Default::default()
    };
    update_list_patched(&conn, &lid("l1"), &patch, "v2", "2026-03-27T00:00:00.000Z").unwrap();
    let row = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert_eq!(row.name, "After");
}

#[test]
fn update_list_patched_bumps_version() {
    let conn = test_conn();
    create_list(&conn, &lid("l1"), "Test", None, None, None, "v1").unwrap();

    let patch = ListUpdatePatch {
        name: Some("Updated"),
        ..Default::default()
    };
    update_list_patched(&conn, &lid("l1"), &patch, "v2", "2026-03-27T12:00:00.000Z").unwrap();

    let row = get_list(&conn, &lid("l1")).unwrap().unwrap();
    assert_eq!(row.version, "v2");
    assert_eq!(row.name, "Updated");
}
