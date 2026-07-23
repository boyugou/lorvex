use super::*;

#[test]
fn two_device_conflict_matrix_preserves_deterministic_tie_break_order() {
    // With the lorvex-sync pipeline, deletes actually remove the row and
    // create tombstones. Scenarios involving delete as the winner result in
    // the task row being absent (task_status returns None).

    struct Scenario {
        name: &'static str,
        device_a_operation: &'static str,
        device_a_title: &'static str,
        device_z_operation: &'static str,
        device_z_title: &'static str,
        // None means the task should be deleted (row absent).
        expected_status: Option<&'static str>,
        expected_title: Option<&'static str>,
    }

    let scenarios = [
        Scenario {
            name: "upsert_vs_upsert",
            device_a_operation: "upsert",
            device_a_title: "device-a upsert",
            device_z_operation: "upsert",
            device_z_title: "device-z upsert",
            expected_status: Some("open"),
            expected_title: Some("device-z upsert"),
        },
        Scenario {
            name: "upsert_vs_delete",
            device_a_operation: "upsert",
            device_a_title: "device-a upsert",
            device_z_operation: "delete",
            device_z_title: "device-z delete",
            // Delete is newer (device-z at 09:00:01) -> task is removed.
            expected_status: None,
            expected_title: None,
        },
        Scenario {
            name: "delete_vs_upsert",
            device_a_operation: "delete",
            device_a_title: "device-a delete",
            device_z_operation: "upsert",
            device_z_title: "device-z upsert",
            // Upsert is newer (device-z at 09:00:01) -> task exists.
            expected_status: Some("open"),
            expected_title: Some("device-z upsert"),
        },
        Scenario {
            name: "delete_vs_delete",
            device_a_operation: "delete",
            device_a_title: "device-a delete",
            device_z_operation: "delete",
            device_z_title: "device-z delete",
            // Both delete -> task is removed.
            expected_status: None,
            expected_title: None,
        },
    ];

    let make_payload = |task_id: &str, title: &str, status: &str| {
        json!({
            "id": task_id,
            "title": title,
            "status": status,
            "created_at": "2026-03-02T08:00:00Z"
        })
    };

    for (index, scenario) in scenarios.iter().enumerate() {
        let task_id = format!("01966a3f-7c8b-7d4e-8f3a-{index:012x}");
        // device-z has a slightly newer timestamp to ensure it wins the LWW tie-break.
        let event_a = make_sync_event(
            &format!("evt-a-{index}"),
            "task",
            &task_id,
            scenario.device_a_operation,
            make_payload(&task_id, scenario.device_a_title, "open"),
            "2026-03-02T09:00:00Z",
            "device-a",
        );
        let event_z = make_sync_event(
            &format!("evt-z-{index}"),
            "task",
            &task_id,
            scenario.device_z_operation,
            make_payload(&task_id, scenario.device_z_title, "open"),
            "2026-03-02T09:00:01Z",
            "device-z",
        );

        let conn_forward = setup_sync_test_conn();
        apply_remote_sync_envelopes_internal(
            &conn_forward,
            vec![event_a.clone(), event_z.clone()],
            "2026-03-02T10:00:00Z",
        )
        .unwrap_or_else(|_| panic!("apply forward order for {}", scenario.name));
        let forward_status = task_status(&conn_forward, &task_id);
        let forward_title = task_title(&conn_forward, &task_id);

        let conn_reverse = setup_sync_test_conn();
        apply_remote_sync_envelopes_internal(
            &conn_reverse,
            vec![event_z, event_a],
            "2026-03-02T10:00:00Z",
        )
        .unwrap_or_else(|_| panic!("apply reverse order for {}", scenario.name));
        let reverse_status = task_status(&conn_reverse, &task_id);
        let reverse_title = task_title(&conn_reverse, &task_id);

        // Both orderings must produce the same result (determinism).
        assert_eq!(
            forward_status, reverse_status,
            "status ordering drifted in scenario {}",
            scenario.name
        );
        assert_eq!(
            forward_title, reverse_title,
            "title ordering drifted in scenario {}",
            scenario.name
        );

        assert_eq!(
            forward_status,
            scenario
                .expected_status
                .map(std::string::ToString::to_string),
            "unexpected status in scenario {}",
            scenario.name
        );
        assert_eq!(
            forward_title,
            scenario
                .expected_title
                .map(std::string::ToString::to_string),
            "unexpected title in scenario {}",
            scenario.name
        );
    }
}
