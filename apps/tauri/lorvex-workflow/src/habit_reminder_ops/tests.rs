//! Tests for `habit_reminder_ops`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use lorvex_store::test_support::test_conn;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

fn seed_habit(conn: &Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) \
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', ?3, ?3)",
        params![id, name, "2026-03-29T00:00:00Z"],
    )
    .expect("seed habit");
}

fn dummy_version() -> &'static str {
    "0000000000000_0000_0000000000000001"
}

#[test]
fn upsert_creates_new_policy() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let policy = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("create policy");

    assert_eq!(policy.habit_id, "h1");
    assert_eq!(policy.habit_name, "Meditate");
    assert_eq!(policy.reminder_time, "08:00");
    assert!(policy.enabled);
}

#[test]
fn upsert_updates_existing_policy() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let created = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("create");

    let updated = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: Some(&created.id),
            habit_id: "h1",
            reminder_time: "09:30",
            enabled: false,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T10:00:00Z",
        },
    )
    .expect("update");

    assert_eq!(updated.id, created.id);
    assert_eq!(updated.reminder_time, "09:30");
    assert!(!updated.enabled);
}

#[test]
fn upsert_rejects_invalid_time() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "25:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect_err("invalid time should fail");

    assert!(
        err.to_string().contains("invalid reminder_time"),
        "unexpected error: {err}"
    );
}

#[test]
fn upsert_rejects_missing_habit() {
    let conn = test_conn();

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "missing",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect_err("missing habit should fail");

    match err {
        StoreError::NotFound { entity, id } => {
            assert_eq!(entity, "habit");
            assert_eq!(id, "missing");
        }
        other => panic!("expected NotFound, got {other:?}"),
    }
}

#[test]
fn upsert_rejects_empty_habit_id() {
    let conn = test_conn();

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "   ",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect_err("empty habit_id should fail");

    assert!(
        err.to_string().contains("habit_id must not be empty"),
        "unexpected error: {err}"
    );
}

#[test]
fn upsert_allows_multiple_slots_for_one_habit() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let first = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("first slot");

    let second = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "18:30",
            enabled: false,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T09:05:00Z",
        },
    )
    .expect("second slot");

    assert_ne!(first.id, second.id);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE habit_id = 'h1'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 2);
}

#[test]
fn upsert_rejects_duplicate_time_for_same_habit() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("first slot");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: false,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T09:05:00Z",
        },
    )
    .expect_err("duplicate time should fail");

    assert!(
        err.to_string()
            .contains("already has a reminder slot at 08:00"),
        "unexpected error: {err}"
    );
}

#[test]
fn upsert_rejects_cross_habit_slot_updates() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");
    seed_habit(&conn, "h2", "Read");

    let created = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("create slot for h1");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: Some(&created.id),
            habit_id: "h2",
            reminder_time: "09:00",
            enabled: false,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T10:00:00Z",
        },
    )
    .expect_err("cross-habit update should fail");

    assert!(
        err.to_string().contains("belongs to a different habit"),
        "unexpected error: {err}"
    );
}

#[test]
fn upsert_rejects_duplicate_time_on_update() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let _first = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("first slot");

    let second = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "18:30",
            enabled: true,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T09:05:00Z",
        },
    )
    .expect("second slot");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: Some(&second.id),
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: false,
            version: "0000000000000_0000_0000000000000003",
            now: "2026-03-29T10:00:00Z",
        },
    )
    .expect_err("update colliding with existing slot should fail");

    assert!(
        err.to_string()
            .contains("already has a reminder slot at 08:00"),
        "unexpected error: {err}"
    );
}

#[test]
fn upsert_treats_blank_id_as_new_slot() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let created = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: Some("   "),
            habit_id: "h1",
            reminder_time: "07:15",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("blank id should create new slot");

    assert!(!created.id.trim().is_empty());
    assert_eq!(created.reminder_time, "07:15");
}

#[test]
fn upsert_surfaces_habit_lookup_failures() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habits",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "09:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect_err("habit lookup failure should surface");

    // Should be a Sql error, not a NotFound error
    match err {
        StoreError::Sql(_) => {}
        other => panic!("expected Sql error, got {other:?}"),
    }
}

#[test]
fn upsert_surfaces_existing_policy_lookup_failures() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");
    conn.execute(
        "INSERT INTO habit_reminder_policies \
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at) \
         VALUES ('p1', 'h1', '08:00', 1, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        [],
    )
    .expect("seed policy");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habit_reminder_policies",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let err = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "09:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect_err("policy lookup failure should surface");

    match err {
        StoreError::Sql(_) => {}
        other => panic!("expected Sql error, got {other:?}"),
    }
}

#[test]
fn delete_existing_policy() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Meditate");

    let created = upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "08:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("create");

    let result = delete_habit_reminder_policy(&conn, &created.id).expect("delete");
    assert!(result.deleted);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE id = ?1",
            params![created.id],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 0);
}

#[test]
fn delete_nonexistent_policy_returns_false() {
    let conn = test_conn();
    let result = delete_habit_reminder_policy(&conn, "nonexistent").expect("delete");
    assert!(!result.deleted);
}

#[test]
fn list_policies_ordered() {
    let conn = test_conn();
    seed_habit(&conn, "h1", "Zzz Sleep");
    seed_habit(&conn, "h2", "Aaa Meditate");

    upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h1",
            reminder_time: "22:00",
            enabled: true,
            version: dummy_version(),
            now: "2026-03-29T09:00:00Z",
        },
    )
    .expect("create for h1");

    upsert_habit_reminder_policy(
        &conn,
        &UpsertHabitReminderPolicyParams {
            policy_id: None,
            habit_id: "h2",
            reminder_time: "06:00",
            enabled: true,
            version: "0000000000000_0000_0000000000000002",
            now: "2026-03-29T09:05:00Z",
        },
    )
    .expect("create for h2");

    let policies = list_all_policies(&conn).expect("list");
    assert_eq!(policies.len(), 2);
    // "Aaa Meditate" should come before "Zzz Sleep" (case-insensitive)
    assert_eq!(policies[0].habit_name, "Aaa Meditate");
    assert_eq!(policies[1].habit_name, "Zzz Sleep");
}
