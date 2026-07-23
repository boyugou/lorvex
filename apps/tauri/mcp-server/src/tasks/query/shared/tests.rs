use super::{insert_object_field, rows_to_values};
use serde::ser::{Error as _, Serialize, Serializer};
use serde_json::{json, Value};

#[derive(serde::Serialize)]
struct GoodRow {
    title: &'static str,
}

struct BadRow;

impl Serialize for BadRow {
    fn serialize<S>(&self, _serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        Err(S::Error::custom("boom"))
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rows_to_values_serializes_task_rows() {
    let values = rows_to_values(vec![GoodRow { title: "Task" }], "task rows")
        .expect("serializable rows should succeed");

    assert_eq!(values, vec![json!({ "title": "Task" })]);
}

#[test]
#[serial_test::serial(hlc)]
fn rows_to_values_surfaces_serialization_failures() {
    let error = rows_to_values(vec![BadRow], "task rows")
        .expect_err("serialization failures should surface")
        .to_string();

    assert!(error.contains("task rows"), "unexpected error: {error}");
    assert!(error.contains("boom"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn insert_object_field_rejects_non_object_payloads() {
    let mut payload = Value::Array(Vec::new());
    let error = insert_object_field(&mut payload, "query", Value::String("x".to_string()))
        .expect_err("non-object payloads should be rejected")
        .to_string();

    assert!(error.contains("JSON object"), "unexpected error: {error}");
}
