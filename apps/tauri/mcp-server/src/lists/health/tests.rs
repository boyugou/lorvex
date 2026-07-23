use super::extract_and_remove_total_lists;
use crate::system::diagnostics::clamp_rows_text_field;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn extract_and_remove_total_lists_returns_zero_for_empty_rows() {
    let mut rows = Vec::new();
    let total = extract_and_remove_total_lists(&mut rows).expect("empty rows should succeed");
    assert_eq!(total, 0);
}

#[test]
#[serial_test::serial(hlc)]
fn extract_and_remove_total_lists_rejects_nonempty_rows_without_count() {
    let mut rows = vec![json!({
        "id": "list-1",
        "name": "Inbox",
    })];

    let error = extract_and_remove_total_lists(&mut rows)
        .expect_err("missing total_lists should fail")
        .to_string();
    assert!(error.contains("total_lists"));
}

#[test]
#[serial_test::serial(hlc)]
fn extract_and_remove_total_lists_removes_projection_field() {
    let mut rows = vec![
        json!({"id": "list-1", "name": "Inbox", "total_lists": 3}),
        json!({"id": "list-2", "name": "Work", "total_lists": 3}),
    ];

    let total = extract_and_remove_total_lists(&mut rows).expect("rows should succeed");

    assert_eq!(total, 3);
    assert!(rows[0].get("total_lists").is_none());
    assert!(rows[1].get("total_lists").is_none());
}

#[test]
#[serial_test::serial(hlc)]
fn clamp_rows_text_field_compacts_and_truncates_present_strings_only() {
    let mut rows = vec![
        json!({"name": "  Inbox   Tasks  "}),
        json!({"name": null}),
        json!({"other": "value"}),
    ];

    clamp_rows_text_field(&mut rows, "name", 5);

    assert_eq!(rows[0]["name"], "Inbox...");
    assert!(rows[1]["name"].is_null());
    assert_eq!(rows[2]["other"], "value");
}
