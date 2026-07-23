use super::{required_existing_bool_field, required_existing_string_field};
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn required_existing_string_field_rejects_blank_string() {
    let row = json!({ "start_date": "" });
    let object = row.as_object().expect("object");

    let error = required_existing_string_field(object, "start_date")
        .expect_err("blank start_date should fail")
        .to_string();
    assert!(error.contains("start_date"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn required_existing_bool_field_rejects_non_boolean_number() {
    let row = json!({ "all_day": 2 });
    let object = row.as_object().expect("object");

    let error = required_existing_bool_field(object, "all_day")
        .expect_err("non-boolean all_day should fail")
        .to_string();
    assert!(error.contains("all_day"), "unexpected error: {error}");
}
