use super::effects::SetupCompletionResult;
use super::*;
use lorvex_store::SetupStatus;
use serde_json::Value;
use std::path::PathBuf;

fn fake_status() -> SetupStatus {
    SetupStatus {
        list_count: 1,
        default_list_id: Some("inbox".to_string()),
        lists_ready: true,
        default_list_ready: true,
        working_hours_ready: true,
        normal_task_creation_ready: true,
        prerequisites_ready: true,
        explicit_setup_completed: true,
        setup_completed: true,
    }
}

#[test]
fn render_setup_complete_json_envelope_carries_canonical_action() {
    // Synthesize the result without touching the DB so the test
    // exercises the renderer in isolation.
    let result = SetupCompletionResult {
        setup_completed: true,
        summary: "All set".to_string(),
        status: fake_status(),
    };
    let path = PathBuf::from("/tmp/db.sqlite");
    let payload = render_mutation_envelope("setup.complete", &path, json!({ "result": result }))
        .expect("render");
    let parsed: Value = serde_json::from_str(&payload).expect("valid json");
    assert_eq!(parsed["action"].as_str(), Some("setup.complete"));
    assert_eq!(parsed["db_path"].as_str(), Some("/tmp/db.sqlite"));
    assert_eq!(parsed["result"]["summary"].as_str(), Some("All set"));
    assert!(parsed["result"]["setup_completed"].as_bool().unwrap());
}
