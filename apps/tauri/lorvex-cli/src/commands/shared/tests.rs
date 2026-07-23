use super::*;
use std::path::PathBuf;

fn payload_map(value: Value) -> Map<String, Value> {
    match value {
        Value::Object(map) => map,
        other => panic!("test fixture must be an object, got {other:?}"),
    }
}

#[test]
fn envelope_prepends_action_and_db_path() {
    let payload = payload_map(json!({ "task": { "id": "t1" }, "extra": 7 }));
    let value = mutation_envelope("task.update", &PathBuf::from("/tmp/db.sqlite"), payload);
    let obj = value.as_object().expect("envelope is object");
    // `serde_json::Map` is BTreeMap-backed under the default
    // (alphabetic) feature, so we don't assert ordering — just
    // that every expected key is present and carries the right
    // value. The wire-shape contract is "envelope contains
    // {action, db_path, ...payload}", not key order.
    assert_eq!(obj["action"], json!("task.update"));
    assert_eq!(obj["db_path"], json!("/tmp/db.sqlite"));
    assert_eq!(obj["task"], json!({ "id": "t1" }));
    assert_eq!(obj["extra"], json!(7));
}

#[test]
fn envelope_overwrites_caller_supplied_action_and_db_path() {
    let payload = payload_map(json!({ "action": "wrong", "db_path": "/wrong", "id": "x" }));
    let value = mutation_envelope("focus.set", &PathBuf::from("/right"), payload);
    assert_eq!(value["action"], json!("focus.set"));
    assert_eq!(value["db_path"], json!("/right"));
    assert_eq!(value["id"], json!("x"));
}

/// `render_mutation_envelope` now returns a
/// typed `CliError` instead of panicking on a non-object
/// payload. Pre-fix the helper crashed the CLI process; the
/// typed signature on `mutation_envelope` itself makes the
/// invariant compile-time, while this surface keeps the same
/// `serde_json::Value` ergonomics for callers who build payloads
/// from `json!(...)`.
#[test]
fn render_envelope_returns_typed_error_on_non_object_payload() {
    let err = render_mutation_envelope("x.y", &PathBuf::from("/tmp"), json!([1, 2, 3]))
        .expect_err("non-object payload must produce a typed CliError");
    let msg = format!("{err}");
    assert!(
        msg.contains("requires a JSON object payload"),
        "diagnostic should describe the contract, got: {msg}"
    );
}
