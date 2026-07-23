use super::super::*;
use super::support::*;

fn make_parent_task_envelope(task_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: task_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234569999_0000_b1b2c3d4b1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: serde_json::json!({
            "title": "Recovered parent",
            "status": "open",
            "defer_count": 0,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        })
        .to_string(),
        device_id: "device-001".to_string(),
    }
}

#[test]
fn drain_reaches_old_parent_after_first_capped_child_batch() {
    let conn = test_db();
    let parent_task_id = "01966a3f-7c8b-7d4e-8f3a-00000000218d";

    for idx in 0..500 {
        let env = make_reminder_envelope_with_missing_task(
            &format!("reminder-capped-prefix-{idx:03}"),
            parent_task_id,
        );
        enqueue_pending(
            &conn,
            &env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some(parent_task_id),
        )
        .unwrap();
    }

    let parent = make_parent_task_envelope(parent_task_id);
    enqueue_pending(&conn, &parent, "queued_parent", None, None).unwrap();
    conn.execute(
        "UPDATE sync_pending_inbox
         SET first_attempted_at = '2026-01-01T00:00:00.000Z',
             last_attempted_at = '2026-01-01T00:00:00.000Z'",
        [],
    )
    .unwrap();

    let first = drain_pending_inbox(&conn).unwrap();
    assert_eq!(first.replayed, 0);

    let second = drain_pending_inbox(&conn).unwrap();
    assert!(
        second.replayed >= 1,
        "second pass must reach the parent instead of retrying the same capped child prefix"
    );

    let parent_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            params![parent_task_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        parent_count, 1,
        "parent task should have applied by pass two"
    );
}
