use super::*;
use serde_json::json;

#[test]
fn strip_derived_task_fields_removes_every_known_field() {
    let raw = json!({
        "id": "task-1",
        "title": "demo",
        "tags": ["work"],
        "depends_on": ["task-0"],
        "checklist_items": [{"id": "ci-1"}],
        "lateness_state": "overdue",
    });
    let stripped = strip_derived_task_fields(raw);
    let obj = stripped.as_object().expect("object");
    assert_eq!(obj.get("id"), Some(&json!("task-1")));
    assert_eq!(obj.get("title"), Some(&json!("demo")));
    for derived in DERIVED_TASK_FIELDS {
        assert!(
            obj.get(*derived).is_none(),
            "{derived} must not survive the strip"
        );
    }
}

#[test]
fn strip_derived_task_fields_passes_non_object_through() {
    let raw = json!("just-a-string");
    let stripped = strip_derived_task_fields(raw.clone());
    assert_eq!(stripped, raw);
}

#[test]
fn strip_derived_task_fields_is_no_op_when_field_absent() {
    let raw = json!({
        "id": "task-1",
        "title": "demo",
    });
    let stripped = strip_derived_task_fields(raw.clone());
    assert_eq!(stripped, raw);
}
