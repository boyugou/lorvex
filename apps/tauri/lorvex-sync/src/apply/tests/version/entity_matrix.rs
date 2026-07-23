use super::fixtures::*;
use super::*;

#[test]
fn memory_entry_lww_older_version_rejected() {
    let conn = test_db();
    seed_memory_row(&conn, "timezone", "local-note", LWW_V_NEW);

    let env = make_memory_envelope("timezone", LWW_V_OLD, "remote-stale");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let (content, version): (String, String) = conn
        .query_row(
            "SELECT content, version FROM memories WHERE key = 'timezone'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(content, "local-note");
    assert_eq!(version, LWW_V_NEW);
}

#[test]
fn memory_entry_tombstoned_newer_payload_skipped() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_MEMORY,
        "timezone",
        LWW_V_NEW,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_memory_envelope("timezone", LWW_V_OLD, "remote-stale");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memories WHERE key = 'timezone'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
    assert!(crate::tombstone::is_tombstoned(&conn, naming::ENTITY_MEMORY, "timezone").unwrap());
}

#[test]
fn memory_entry_tombstoned_older_upsert_wins() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_MEMORY,
        "timezone",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_memory_envelope("timezone", LWW_V_NEW, "resurrected");
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    assert!(!crate::tombstone::is_tombstoned(&conn, naming::ENTITY_MEMORY, "timezone").unwrap());
    let content: String = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'timezone'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(content, "resurrected");
}

#[test]
fn preference_lww_older_version_rejected() {
    let conn = test_db();
    seed_preference_row(&conn, "theme", "dark", LWW_V_NEW);

    let env = make_preference_envelope("theme", LWW_V_OLD, "light");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let (value, version): (String, String) = conn
        .query_row(
            "SELECT value, version FROM preferences WHERE key = 'theme'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(value, "\"dark\"");
    assert_eq!(version, LWW_V_NEW);
}

#[test]
fn preference_tombstoned_newer_payload_skipped() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_PREFERENCE,
        "theme",
        LWW_V_NEW,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_preference_envelope("theme", LWW_V_OLD, "light");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM preferences WHERE key = 'theme'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
    assert!(crate::tombstone::is_tombstoned(&conn, naming::ENTITY_PREFERENCE, "theme").unwrap());
}

#[test]
fn preference_tombstoned_older_upsert_wins() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_PREFERENCE,
        "theme",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_preference_envelope("theme", LWW_V_NEW, "light");
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    assert!(!crate::tombstone::is_tombstoned(&conn, naming::ENTITY_PREFERENCE, "theme").unwrap());
    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'theme'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(value, "\"light\"");
}

#[test]
fn calendar_subscription_lww_older_version_rejected() {
    let conn = test_db();
    seed_calendar_subscription_row(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        "Local Feed",
        LWW_V_NEW,
    );

    let env = make_calendar_subscription_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        LWW_V_OLD,
        "Stale Remote",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let (name, version): (String, String) = conn
        .query_row(
            "SELECT name, version FROM calendar_subscriptions WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002150'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(name, "Local Feed");
    assert_eq!(version, LWW_V_NEW);
}

#[test]
fn calendar_subscription_tombstoned_newer_payload_skipped() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        LWW_V_NEW,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_calendar_subscription_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        LWW_V_OLD,
        "Stale Remote",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_subscriptions WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002150'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000002150"
    )
    .unwrap());
}

#[test]
fn calendar_subscription_tombstoned_older_upsert_wins() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_calendar_subscription_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002150",
        LWW_V_NEW,
        "Resurrected Feed",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    assert!(!crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        "01966a3f-7c8b-7d4e-8f3a-000000002150"
    )
    .unwrap());
    let name: String = conn
        .query_row(
            "SELECT name FROM calendar_subscriptions WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002150'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(name, "Resurrected Feed");
}

#[test]
fn daily_review_lww_older_version_rejected() {
    let conn = test_db();
    seed_daily_review_row(&conn, "2026-03-29", "local summary", LWW_V_NEW);

    let env = make_daily_review_envelope("2026-03-29", LWW_V_OLD, "remote stale");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let (summary, version): (String, String) = conn
        .query_row(
            "SELECT summary, version FROM daily_reviews WHERE date = '2026-03-29'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(summary, "local summary");
    assert_eq!(version, LWW_V_NEW);
}

#[test]
fn daily_review_tombstoned_newer_payload_skipped() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_DAILY_REVIEW,
        "2026-03-29",
        LWW_V_NEW,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_daily_review_envelope("2026-03-29", LWW_V_OLD, "remote stale");
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_reviews WHERE date = '2026-03-29'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
    assert!(
        crate::tombstone::is_tombstoned(&conn, naming::ENTITY_DAILY_REVIEW, "2026-03-29").unwrap()
    );
}

#[test]
fn daily_review_tombstoned_older_upsert_wins() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_DAILY_REVIEW,
        "2026-03-29",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_daily_review_envelope("2026-03-29", LWW_V_NEW, "resurrected");
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    assert!(
        !crate::tombstone::is_tombstoned(&conn, naming::ENTITY_DAILY_REVIEW, "2026-03-29").unwrap()
    );
    let summary: String = conn
        .query_row(
            "SELECT summary FROM daily_reviews WHERE date = '2026-03-29'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(summary, "resurrected");
}

#[test]
fn habit_completion_lww_older_version_rejected() {
    let conn = test_db();
    seed_habit_parent(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002120");
    seed_habit_completion_row(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002120",
        "2026-03-29",
        3,
        LWW_V_NEW,
    );

    let env = make_habit_completion_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002120",
        "2026-03-29",
        LWW_V_OLD,
        1,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let (value, version): (i64, String) = conn
        .query_row(
            "SELECT value, version FROM habit_completions \
             WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000002120' AND completed_date = '2026-03-29'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(value, 3);
    assert_eq!(version, LWW_V_NEW);
}

#[test]
fn habit_completion_tombstoned_newer_payload_skipped() {
    let conn = test_db();
    seed_habit_parent(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002120");

    create_tombstone(
        &conn,
        naming::EDGE_HABIT_COMPLETION,
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-03-29",
        LWW_V_NEW,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_habit_completion_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002120",
        "2026-03-29",
        LWW_V_OLD,
        1,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_completions \
             WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000002120' AND completed_date = '2026-03-29'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 0);
    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::EDGE_HABIT_COMPLETION,
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-03-29"
    )
    .unwrap());
}

#[test]
fn habit_completion_tombstoned_older_upsert_wins() {
    let conn = test_db();
    seed_habit_parent(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002120");

    create_tombstone(
        &conn,
        naming::EDGE_HABIT_COMPLETION,
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-03-29",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_habit_completion_envelope(
        "01966a3f-7c8b-7d4e-8f3a-000000002120",
        "2026-03-29",
        LWW_V_NEW,
        5,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    assert!(!crate::tombstone::is_tombstoned(
        &conn,
        naming::EDGE_HABIT_COMPLETION,
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-03-29"
    )
    .unwrap());
    let value: i64 = conn
        .query_row(
            "SELECT value FROM habit_completions \
             WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000002120' AND completed_date = '2026-03-29'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(value, 5);
}
