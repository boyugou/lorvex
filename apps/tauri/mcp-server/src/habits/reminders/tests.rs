//! Tests for the habit reminder MCP verbs. Extracted from
//! `reminders.rs` when that file was decomposed into per-verb siblings;
//! tests stay co-located with the public surface via `super::*`.

use super::*;
use crate::contract::UpsertHabitReminderPolicyArgs;
use crate::db::open_database_for_path;
use crate::error::McpError;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
use rusqlite::params;
use rusqlite::Connection;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_habit(conn: &Connection, id: &str, name: &str) {
    let now = "2026-03-29T00:00:00Z";
    conn.execute(
    "INSERT INTO habits (id, name, created_at, updated_at, version) VALUES (?1, ?2, ?3, ?3, '0000000000000_0000_0000000000000000')",
    params![id, name, now],
)
.expect("insert habit");
}

#[test]
fn upsert_habit_reminder_policy_surfaces_existing_policy_lookup_failures() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.execute(
    "INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
     VALUES (?1, ?2, ?3, 1, '0000000000000_0000_0000000000000000', ?4, ?4)",
    params!["01966a3f-7c8b-7d4e-8f3a-000000000207", "01966a3f-7c8b-7d4e-8f3a-000000000201", "08:00", "2026-03-29T00:00:00Z"],
)
.expect("insert reminder policy");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habit_reminder_policies",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error: String = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "09:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect_err("existing policy lookup failure should surface")
    .into();
    assert!(
        error.contains("internal error") || error.contains("Please try again"),
        "unexpected error: {error}"
    );
    assert!(
        !error.contains("already exists"),
        "lookup failure must not degrade into duplicate insert error: {error}"
    );
}

#[test]
fn upsert_habit_reminder_policy_surfaces_habit_lookup_failures() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habits",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error: String = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "09:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect_err("habit lookup failure should surface")
    .into();
    assert!(
        error.contains("internal error") || error.contains("Please try again"),
        "unexpected error: {error}"
    );
    assert!(
        !error.contains("habit not found"),
        "database failure must not degrade into not-found error: {error}"
    );
}

#[test]
fn upsert_habit_reminder_policy_allows_multiple_slots_for_one_habit() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");

    let first = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create first slot");
    let second = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "18:30".to_string(),
            enabled: Some(false),
            idempotency_key: None,
        },
    )
    .expect("create second slot");

    let first: serde_json::Value = serde_json::from_str(&first).expect("decode first slot");
    let second: serde_json::Value = serde_json::from_str(&second).expect("decode second slot");
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE habit_id = '01966a3f-7c8b-7d4e-8f3a-000000000201'",
            [],
            |row| row.get(0),
        )
        .expect("count reminder slots");

    assert_ne!(first["id"], second["id"]);
    assert_eq!(count, 2);
    assert_eq!(second["enabled"], false);
}

#[test]
fn upsert_habit_reminder_policy_create_logs_generated_policy_id() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");

    let created = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create reminder policy");
    let created: serde_json::Value =
        serde_json::from_str(&created).expect("decode reminder policy");
    let policy_id = created["id"].as_str().expect("policy id");

    let (entity_id, after_json): (String, String) = conn
        .query_row(
            "SELECT entity_id, after_json FROM ai_changelog
             WHERE mcp_tool = 'upsert_habit_reminder_policy'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read reminder policy changelog");
    let after_json: serde_json::Value =
        serde_json::from_str(&after_json).expect("parse after_json");

    assert_eq!(entity_id, policy_id);
    assert_eq!(after_json["id"], policy_id);
}

#[test]
fn upsert_habit_reminder_policy_treats_blank_id_as_new_slot() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");

    let created = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: Some("   ".to_string()),
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "07:15".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("blank id should create a new slot");

    let created: serde_json::Value = serde_json::from_str(&created).expect("decode created slot");
    assert_eq!(created["habit_id"], "01966a3f-7c8b-7d4e-8f3a-000000000201");
    assert_eq!(created["reminder_time"], "07:15");
    assert_eq!(created["enabled"], true);
    assert!(created["id"]
        .as_str()
        .is_some_and(|id| !id.trim().is_empty()));
}

