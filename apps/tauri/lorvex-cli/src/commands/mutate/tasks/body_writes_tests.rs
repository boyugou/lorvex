use super::*;
use serde_json::Value;
use std::path::PathBuf;

fn fake_task(id: &str, title: &str) -> lorvex_store::repositories::task::read::TaskRow {
    use lorvex_store::repositories::task::read::{
        TaskCore, TaskCoreFields, TaskLifecycleTimestamps, TaskLifecycleTimestampsFields,
        TaskRecurrenceState, TaskRecurrenceStateFields, TaskRow, TaskScheduling,
        TaskSchedulingFields,
    };
    TaskRow::from_parts(
        TaskCore::new(TaskCoreFields {
            id: id.to_string(),
            title: title.to_string(),
            body: None,
            raw_input: None,
            ai_notes: None,
            status: "open".to_string(),
            list_id: "inbox".to_string(),
            priority: None,
            version: "0000000000000_0000_0000000000000000".to_string(),
            created_at: "2026-04-25T00:00:00Z".to_string(),
            updated_at: "2026-04-25T00:00:00Z".to_string(),
        }),
        TaskScheduling::new(TaskSchedulingFields::default()),
        TaskRecurrenceState::new(TaskRecurrenceStateFields::default()),
        TaskLifecycleTimestamps::new(TaskLifecycleTimestampsFields::default()),
    )
}

#[test]
fn render_task_write_envelope_text_includes_heading_and_id() {
    let path = PathBuf::from("/tmp/lorvex.sqlite");
    let task = fake_task("t-1", "Plan");
    let out = render_task_write_envelope(
        "task.append_body",
        "Appended to Lorvex task body",
        &path,
        &task,
        OutputFormat::Text,
    )
    .expect("render");
    assert!(out.contains("Appended to Lorvex task body"));
    assert!(out.contains("Task: Plan (t-1)"));
    assert!(out.contains("/tmp/lorvex.sqlite"));
}

#[test]
fn render_task_write_envelope_json_emits_canonical_action() {
    let path = PathBuf::from("/tmp/lorvex.sqlite");
    let task = fake_task("t-2", "Title");
    let out = render_task_write_envelope(
        "task.recurrence_exception.add",
        "Added Lorvex task recurrence exception",
        &path,
        &task,
        OutputFormat::Json,
    )
    .expect("render");
    let parsed: Value = serde_json::from_str(&out).expect("valid json");
    assert_eq!(
        parsed["action"].as_str(),
        Some("task.recurrence_exception.add")
    );
    assert_eq!(parsed["db_path"].as_str(), Some("/tmp/lorvex.sqlite"));
    assert_eq!(parsed["task"]["id"].as_str(), Some("t-2"));
}
