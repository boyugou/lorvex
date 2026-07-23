use super::seed_orchestrator::seed_full_sync_internal;
use crate::test_support::test_conn;

fn setup_seed_test_conn() -> rusqlite::Connection {
    test_conn()
}

#[test]
fn seed_full_sync_internal_marks_seed_checkpoint() {
    let conn = setup_seed_test_conn();

    let result = seed_full_sync_internal(&conn).expect("seed full sync");

    assert_eq!(result.tasks_enqueued, 0);

    let seeded = lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
        .expect("load seed checkpoint")
        .expect("seed checkpoint row");
    assert_eq!(seeded, "1");
}

#[test]
fn seed_full_sync_internal_enqueues_calendar_subscription_definitions() {
    let conn = setup_seed_test_conn();
    let subscription_id = "01966a3f-7c8b-7d4e-8f3a-000000004318";
    conn.execute(
        "INSERT INTO calendar_subscriptions
            (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES
            (?1, 'Seeded ICS', 'https://example.com/seeded.ics', '#336699', 1,
             '0000000000000_0000_a0a0a0a0a0a0a0a0',
             '2026-04-01T00:00:00.000Z', '2026-04-02T00:00:00.000Z')",
        rusqlite::params![subscription_id],
    )
    .expect("seed subscription");

    let result = seed_full_sync_internal(&conn).expect("seed full sync");

    assert_eq!(result.calendar_subscriptions_enqueued, 1);
    let payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = 'calendar_subscription' AND entity_id = ?1 AND operation = 'upsert'",
            rusqlite::params![subscription_id],
            |row| row.get(0),
        )
        .expect("load seeded subscription payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_raw).expect("payload should be JSON");
    assert_eq!(payload["id"], subscription_id);
    assert_eq!(payload["name"], "Seeded ICS");
    assert_eq!(payload["url"], "https://example.com/seeded.ics");
    assert_eq!(payload["enabled"], true);
    assert!(payload.get("next_retry_at").is_none());
    assert!(payload.get("consecutive_failures").is_none());
    assert!(payload.get("last_retry_after_hint").is_none());
}

#[test]
fn seed_full_sync_internal_rejects_second_seed_attempt() {
    let conn = setup_seed_test_conn();

    seed_full_sync_internal(&conn).expect("first seed succeeds");
    let error = seed_full_sync_internal(&conn).expect_err("second seed should fail");

    assert_eq!(
        error.to_string(),
        "Full sync has already been seeded. To re-seed, clear the 'full_sync_seeded' flag in sync_checkpoints."
    );
}

#[test]
fn seed_full_sync_internal_rejects_malformed_preference_json() {
    let conn = setup_seed_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, updated_at, version)
         VALUES ('theme', '{not-valid-json', '2026-03-29T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        [],
    )
    .expect("insert malformed preference");

    let error = seed_full_sync_internal(&conn)
        .expect_err("malformed preference should fail seed_full_sync");

    let message = error.to_string();
    assert!(message.contains("theme"), "unexpected error: {message}");
}
