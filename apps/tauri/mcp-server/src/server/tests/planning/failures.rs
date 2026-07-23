use super::super::*;

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_empty_blocks_returns_error() {
    let server = make_server();

    let err = server
        .save_focus_schedule(Parameters(SaveFocusScheduleArgs {
            date: None,
            blocks: vec![],
            rationale: None,
            idempotency_key: None,
        }))
        .expect_err("empty blocks should fail");
    assert!(err.contains("at least 1 item"));
}
