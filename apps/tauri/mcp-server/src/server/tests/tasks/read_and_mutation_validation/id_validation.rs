use super::support::side_effect_row_counts;
use super::*;

#[test]
#[serial_test::serial(hlc)]
fn single_task_id_tools_reject_malformed_uuid_before_side_effects() {
    let server = make_server();
    let before_counts = side_effect_row_counts(&server);

    let err = server
        .complete_task(Parameters(CompleteTaskArgs {
            id: "not-a-uuid".to_string(),
            idempotency_key: None,
        }))
        .expect_err("malformed complete_task id should be rejected at the boundary");
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("validation error must be structured JSON");
    assert_eq!(payload["code"], "validation");
    assert!(
        payload["message"]
            .as_str()
            .unwrap()
            .contains("id is not a valid UUID"),
        "unexpected complete_task validation payload: {payload}"
    );

    let err = server
        .add_task_checklist_item(Parameters(AddTaskChecklistItemArgs {
            id: "not-a-uuid".to_string(),
            text: "Boundary guard".to_string(),
            position: None,
            idempotency_key: None,
        }))
        .expect_err("malformed checklist task id should be rejected at the boundary");
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("validation error must be structured JSON");
    assert_eq!(payload["code"], "validation");

    let err = server
        .add_task_reminder(Parameters(AddTaskReminderArgs {
            id: "not-a-uuid".to_string(),
            reminder_at: "2026-05-01T12:00:00Z".to_string(),
            idempotency_key: None,
        }))
        .expect_err("malformed reminder task id should be rejected at the boundary");
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("validation error must be structured JSON");
    assert_eq!(payload["code"], "validation");

    let err = server
        .set_recurrence(Parameters(SetRecurrenceArgs {
            id: "not-a-uuid".to_string(),
            rule: RecurrenceRuleArgs {
                freq: RecurrenceFreq::Daily,
                interval: Some(1),
                byday: None,
                bymonth: None,
                bymonthday: None,
                bysetpos: None,
                wkst: None,
                count: None,
                until: None,
            },
            idempotency_key: None,
        }))
        .expect_err("malformed recurrence task id should be rejected at the boundary");
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("validation error must be structured JSON");
    assert_eq!(payload["code"], "validation");

    assert_eq!(
        side_effect_row_counts(&server),
        before_counts,
        "invalid single task IDs must not write changelog or outbox rows"
    );
}
