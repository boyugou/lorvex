use super::*;

#[test]
#[serial_test::serial(hlc)]
fn validate_required_vec_count_rejects_over_limit() {
    let items: Vec<String> = (0..25).map(|i| format!("item-{i}")).collect();
    let result = validate_required_vec_count(&items, "reminders", 20);
    assert!(result.is_err());
    let err = result.unwrap_err().to_string();
    assert!(err.contains("25 items"));
    assert!(err.contains("limit 20"));
}

#[test]
#[serial_test::serial(hlc)]
fn validate_batch_ids_accepts_valid_batch() {
    let ids = vec!["id-1".to_string(), "id-2".to_string()];
    assert!(validate_batch_ids(&ids, "test_tool").is_ok());
}

#[test]
#[serial_test::serial(hlc)]
fn validate_batch_ids_rejects_empty() {
    let result = validate_batch_ids(&[], "test_tool");
    assert!(result.is_err());
    let err = result.unwrap_err().to_string();
    assert!(err.contains("test_tool"));
    assert!(err.contains("at least one ID"));
}

#[test]
#[serial_test::serial(hlc)]
fn validate_batch_ids_rejects_over_limit() {
    let ids: Vec<String> = (0..501).map(|i| format!("id-{i}")).collect();
    let result = validate_batch_ids(&ids, "test_tool");
    assert!(result.is_err());
    let err = result.unwrap_err().to_string();
    assert!(err.contains("501"));
    assert!(err.contains("500"));
}

/// duplicate ids must be rejected wholesale rather
/// than silently deduped by the downstream `IN (...)` predicate.
#[test]
#[serial_test::serial(hlc)]
fn validate_batch_ids_rejects_duplicates() {
    let ids = vec!["t1".to_string(), "t2".to_string(), "t1".to_string()];
    let err = validate_batch_ids(&ids, "test_tool").expect_err("duplicate ids must be rejected");
    let msg = err.to_string();
    assert!(msg.contains("duplicate"), "unexpected error: {msg}");
    assert!(
        msg.contains("'t1'"),
        "error should name the duplicate id: {msg}"
    );
}