#[test]
fn upsert_habit_reminder_policy_rejects_cross_habit_slot_updates() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    seed_habit(&conn, "habit-2", "Read");

    let created = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create source slot");
    let created: serde_json::Value = serde_json::from_str(&created).expect("decode created slot");
    let policy_id = created["id"].as_str().expect("slot id");

    let error = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: Some(policy_id.to_string()),
            habit_id: "habit-2".to_string(),
            reminder_time: "09:00".to_string(),
            enabled: Some(false),
            idempotency_key: None,
        },
    )
    .expect_err("cross-habit update should fail");

    assert!(
        error.to_string().contains("belongs to a different habit"),
        "unexpected error: {error}"
    );
}

#[test]
fn upsert_habit_reminder_policy_rejects_duplicate_time_for_same_habit_on_create() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create first slot");

    let error = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(false),
            idempotency_key: None,
        },
    )
    .expect_err("duplicate slot time should fail");

    assert!(
        error
            .to_string()
            .contains("already has a reminder slot at 08:00"),
        "unexpected error: {error}"
    );
}

/// Regression for #2966-H4: a phantom `habit_id` must fail at the
/// MCP trust boundary with a clean Validation error before any
/// store-layer work runs. Pre-fix the only existence check lived
/// in the store and surfaced as `StoreError::NotFound`, conflating
/// "habit doesn't exist" with "policy slot doesn't exist".
#[test]
fn upsert_habit_reminder_policy_rejects_phantom_habit_id_at_trust_boundary() {
    let conn = open_temp_db();

    let error = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "habit-phantom".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect_err("phantom habit_id must fail at trust boundary");

    match error {
        McpError::Validation(message) => {
            assert!(
                message.contains("habit_id") && message.contains("habit-phantom"),
                "expected validation error referencing the phantom habit_id, got: {message}"
            );
        }
        other => panic!("expected Validation error, got {other:?}"),
    }

    let policy_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM habit_reminder_policies", [], |row| {
            row.get(0)
        })
        .expect("count policies");
    assert_eq!(
        policy_count, 0,
        "no policy row should be persisted when habit_id validation fails"
    );

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'upsert_habit_reminder_policy'",
            [],
            |row| row.get(0),
        )
        .expect("count changelog rows");
    assert_eq!(
        changelog_count, 0,
        "no changelog row should be emitted on phantom habit_id"
    );
}

#[test]
fn upsert_habit_reminder_policy_rejects_blank_habit_id_at_trust_boundary() {
    let conn = open_temp_db();
    let error = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "   ".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect_err("blank habit_id must fail at trust boundary");
    match error {
        McpError::Validation(message) => {
            assert!(
                message.contains("habit_id"),
                "expected validation error mentioning habit_id, got: {message}"
            );
        }
        other => panic!("expected Validation error, got {other:?}"),
    }
}

#[test]
fn upsert_habit_reminder_policy_rejects_duplicate_time_for_same_habit_on_update() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");

    let first = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "08:00".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create first slot");
    let second = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: None,
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: "18:30".to_string(),
            enabled: Some(true),
            idempotency_key: None,
        },
    )
    .expect("create second slot");
    let first: serde_json::Value = serde_json::from_str(&first).expect("decode first slot");
    let second: serde_json::Value = serde_json::from_str(&second).expect("decode second slot");

    let error = upsert_habit_reminder_policy(
        &conn,
        UpsertHabitReminderPolicyArgs {
            id: Some(second["id"].as_str().expect("second id").to_string()),
            habit_id: "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            reminder_time: first["reminder_time"]
                .as_str()
                .expect("first reminder time")
                .to_string(),
            enabled: Some(false),
            idempotency_key: None,
        },
    )
    .expect_err("duplicate slot time update should fail");

    assert!(
        error
            .to_string()
            .contains("already has a reminder slot at 08:00"),
        "unexpected error: {error}"
    );
}
