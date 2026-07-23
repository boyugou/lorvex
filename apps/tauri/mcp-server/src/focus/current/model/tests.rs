use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn enrich_current_focus_row_rejects_missing_date() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    let error = enrich_current_focus_row(&conn, json!({}))
        .expect_err("missing date should fail")
        .to_string();
    assert!(error.contains("missing date"), "unexpected error: {error}");
}
