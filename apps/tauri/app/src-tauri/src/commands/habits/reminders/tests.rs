use super::*;
use chrono::TimeZone;
use rusqlite::{
    hooks::{AuthAction, AuthContext, Authorization},
    params,
};

use crate::error::AppError;
use crate::test_support::test_conn;

#[test]
fn upsert_habit_reminder_policy_with_conn_rejects_missing_habit() {
    let conn = test_conn();

    let error = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("missing-habit".to_string()),
        "09:30",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect_err("missing habit should be rejected");

    // The shared op returns StoreError::NotFound, which wraps into AppError::Store(...)
    let message = error.to_string();
    assert!(
        message.contains("missing-habit") || message.contains("habit"),
        "expected not found error, got {error:?}"
    );
}

#[test]
fn upsert_habit_reminder_policy_with_conn_surfaces_habit_lookup_failures() {
    let conn = test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habits",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:30",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect_err("habit lookup failure should surface");

    // The shared op returns StoreError::Sql, which wraps into AppError::Store(...)
    match error {
        crate::error::AppError::Store(boxed) => match *boxed {
            lorvex_store::StoreError::Sql(_) => {}
            other => panic!("expected sql error, got {other:?}"),
        },
        crate::error::AppError::Sql(_) => {}
        other => panic!("expected sql error, got {other:?}"),
    }
}

#[test]
fn upsert_habit_reminder_policy_with_conn_updates_version_for_existing_policy() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");

    let first = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:30",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect("create policy");

    let first_version: String = conn
        .query_row(
            "SELECT version FROM habit_reminder_policies WHERE id = ?1",
            params![first.id],
            |row| row.get(0),
        )
        .expect("load initial policy version");

    let updated = upsert_habit_reminder_policy_with_conn(
        &conn,
        Some(first.id.as_str()),
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "10:15",
        false,
        "2026-03-29T10:00:00Z",
    )
    .expect("update policy");

    let updated_version: String = conn
        .query_row(
            "SELECT version FROM habit_reminder_policies WHERE id = ?1",
            params![updated.id],
            |row| row.get(0),
        )
        .expect("load updated policy version");

    assert_ne!(updated_version, first_version);
    assert_eq!(updated.reminder_time, "10:15");
    assert!(!updated.enabled);
}

#[test]
fn due_habit_reminder_clock_at_uses_timezone_calendar_day() {
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    let (today, current_time) =
        due_habit_reminder_clock_at(now, "America/Los_Angeles").expect("resolve clock");

    assert_eq!(today, "2026-03-07");
    assert_eq!(current_time, "17:00");
}

#[test]
fn due_habit_reminder_clock_at_rejects_invalid_timezone_name() {
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    let error = due_habit_reminder_clock_at(now, "Not/AZone")
        .expect_err("invalid timezone should be rejected");

    match error {
        AppError::Internal(message) => assert!(message.contains("Not/AZone")),
        other => panic!("expected internal error, got {other:?}"),
    }
}

#[test]
fn get_due_habit_reminders_with_conn_at_skips_policies_already_reminded_today() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed timezone");
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");
    conn.execute(
        "INSERT INTO habit_reminder_policies
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES
         ('policy-1', 'habit-1', '09:00', 1, 'policy_ver', '2026-03-29T08:00:00Z', '2026-03-29T17:30:00Z')",
        [],
    )
    .expect("seed reminded policy");
    conn.execute(
        "INSERT INTO habit_reminder_delivery_state
         (policy_id, last_fired_at, updated_at)
         VALUES
         ('policy-1', '2026-03-29T17:30:00Z', '2026-03-29T17:30:00Z')",
        [],
    )
    .expect("seed reminded policy");

    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 29, 18, 0, 0)
        .single()
        .expect("construct UTC instant");
    let due = get_due_habit_reminders_with_conn_at(&conn, now).expect("load due habit reminders");

    assert!(
        due.is_empty(),
        "already-reminded policy should be suppressed"
    );
}

#[test]
fn reminder_was_sent_on_local_day_propagates_db_errors() {
    // Regression for R15: historically this helper swallowed all
    // SQLite errors via `.ok().flatten()` and returned `false`
    // ("not sent yet"), which caused a duplicate user-facing
    // notification the next time the debounce was re-evaluated.
    // The fix converts the helper to `AppResult<bool>` so a
    // transient query error propagates up through
    // `get_due_habit_reminders_with_conn_at` rather than silently
    // flipping the debounce decision.
    let conn = test_conn();
    conn.execute("DROP TABLE habit_reminder_delivery_state", [])
        .expect("drop debounce table for test");

    let result = reminder_was_sent_on_local_day(
        &conn,
        "policy-missing-table",
        "America/Los_Angeles",
        "2026-03-29",
    );
    assert!(
        result.is_err(),
        "dropping the delivery state table must surface a SQLite error, not coerce to false"
    );
}

