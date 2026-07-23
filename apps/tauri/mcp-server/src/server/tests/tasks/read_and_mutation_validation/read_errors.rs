use super::support::MISSING_TASK_UUID;
use super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_task_missing_returns_not_found_error_text() {
    // #2182: tool-boundary errors are structured JSON payloads so the
    // assistant can classify them programmatically. The inner `message`
    // still carries the human-readable `"<Entity> '<id>' not found"`
    // prose, and `entity_id` echoes the id that could not be resolved.
    let server = make_server();
    let err = server
        .get_task(Parameters(GetTaskArgs {
            id: MISSING_TASK_UUID.to_string(),
        }))
        .expect_err("missing task should return error");
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "not_found");
    assert_eq!(payload["retryable"], false);
    assert_eq!(payload["details"]["entity_id"], MISSING_TASK_UUID);
    assert!(
        payload["message"]
            .as_str()
            .unwrap()
            .contains(&format!("Task '{MISSING_TASK_UUID}' not found")),
        "message must preserve human-readable prose: {payload}"
    );
}
