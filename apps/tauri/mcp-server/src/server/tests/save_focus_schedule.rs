//! router-dispatch tests for `save_focus_schedule`.

use super::*;

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_via_router_persists_blocks_and_logs_audit() {
    let server = make_server();
    let task_id = "01900000-7777-7000-8000-000000003006".to_string();
    seed_task(
        &server,
        &task_id,
        "Write tests",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .save_focus_schedule(Parameters(SaveFocusScheduleArgs {
            date: Some("2026-04-28".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    task_id: Some(task_id),
                    start_time: "09:00".to_string(),
                    end_time: "10:30".to_string(),
                    block_type: ScheduleBlockType::Task,
                },
                FocusScheduleBlockInput {
                    // Buffer block — no task_id required (#2966-M3).
                    task_id: None,
                    start_time: "10:30".to_string(),
                    end_time: "10:45".to_string(),
                    block_type: ScheduleBlockType::Buffer,
                },
            ],
            rationale: Some("Morning deep-work block then a recovery buffer.".to_string()),
            idempotency_key: None,
        }))
        .expect("save_focus_schedule should succeed");
    let parsed: Value = serde_json::from_str(&response).expect("parse save_focus_schedule");
    assert_eq!(parsed.get("date"), Some(&Value::from("2026-04-28")));
    let blocks = parsed
        .get("blocks")
        .and_then(Value::as_array)
        .expect("blocks array");
    assert_eq!(blocks.len(), 2);

    // Audit log row.
    let log_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'save_focus_schedule'",
                [],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("count ai_changelog");
    assert!(
        log_count >= 1,
        "save_focus_schedule must log at least one ai_changelog row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_via_router_rejects_task_block_without_task_id() {
    let server = make_server();

    let err = server
        .save_focus_schedule(Parameters(SaveFocusScheduleArgs {
            date: Some("2026-04-28".to_string()),
            blocks: vec![FocusScheduleBlockInput {
                task_id: None,
                start_time: "09:00".to_string(),
                end_time: "10:00".to_string(),
                // a `task` block with no task_id is
                // a contract violation — the router-level rejection
                // protects the downstream `materialize_blocks` from
                // a None task_id ride-through.
                block_type: ScheduleBlockType::Task,
            }],
            rationale: None,
            idempotency_key: None,
        }))
        .expect_err("task block without task_id must be rejected");
    assert!(
        !err.is_empty(),
        "router must surface a typed rejection diagnostic"
    );
}
