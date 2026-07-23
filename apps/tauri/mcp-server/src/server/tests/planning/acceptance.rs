use super::super::*;

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_applies_current_focus() {
    let server = make_server();
    let date = today_ymd_local_for_test();
    // task_ids in focus-schedule blocks now validate
    // against the trust boundary's UUID-shape + existence rules, so
    // seed real UUIDs and reference them from the blocks.
    let task_a = uuid::Uuid::now_v7().to_string();
    let task_b = uuid::Uuid::now_v7().to_string();

    seed_task(
        &server,
        &task_a,
        "Schedule Task 1",
        "open",
        None,
        Some(&date),
        None,
        0,
    );
    seed_task(
        &server,
        &task_b,
        "Schedule Task 2",
        "open",
        None,
        Some(&date),
        None,
        0,
    );

    let saved_payload = server
        .save_focus_schedule(Parameters(SaveFocusScheduleArgs {
            date: Some(date.clone()),
            blocks: vec![
                FocusScheduleBlockInput {
                    task_id: Some(task_a),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                    block_type: ScheduleBlockType::Task,
                },
                FocusScheduleBlockInput {
                    task_id: None,
                    start_time: "10:10".to_string(),
                    end_time: "10:20".to_string(),
                    block_type: ScheduleBlockType::Buffer,
                },
                FocusScheduleBlockInput {
                    task_id: Some(task_b),
                    start_time: "10:20".to_string(),
                    end_time: "10:50".to_string(),
                    block_type: ScheduleBlockType::Task,
                },
            ],
            rationale: Some("Morning sprint".to_string()),
            idempotency_key: None,
        }))
        .expect("save focus schedule");
    let saved: Value = serde_json::from_str(&saved_payload).expect("valid json");

    // Save directly applies task blocks to current_focus — no accept step needed
    assert_eq!(
        saved["task_ids_applied"].as_array().expect("applied").len(),
        2
    );

    // Verify blocks are stored
    assert_eq!(saved["blocks"].as_array().expect("blocks").len(), 3);

    // Verify current_focus was created via with_conn
    let plan = server
        .with_conn(|conn| {
            query_one_as_json(
                conn,
                "SELECT date FROM current_focus WHERE date = ?",
                [date.clone()],
            )
            .map_err(to_error_message)
        })
        .expect("query current focus");
    assert!(plan.is_some(), "current_focus should exist after save");
}
