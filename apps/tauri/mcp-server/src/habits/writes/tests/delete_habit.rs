//! `delete_habit`: response counts, changelog summary pluralization,
//! cascade tombstones (completions + reminder policies + the habit
//! itself), and the undo-token contract.

use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn delete_habit_returns_completion_count_in_response() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-27");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-28");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-29");
    seed_reminder_policy(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000207",
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "08:00",
    );

    let payload = delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
    )
    .expect("delete habit");
    let result: serde_json::Value = serde_json::from_str(&payload).expect("decode delete result");

    assert_eq!(result["deleted"], true);
    assert_eq!(result["id"], "01966a3f-7c8b-7d4e-8f3a-000000000201");
    assert_eq!(result["name"], "Meditate");
    assert_eq!(result["completions_destroyed"], 3);
    assert_eq!(result["reminder_policies_destroyed"], 1);
}

#[test]
#[serial_test::serial(hlc)]
fn delete_habit_logs_counts_in_changelog_summary() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-27");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-28");
    seed_reminder_policy(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000207",
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "08:00",
    );
    seed_reminder_policy(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000208",
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "20:00",
    );

    delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
    )
    .expect("delete habit");

    let summary: String = conn
        .query_row(
            "SELECT summary FROM ai_changelog
             WHERE entity_type = 'habit' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000201' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("query changelog for habit delete");

    assert!(
        summary.contains("Meditate"),
        "summary should name the habit: {summary}"
    );
    assert!(
        summary.contains("2 completion records"),
        "summary should state pluralized completion count: {summary}"
    );
    assert!(
        summary.contains("2 reminder policies"),
        "summary should state pluralized reminder policy count: {summary}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn delete_habit_emits_tombstones_for_completions() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-27");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-28");
    seed_reminder_policy(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000207",
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "08:00",
    );

    delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
    )
    .expect("delete habit");

    // Every completion must have a tombstone under habit_completion.
    for completed_date in ["2026-03-27", "2026-03-28"] {
        let entity_id = format!("01966a3f-7c8b-7d4e-8f3a-000000000201:{completed_date}");
        let tombstone_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_tombstones
                 WHERE entity_type = 'habit_completion' AND entity_id = ?1",
                params![entity_id],
                |row| row.get(0),
            )
            .expect("count completion tombstones");
        assert_eq!(
            tombstone_count, 1,
            "expected a tombstone for completion {entity_id}"
        );

        let delete_envelope_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = 'habit_completion'
                   AND entity_id = ?1
                   AND operation = 'delete'",
                params![entity_id],
                |row| row.get(0),
            )
            .expect("count completion delete envelopes");
        assert!(
            delete_envelope_count >= 1,
            "expected at least one DELETE envelope for completion {entity_id}"
        );
    }

    let completion_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = 'habit_completion'
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000201:2026-03-27'
               AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("read completion delete payload");
    let completion_payload: serde_json::Value =
        serde_json::from_str(&completion_payload).expect("parse completion payload");
    assert_eq!(
        completion_payload["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000201"
    );
    assert_eq!(completion_payload["completed_date"], "2026-03-27");
    assert_eq!(completion_payload["value"], 1);
    assert_eq!(completion_payload["note"], serde_json::Value::Null);
    assert_eq!(
        completion_payload["created_at"], "2026-03-29T00:00:00Z",
        "cascade delete must preserve the full completion row"
    );
    assert!(completion_payload["version"].as_str().is_some());

    // Reminder policies are tombstoned too for the same reason.
    let policy_tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones
             WHERE entity_type = 'habit_reminder_policy' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000207'",
            [],
            |row| row.get(0),
        )
        .expect("count policy tombstones");
    assert_eq!(policy_tombstone_count, 1);

    let policy_payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = 'habit_reminder_policy'
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000207'
               AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("read policy delete payload");
    let policy_payload: serde_json::Value =
        serde_json::from_str(&policy_payload).expect("parse policy payload");
    assert_eq!(policy_payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000000207");
    assert_eq!(
        policy_payload["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000201"
    );
    assert_eq!(policy_payload["reminder_time"], "08:00");
    assert_eq!(policy_payload["enabled"], true);
    assert_eq!(
        policy_payload["created_at"], "2026-03-29T00:00:00Z",
        "cascade delete must preserve the full reminder policy row"
    );
    assert!(policy_payload["version"].as_str().is_some());

    // The habit row itself is also tombstoned + delete-envelope-enqueued.
    let habit_delete_envelope: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'habit'
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000201'
               AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("count habit delete envelope");
    assert_eq!(habit_delete_envelope, 1);
}

#[test]
#[serial_test::serial(hlc)]
fn delete_habit_with_no_completions_returns_zero_count() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000204", "Journal");

    let payload = delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000204".to_string()),
    )
    .expect("delete habit");
    let result: serde_json::Value = serde_json::from_str(&payload).expect("decode delete result");

    assert_eq!(result["deleted"], true);
    assert_eq!(result["completions_destroyed"], 0);
    assert_eq!(result["reminder_policies_destroyed"], 0);

    // No completion tombstones should exist.
    let completion_tombstones: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'habit_completion'",
            [],
            |row| row.get(0),
        )
        .expect("count completion tombstones");
    assert_eq!(completion_tombstones, 0);

    // No completion DELETE envelopes either.
    let completion_envelopes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'habit_completion' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("count completion delete envelopes");
    assert_eq!(completion_envelopes, 0);

    // Summary should use the singular form with zeros.
    let summary: String = conn
        .query_row(
            "SELECT summary FROM ai_changelog
             WHERE entity_type = 'habit' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000204' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("query changelog for habit delete");
    assert!(
        summary.contains("0 completion records"),
        "summary should report zero completions explicitly: {summary}"
    );
    assert!(
        summary.contains("0 reminder policies"),
        "summary should report zero reminder policies explicitly: {summary}"
    );
}

