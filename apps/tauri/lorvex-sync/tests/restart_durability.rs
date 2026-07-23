// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

use rusqlite::Connection;

use lorvex_domain::naming;
use lorvex_store::open_db_at_path;
use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};
use lorvex_sync::outbox;
use lorvex_sync::pending_inbox;

fn upsert_envelope(
    entity_type: &str,
    entity_id: &str,
    version: &str,
    payload: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: payload.to_string(),
        device_id: "restart-test-device".to_string(),
    }
}

fn seed_task(conn: &Connection, task_id: &str) {
    // delegate to the shared TaskBuilder. The custom
    // title and timestamp keep the test's identity-of-the-recovered-row
    // assertion intact.
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title("Recovered Task")
        .created_at("2026-04-20T09:00:00.000Z")
        .insert(conn);
}

#[test]
fn restart_preserves_pending_outbox_and_pending_inbox_bytes_and_allows_replay() {
    let dir = tempfile::tempdir().expect("create tempdir");
    let db_path = dir.path().join("restart-durability.sqlite");
    const OUTBOX_TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000005101";
    const OUTBOX_TASK_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000005102";
    const REMINDER_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000005103";
    const MISSING_TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000005104";

    let outbox_env_1 = upsert_envelope(
        naming::ENTITY_TASK,
        OUTBOX_TASK_1,
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        r#"{"title":"Outbox One","status":"open","defer_count":0,"list_id":"inbox","created_at":"2026-04-20T09:00:00.000Z","updated_at":"2026-04-20T09:00:00.000Z"}"#,
    );
    let outbox_env_2 = upsert_envelope(
        naming::ENTITY_TASK,
        OUTBOX_TASK_2,
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{"title":"Outbox Two","status":"open","defer_count":0,"list_id":"inbox","created_at":"2026-04-20T09:01:00.000Z","updated_at":"2026-04-20T09:01:00.000Z"}"#,
    );
    let pending_env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        REMINDER_ID,
        "1711234569000_0000_a1b2c3d4a1b2c3d4",
        &format!(
            r#"{{"task_id":"{MISSING_TASK_ID}","reminder_at":"2026-04-21T09:00:00Z","created_at":"2026-04-20T09:02:00.000Z"}}"#
        ),
    );

    {
        let conn = open_db_at_path(&db_path).expect("initialize db");
        outbox::enqueue(&conn, &outbox_env_1).expect("enqueue outbox 1");
        outbox::enqueue(&conn, &outbox_env_2).expect("enqueue outbox 2");
        pending_inbox::enqueue_pending(
            &conn,
            &pending_env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some(MISSING_TASK_ID),
        )
        .expect("enqueue pending inbox row");

        conn.execute(
            "UPDATE sync_pending_inbox
             SET first_attempted_at = '2026-04-18T00:00:00.000Z',
                 last_attempted_at = '2026-04-19T00:00:00.000Z'
             WHERE id = (SELECT id FROM sync_pending_inbox LIMIT 1)",
            [],
        )
        .expect("pin pending inbox timestamps");
    }

    let reopened = open_db_at_path(&db_path).expect("reopen db");

    let outbox_rows = outbox::get_pending(&reopened).expect("load pending outbox rows");
    assert_eq!(
        outbox_rows.len(),
        2,
        "both pending outbox rows must survive restart"
    );
    // `get_pending` returns rows in FIFO (id ASC) order.
    assert_eq!(outbox_rows[0].envelope.entity_id, OUTBOX_TASK_1);
    assert_eq!(outbox_rows[0].envelope.payload, outbox_env_1.payload);
    assert_eq!(outbox_rows[0].envelope.version, outbox_env_1.version);
    assert_eq!(outbox_rows[1].envelope.entity_id, OUTBOX_TASK_2);
    assert_eq!(outbox_rows[1].envelope.payload, outbox_env_2.payload);
    assert_eq!(outbox_rows[1].envelope.version, outbox_env_2.version);

    let pending_rows = pending_inbox::get_all_pending(&reopened).expect("load pending inbox rows");
    assert_eq!(pending_rows.len(), 1);
    let pending = &pending_rows[0];
    assert_eq!(
        pending.envelope_json,
        serde_json::to_string(&pending_env).unwrap()
    );
    assert_eq!(pending.reason, naming::RESOLUTION_FK_UNRESOLVED);
    assert_eq!(
        pending.missing_entity_type.as_deref(),
        Some(naming::ENTITY_TASK)
    );
    assert_eq!(pending.missing_entity_id.as_deref(), Some(MISSING_TASK_ID));
    assert_eq!(pending.first_attempted_at, "2026-04-18T00:00:00.000Z");
    assert_eq!(pending.last_attempted_at, "2026-04-19T00:00:00.000Z");
    assert_eq!(
        pending.parse_envelope().unwrap().payload,
        pending_env.payload
    );
    assert!(
        pending_inbox::has_expired_entries(&reopened, 1).expect("check expiry horizon"),
        "pre-restart pending timestamps must survive and still look expired"
    );

    seed_task(&reopened, MISSING_TASK_ID);
    // `drain_pending_inbox` calls `apply_envelope`
    // which debug_asserts an outer transaction.
    reopened
        .execute_batch("BEGIN IMMEDIATE")
        .expect("BEGIN IMMEDIATE for drain");
    let summary = pending_inbox::drain_pending_inbox(&reopened).expect("drain pending inbox");
    reopened.execute_batch("COMMIT").expect("commit drain");
    assert_eq!(summary.replayed, 1);
    assert_eq!(
        pending_inbox::count_pending(&reopened).expect("count pending after drain"),
        0
    );

    let reminder_task_id: String = reopened
        .query_row(
            "SELECT task_id FROM task_reminders WHERE id = ?1",
            [REMINDER_ID],
            |row| row.get(0),
        )
        .expect("reminder should replay after restart");
    assert_eq!(reminder_task_id, MISSING_TASK_ID);
}
