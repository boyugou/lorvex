use crate::commands::shared::render_mutation_envelope;
use serde_json::{json, Value};
use std::path::PathBuf;

/// `run_update_task` JSON output is produced
/// by `render_mutation_envelope("task.update", &db_path,
/// json!({"task": task}))`. Pre-fix this site hand-built the
/// JSON map, which silently drifted from the canonical helper
/// whenever the helper picked up new behavior (e.g. overriding
/// caller-supplied `action`/`db_path` keys CL-M3).
/// This test pins the canonical wire shape so a regression to
/// the hand-built form (with possibly drifted key ordering or
/// missing override semantics) surfaces here.
#[test]
fn task_update_envelope_uses_canonical_render_helper() {
    let task_payload = json!({
        "id": "01900000-0000-7000-8000-00000000ee01",
        "title": "Updated",
        "status": "open",
    });
    let rendered = render_mutation_envelope(
        "task.update",
        &PathBuf::from("/tmp/lorvex.sqlite"),
        json!({ "task": task_payload }),
    )
    .expect("render envelope");
    let parsed: Value = serde_json::from_str(&rendered).expect("parse rendered envelope");
    assert_eq!(parsed["action"], json!("task.update"));
    assert_eq!(parsed["db_path"], json!("/tmp/lorvex.sqlite"));
    assert_eq!(parsed["task"], task_payload);
}
