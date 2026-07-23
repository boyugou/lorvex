use super::support::{get_task, insert_task, test_conn};
use lorvex_domain::TaskId;

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

#[test]
fn get_task_by_id() {
    let conn = test_conn();
    insert_task(&conn, "t1", "My task", "open", None, None, Some(2), None);

    let task = get_task(&conn, &tid("t1")).unwrap();
    assert!(task.is_some());
    let task = task.unwrap();
    assert_eq!(task.core.id, "t1");
    assert_eq!(task.core.title, "My task");
    assert_eq!(task.core.status, "open");
    assert_eq!(task.core.priority, Some(2));
}

#[test]
fn get_task_returns_none_for_missing() {
    let conn = test_conn();
    let task = get_task(&conn, &tid("nonexistent")).unwrap();
    assert!(task.is_none());
}

// -- search_tasks --
