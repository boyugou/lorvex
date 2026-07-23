// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

use lorvex_store::open_db_in_memory;

#[test]
fn payload_shadow_promotion_rehydrates_equal_version_known_fields() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, body, defer_count, version, created_at, updated_at)
         VALUES ('task-shadow-promote', 'Shadow task', 'open', NULL, 0, '1711234567890_0201_deadbeefdeadbeef', '2026-03-27T09:00:00Z', '2026-03-27T09:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO sync_payload_shadow
            (entity_type, entity_id, base_version, payload_schema_version, raw_payload_json, updated_at)
         VALUES
            ('task', 'task-shadow-promote', '1711234567890_0201_deadbeefdeadbeef', 1,
             '{\"id\":\"task-shadow-promote\",\"title\":\"Shadow task\",\"status\":\"open\",\"body\":\"Recovered from shadow\",\"defer_count\":0,\"created_at\":\"2026-03-27T09:00:00Z\",\"updated_at\":\"2026-03-27T09:00:00Z\"}',
             '2026-03-27T09:00:00Z')",
        [],
    )
    .unwrap();

    let promoted = lorvex_sync::apply::promote_payload_shadows(&conn).unwrap();
    assert_eq!(promoted, 1);

    let body: Option<String> = conn
        .query_row(
            "SELECT body FROM tasks WHERE id = 'task-shadow-promote'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(body.as_deref(), Some("Recovered from shadow"));

    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_type = 'task' AND entity_id = 'task-shadow-promote'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(remaining, 0);
}
