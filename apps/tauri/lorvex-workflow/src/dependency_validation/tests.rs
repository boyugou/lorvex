use super::*;

fn tid(s: &str) -> TaskId {
    TaskId::from_trusted(s.to_string())
}

fn setup_test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");
    conn
}

fn insert_task(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
         VALUES (?1, ?1, 'open', '0000000000000_0000_0000000000000000', datetime('now'), datetime('now'))",
        rusqlite::params![id],
    )
    .unwrap();
}

fn insert_dep(conn: &Connection, task_id: &str, depends_on_id: &str) {
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES (?1, ?2, '0000000000000_0000_0000000000000000', datetime('now'))",
        rusqlite::params![task_id, depends_on_id],
    )
    .unwrap();
}

#[test]
fn cycle_detection_allows_valid_dependency() {
    let conn = setup_test_conn();
    insert_task(&conn, "a");
    insert_task(&conn, "b");
    assert!(validate_no_dependency_cycle(&conn, &tid("a"), &["b".into()]).is_ok());
}

#[test]
fn cycle_detection_rejects_self_depends_on() {
    let conn = setup_test_conn();
    insert_task(&conn, "a");
    let result = validate_no_dependency_cycle(&conn, &tid("a"), &["a".into()]);
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Circular dependency detected"));
}

#[test]
fn cycle_detection_rejects_direct_cycle() {
    let conn = setup_test_conn();
    insert_task(&conn, "a");
    insert_task(&conn, "b");
    insert_dep(&conn, "b", "a"); // b depends on a
    let result = validate_no_dependency_cycle(&conn, &tid("a"), &["b".into()]);
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Circular dependency detected"));
}

#[test]
fn cycle_detection_rejects_transitive_cycle() {
    let conn = setup_test_conn();
    insert_task(&conn, "a");
    insert_task(&conn, "b");
    insert_task(&conn, "c");
    insert_dep(&conn, "b", "a"); // b depends on a
    insert_dep(&conn, "c", "b"); // c depends on b
    let result = validate_no_dependency_cycle(&conn, &tid("a"), &["c".into()]);
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Circular dependency detected"));
}

#[test]
fn cycle_detection_allows_diamond_without_cycle() {
    let conn = setup_test_conn();
    insert_task(&conn, "d");
    insert_task(&conn, "b");
    insert_task(&conn, "c");
    insert_task(&conn, "a");
    insert_task(&conn, "e");
    insert_dep(&conn, "b", "d"); // b depends on d
    insert_dep(&conn, "c", "d"); // c depends on d
    insert_dep(&conn, "a", "b"); // a depends on b
    insert_dep(&conn, "a", "c"); // a depends on c
    assert!(validate_no_dependency_cycle(&conn, &tid("e"), &["a".into()]).is_ok());
}