// delete_habit emits an undo_token carrying the pre-delete habit
// snapshot so a reverse write can re-insert the row.
#[test]
#[serial_test::serial(hlc)]
fn delete_habit_returns_undo_token_with_pre_snapshot() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000205", "Meditate");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000205", "2026-04-18");

    let payload = delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000205".to_string()),
    )
    .expect("delete habit");
    let value: serde_json::Value = serde_json::from_str(&payload).expect("decode delete result");

    let undo_token_raw = value["undo_token"]
        .as_str()
        .expect("delete_habit response must carry undo_token");
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(undo_token_raw).expect("undo_token must be parseable");

    assert_eq!(token.kind, crate::runtime::undo::McpUndoKind::DeleteHabit);
    assert_eq!(
        token.entity_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-000000000205")
    );
    assert_eq!(token.mcp_tool, "delete_habit");

    // The snapshot carries the name so a reverse write can
    // reconstruct the habit row. (Completions are intentionally
    // out of scope — see the undo comment in delete_habit.)
    let snapshot = token
        .pre_entity_json
        .as_ref()
        .expect("pre_entity_json must exist for delete");
    assert_eq!(snapshot.get("name"), Some(&serde_json::json!("Meditate")));
    assert_eq!(
        snapshot.get("version"),
        Some(&serde_json::json!("0000000000000_0000_0000000000000000"))
    );
}

// The top-level habit-delete outbox envelope is enqueued plain
// (immediately dispatchable) and carries the full pre-delete habit
// payload so peers can reconstruct the tombstoned row.
#[test]
#[serial_test::serial(hlc)]
fn delete_habit_enqueues_plain_envelope_with_full_payload() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000206", "Stretch");

    let payload = delete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000206".to_string()),
    )
    .expect("delete habit");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    assert!(
        value["undo_token"].as_str().is_some(),
        "response must carry undo_token"
    );

    let payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'habit' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000206' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("habit delete envelope must exist");

    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("habit delete payload must parse");
    assert_eq!(payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000000206");
    assert_eq!(payload["name"], "Stretch");
    assert_eq!(payload["created_at"], "2026-03-29T00:00:00Z");
    assert_eq!(payload["updated_at"], "2026-03-29T00:00:00Z");
    assert_eq!(payload["version"], "0000000000000_0000_0000000000000000");
}
