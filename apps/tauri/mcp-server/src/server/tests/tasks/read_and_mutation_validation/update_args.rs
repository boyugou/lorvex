use super::*;

// Guards the `TaskStatusValue` serde contract: an invalid status string
// must reject at JSON-Schema deserialize before the handler body runs,
// so a future regression in the enum's serde attribute (e.g. accidental
// `serde(rename_all = "PascalCase")`) fails loudly here.
#[test]
#[serial_test::serial(hlc)]
fn update_task_args_rejects_status_outside_allowed_enum_at_parse() {
    let raw = r#"{
        "id": "task-status-test",
        "status": "blocked"
    }"#;
    let err = serde_json::from_str::<UpdateTaskArgs>(raw)
        .expect_err("invalid status string must fail at deserialize");
    let msg = err.to_string();
    assert!(
        msg.contains("blocked")
            || msg.to_ascii_lowercase().contains("variant")
            || msg.to_ascii_lowercase().contains("expected"),
        "deserialize diagnostic should name the offender or expected variants, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn update_task_args_status_round_trips_through_typed_enum() {
    let raw = r#"{
        "id": "task-status-test",
        "status": "completed"
    }"#;
    let parsed: UpdateTaskArgs = serde_json::from_str(raw).expect("valid status must deserialize");
    assert!(matches!(parsed.status, Some(TaskStatusValue::Completed)));
}

#[test]
#[serial_test::serial(hlc)]
fn update_task_args_rejects_legacy_tags_replacement_alias() {
    let raw = r#"{
        "id": "task-tags-test",
        "tags": ["legacy"]
    }"#;
    let err = serde_json::from_str::<UpdateTaskArgs>(raw)
        .expect_err("legacy update tags alias must fail at deserialize");
    assert!(
        err.to_string().contains("tags"),
        "deserialize diagnostic should name legacy field, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_task_patch_rejects_legacy_tags_replacement_alias() {
    let raw = r#"{
        "id": "task-tags-test",
        "tags": ["legacy"]
    }"#;
    let err = serde_json::from_str::<BatchUpdateTaskPatch>(raw)
        .expect_err("legacy batch update tags alias must fail at deserialize");
    assert!(
        err.to_string().contains("tags"),
        "deserialize diagnostic should name legacy field, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_args_rejects_create_time_tag_patch_fields() {
    let raw = r#"{
        "title": "Create tag cleanup",
        "tags_set": ["legacy"],
        "tags_remove": ["noop"]
    }"#;
    let err = serde_json::from_str::<CreateTaskArgs>(raw)
        .expect_err("create-time tag patch fields must fail at deserialize");
    assert!(
        err.to_string().contains("tags_set") || err.to_string().contains("tags_remove"),
        "deserialize diagnostic should name removed create field, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_task_input_rejects_create_time_tag_patch_fields() {
    let raw = r#"{
        "title": "Batch create tag cleanup",
        "tags_add": ["legacy"]
    }"#;
    let err = serde_json::from_str::<BatchCreateTaskInput>(raw)
        .expect_err("batch create-time tag patch fields must fail at deserialize");
    assert!(
        err.to_string().contains("tags_add"),
        "deserialize diagnostic should name removed create field, got: {err}"
    );
}
