use super::*;
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_args_reject_string_allow_replace_pending() {
    let err = serde_json::from_value::<ControlAppUiArgs>(json!({
        "action": "enter_focus_mode",
        "allow_replace_pending": "false"
    }))
    .expect_err("string allow_replace_pending should be rejected");

    assert!(err.to_string().contains("boolean"));
}
