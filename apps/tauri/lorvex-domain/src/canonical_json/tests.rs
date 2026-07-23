use super::*;
use serde_json::json;

fn canon(value: &Value) -> String {
    canonicalize_json(value).expect("test payloads must canonicalize successfully")
}

#[test]
fn sorted_keys_in_output() {
    let v = json!({"z": 1, "a": 2, "m": 3});
    assert_eq!(canon(&v), r#"{"a":2,"m":3,"z":1}"#);
}

#[test]
fn nested_objects_sorted_recursively() {
    let v = json!({"outer_b": {"inner_z": 1, "inner_a": 2}, "outer_a": "value"});
    assert_eq!(
        canon(&v),
        r#"{"outer_a":"value","outer_b":{"inner_a":2,"inner_z":1}}"#
    );
}

#[test]
fn arrays_preserve_order() {
    let v = json!({"items": [3, 1, 2]});
    assert_eq!(canon(&v), r#"{"items":[3,1,2]}"#);
}

#[test]
fn depth_overflow_errors_cleanly() {
    // Build a value with depth = MAX_JSON_DEPTH (one level past
    // the cap). With #3051 M14's `>=` gate this rejects on the
    // first level past the contract.
    let mut nested = json!(0);
    for _ in 0..MAX_JSON_DEPTH {
        nested = json!([nested]);
    }
    match canonicalize_json(&nested) {
        Err(CanonError::DepthExceeded) => {}
        other => panic!("expected DepthExceeded, got {other:?}"),
    }
}

/// #3051 M14 boundary: a value that nests exactly to
/// `MAX_JSON_DEPTH - 1` (the deepest legal level) must
/// canonicalize successfully. Pre-fix `if depth > MAX_JSON_DEPTH`
/// silently accepted ONE EXTRA level past the documented cap;
/// post-fix `if depth >= MAX_JSON_DEPTH` matches the doc-comment
/// contract that the half-open range `0..MAX_JSON_DEPTH` is the
/// accepted set.
#[test]
fn depth_at_boundary_canonicalizes_successfully() {
    // Outer-most array is depth 0; each `json!([...])` adds 1.
    // After `MAX_JSON_DEPTH - 1` wraps the deepest scalar sits
    // at depth `MAX_JSON_DEPTH - 1`.
    let mut nested = json!(0);
    for _ in 0..(MAX_JSON_DEPTH - 1) {
        nested = json!([nested]);
    }
    canonicalize_json(&nested).expect("depth = MAX_JSON_DEPTH - 1 must canonicalize");
}

#[test]
fn parity_with_sync_layer_for_simple_payload() {
    // Cross-check against the canonical example used in the
    // sync-layer test suite — the two implementations must
    // produce byte-identical output for any common input.
    let v = json!({"title": "Buy milk", "status": "open", "priority": 2});
    assert_eq!(
        canon(&v),
        r#"{"priority":2,"status":"open","title":"Buy milk"}"#
    );
}
