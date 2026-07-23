//! `complete_habit` / `uncomplete_habit`: completion-snapshot lookup
//! failures must surface (and abort the write) instead of degrading
//! into a not-found error, and the changelog `before_json` /
//! `after_json` must carry the full completion-row state.

use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn complete_habit_surfaces_completion_snapshot_lookup_failures() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    deny_habit_completion_reads(&conn);

    let error = complete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
        Some("2026-03-29"),
        None,
    )
    .expect_err("completion snapshot lookup failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("internal error"),
        "unexpected error: {message}"
    );
    assert!(
        !message.contains("not found"),
        "database failure must not degrade into not-found error: {message}"
    );

    clear_authorizer(&conn);
    let completion_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_completions WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000000201'",
            [],
            |row| row.get(0),
        )
        .expect("count completions");
    assert_eq!(
        completion_count, 0,
        "failed snapshot lookup must abort before writing completion"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn uncomplete_habit_surfaces_completion_snapshot_lookup_failures_without_deleting() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_completion(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "2026-03-29");
    deny_habit_completion_reads(&conn);

    let error = uncomplete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
        Some("2026-03-29"),
    )
    .expect_err("completion snapshot lookup failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("internal error"),
        "unexpected error: {message}"
    );
    assert!(
        !message.contains("not found"),
        "database failure must not degrade into not-found error: {message}"
    );

    clear_authorizer(&conn);
    let completion_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_completions
             WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000000201' AND completed_date = '2026-03-29'",
            [],
            |row| row.get(0),
        )
        .expect("count completions");
    assert_eq!(
        completion_count, 1,
        "failed snapshot lookup must not delete completion"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn complete_habit_changelog_uses_full_completion_state() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.execute(
        "UPDATE habits SET target_count = 2 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000201'",
        [],
    )
    .expect("raise target count");
    seed_completion_with_note(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "2026-03-29",
        Some("before"),
    );

    complete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
        Some("2026-03-29"),
        Some("after"),
    )
    .expect("complete habit");

    let (before_json, after_json): (String, String) = conn
        .query_row(
            "SELECT before_json, after_json FROM ai_changelog
             WHERE entity_type = 'habit_completion'
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000201:2026-03-29'
               AND operation = 'complete'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read completion changelog");
    let before_json: serde_json::Value =
        serde_json::from_str(&before_json).expect("parse before_json");
    let after_json: serde_json::Value =
        serde_json::from_str(&after_json).expect("parse after_json");

    assert_eq!(
        before_json["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000201"
    );
    assert_eq!(before_json["completed_date"], "2026-03-29");
    assert_eq!(before_json["value"], 1);
    assert_eq!(before_json["note"], "before");
    assert_eq!(
        before_json["version"],
        "0000000000000_0000_0000000000000000"
    );
    assert_eq!(before_json["created_at"], "2026-03-29T00:00:00Z");
    assert_eq!(before_json["updated_at"], "2026-03-29T00:00:00Z");

    assert_eq!(
        after_json["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000201"
    );
    assert_eq!(after_json["completed_date"], "2026-03-29");
    assert_eq!(after_json["value"], 2);
    assert_eq!(after_json["note"], "after");
    assert!(after_json["version"].as_str().is_some());
    assert_eq!(after_json["created_at"], "2026-03-29T00:00:00Z");
    assert!(after_json["updated_at"].as_str().is_some());
}

#[test]
#[serial_test::serial(hlc)]
fn uncomplete_habit_changelog_uses_full_completion_state() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_completion_with_note(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000201",
        "2026-03-29",
        Some("done"),
    );

    uncomplete_habit(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
        Some("2026-03-29"),
    )
    .expect("uncomplete habit");

    let before_json: String = conn
        .query_row(
            "SELECT before_json FROM ai_changelog
             WHERE entity_type = 'habit_completion'
               AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000201:2026-03-29'
               AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("read completion changelog");
    let before_json: serde_json::Value =
        serde_json::from_str(&before_json).expect("parse before_json");

    assert_eq!(
        before_json["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000201"
    );
    assert_eq!(before_json["completed_date"], "2026-03-29");
    assert_eq!(before_json["value"], 1);
    assert_eq!(before_json["note"], "done");
    assert_eq!(
        before_json["version"],
        "0000000000000_0000_0000000000000000"
    );
    assert_eq!(before_json["created_at"], "2026-03-29T00:00:00Z");
    assert_eq!(before_json["updated_at"], "2026-03-29T00:00:00Z");
}