#[test]
fn get_due_habit_reminders_with_conn_at_respects_weekly_schedule_days() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed timezone");
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, version, created_at, updated_at)
         VALUES ('habit-1', 'Gym', 'weekly', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed weekly habit");
    // Weekly weekday set (Mon=0, Wed=2) lives in the `habit_weekdays` child.
    conn.execute(
        "INSERT INTO habit_weekdays (habit_id, weekday) VALUES ('habit-1', 0), ('habit-1', 2)",
        [],
    )
    .expect("seed weekly weekdays");
    conn.execute(
        "INSERT INTO habit_reminder_policies
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES
         ('policy-1', 'habit-1', '09:00', 1, 'policy_ver', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed reminder slot");

    let sunday = chrono::Utc
        .with_ymd_and_hms(2026, 3, 29, 18, 0, 0)
        .single()
        .expect("construct sunday UTC instant");
    let sunday_due =
        get_due_habit_reminders_with_conn_at(&conn, sunday).expect("load sunday reminders");
    assert!(
        sunday_due.is_empty(),
        "weekly habit should not fire on unscheduled sunday"
    );

    let monday = chrono::Utc
        .with_ymd_and_hms(2026, 3, 30, 18, 0, 0)
        .single()
        .expect("construct monday UTC instant");
    let monday_due =
        get_due_habit_reminders_with_conn_at(&conn, monday).expect("load monday reminders");
    assert_eq!(
        monday_due.len(),
        1,
        "weekly habit should fire on scheduled monday"
    );
    assert_eq!(monday_due[0].policy.id, "policy-1");
}

#[test]
fn get_due_habit_reminders_with_conn_at_suppresses_slots_after_target_count_is_met() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed timezone");
    conn.execute(
        "INSERT INTO habits (id, name, target_count, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', 3, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed accumulative habit");
    conn.execute(
        "INSERT INTO habit_reminder_policies
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES
         ('policy-1', 'habit-1', '09:00', 1, 'policy_ver', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed reminder slot");
    conn.execute(
        "INSERT INTO habit_completions
         (habit_id, completed_date, value, note, version, created_at, updated_at)
         VALUES
         ('habit-1', '2026-03-29', 3, NULL, 'completion_ver', '2026-03-29T12:00:00Z', '2026-03-29T12:00:00Z')",
        [],
    )
    .expect("seed habit completions");

    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 29, 18, 0, 0)
        .single()
        .expect("construct UTC instant");
    let due = get_due_habit_reminders_with_conn_at(&conn, now).expect("load due habit reminders");

    assert!(
        due.is_empty(),
        "daily reminder should be suppressed after target_count is met"
    );
}

#[test]
fn mark_habit_reminder_fired_with_conn_updates_local_delivery_state() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");
    conn.execute(
        "INSERT INTO habit_reminder_policies
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES
         ('policy-1', 'habit-1', '09:00', 1, 'policy_ver', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed policy");

    mark_habit_reminder_fired_with_conn(&conn, "policy-1", "2026-03-29T18:00:00Z")
        .expect("mark reminder fired");

    let (last_fired_at, updated_at): (Option<String>, String) = conn
        .query_row(
            "SELECT last_fired_at, updated_at
             FROM habit_reminder_delivery_state WHERE policy_id = 'policy-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load updated delivery state");
    assert_eq!(last_fired_at.as_deref(), Some("2026-03-29T18:00:00Z"));
    assert_eq!(updated_at, "2026-03-29T18:00:00Z");
}

#[test]
fn upsert_habit_reminder_policy_with_conn_allows_multiple_slots_per_habit() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");

    let first = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:00",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect("create first reminder slot");
    let second = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "17:30",
        true,
        "2026-03-29T09:05:00Z",
    )
    .expect("create second reminder slot");

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE habit_id = 'habit-1'",
            [],
            |row| row.get(0),
        )
        .expect("count reminder slots");

    assert_ne!(first.id, second.id);
    assert_eq!(count, 2);
}

#[test]
fn upsert_habit_reminder_policy_with_conn_rejects_duplicate_slot_times_for_same_habit() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");
    upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:00",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect("create first reminder slot");

    let error = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:00",
        true,
        "2026-03-29T09:05:00Z",
    )
    .expect_err("duplicate reminder time should be rejected");

    let message = error.to_string();
    assert!(
        message.contains("already has a reminder slot at 09:00"),
        "expected validation error, got {error:?}"
    );
}

#[test]
fn upsert_habit_reminder_policy_with_conn_rejects_updates_that_collide_with_existing_slot() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at)
         VALUES ('habit-1', 'Hydrate', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed habit");
    let first = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:00",
        true,
        "2026-03-29T09:00:00Z",
    )
    .expect("create first reminder slot");
    let second = upsert_habit_reminder_policy_with_conn(
        &conn,
        None,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "17:30",
        true,
        "2026-03-29T09:05:00Z",
    )
    .expect("create second reminder slot");

    let error = upsert_habit_reminder_policy_with_conn(
        &conn,
        Some(second.id.as_str()),
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
        "09:00",
        true,
        "2026-03-29T10:00:00Z",
    )
    .expect_err("update colliding with existing slot should be rejected");

    let message = error.to_string();
    assert!(
        message.contains("already has a reminder slot at 09:00"),
        "expected validation error, got {error:?}"
    );

    let unchanged: String = conn
        .query_row(
            "SELECT reminder_time FROM habit_reminder_policies WHERE id = ?1",
            params![second.id],
            |row| row.get(0),
        )
        .expect("load unchanged reminder time");
    assert_eq!(unchanged, "17:30");
    assert_ne!(first.id, second.id);
}
