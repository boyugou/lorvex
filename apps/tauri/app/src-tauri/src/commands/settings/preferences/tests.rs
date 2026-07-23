use super::*;
use lorvex_domain::naming::{ENTITY_PREFERENCE, OP_DELETE};
use rusqlite::{
    hooks::{AuthAction, AuthContext, Authorization},
    params,
};

use crate::error::AppError;
use crate::test_support::test_conn;

fn setup() -> rusqlite::Connection {
    test_conn()
}

fn seed_task(conn: &rusqlite::Connection, id: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Call mom")
        .list_id(Some("inbox"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-16T00:00:00Z")
        .insert(conn);
}

fn seed_pref_timezone(conn: &rusqlite::Connection, tz_json_literal: &str) {
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, updated_at, version)
         VALUES ('timezone', ?1, '2026-04-16T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        params![tz_json_literal],
    )
    .expect("seed timezone preference");
}

#[test]
fn pref_timezone_change_reanchors_pending_reminders() {
    // moving Asia/Tokyo → America/New_York
    // should re-materialize a reminder anchored at "09:00 Tokyo on
    // 2030-04-17" into "09:00 New_York on 2030-04-17". The UTC
    // instant accordingly moves from 2030-04-17T00:00Z (09:00 JST)
    // to 2030-04-17T13:00Z (09:00 EDT — NY observes DST on that
    // date).
    let conn = setup();
    seed_task(&conn, "t1");
    conn.execute(
        "INSERT INTO task_reminders \
           (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
         VALUES ('11111111-1111-4111-8111-111111111111', 't1', '2030-04-17T00:00:00.000000Z', '09:00', 'Asia/Tokyo', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z')",
        [],
    )
    .expect("seed future reminder with anchor");
    seed_pref_timezone(&conn, "\"Asia/Tokyo\"");

    set_preference_with_conn(
        &conn,
        "timezone",
        "\"America/New_York\"",
        "2026-04-16T12:00:00Z",
    )
    .expect("write new timezone");

    let (reminder_at, original_local_time, original_tz, new_version): (
        String,
        String,
        String,
        String,
    ) = conn
        .query_row(
            "SELECT reminder_at, original_local_time, original_tz, version \
             FROM task_reminders WHERE id = '11111111-1111-4111-8111-111111111111'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("load reminder");
    assert!(
        reminder_at.starts_with("2030-04-17T13:00:00"),
        "expected 2030-04-17T13:00… got {reminder_at}"
    );
    assert_eq!(original_local_time, "09:00");
    assert_eq!(original_tz, "America/New_York");
    assert_ne!(
        new_version, "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "version must be re-stamped on shift"
    );
}

#[test]
fn pref_timezone_change_skips_legacy_reminders_without_original_tz() {
    // Legacy absolute-UTC reminders (no anchor captured) must not be
    // touched — they fall back to the old semantics.
    let conn = setup();
    seed_task(&conn, "t1");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) \
         VALUES ('r-legacy', 't1', '2030-04-17T00:00:00.000000Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z')",
        [],
    )
    .unwrap();
    seed_pref_timezone(&conn, "\"Asia/Tokyo\"");

    set_preference_with_conn(
        &conn,
        "timezone",
        "\"America/New_York\"",
        "2026-04-16T12:00:00Z",
    )
    .unwrap();

    let (reminder_at, version): (String, String) = conn
        .query_row(
            "SELECT reminder_at, version FROM task_reminders WHERE id = 'r-legacy'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(reminder_at, "2030-04-17T00:00:00.000000Z");
    assert_eq!(
        version, "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "legacy rows must not be re-stamped"
    );
}

#[test]
fn pref_timezone_change_skips_notified_reminders() {
    // Reminders whose delivery_state is already 'delivered' must not
    // re-anchor — shifting a fired reminder would either double-fire
    // (if the new UTC falls back into the future) or do nothing
    // useful (if it stays past). Either way it's wrong.
    let conn = setup();
    seed_task(&conn, "t1");
    conn.execute(
        "INSERT INTO task_reminders \
           (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
         VALUES ('r-done', 't1', '2030-04-17T00:00:00.000000Z', '09:00', 'Asia/Tokyo', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at) \
         VALUES ('r-done', 'delivered', '2026-04-16T00:00:00Z')",
        [],
    )
    .unwrap();
    seed_pref_timezone(&conn, "\"Asia/Tokyo\"");

    set_preference_with_conn(
        &conn,
        "timezone",
        "\"America/New_York\"",
        "2026-04-16T12:00:00Z",
    )
    .unwrap();

    let (reminder_at, original_tz, version): (String, String, String) = conn
        .query_row(
            "SELECT reminder_at, original_tz, version \
             FROM task_reminders WHERE id = 'r-done'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(reminder_at, "2030-04-17T00:00:00.000000Z");
    assert_eq!(original_tz, "Asia/Tokyo");
    assert_eq!(
        version, "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "delivered rows must not be re-stamped"
    );
}

#[test]
fn pref_timezone_change_leaves_past_reminders_alone() {
    let conn = setup();
    seed_task(&conn, "t1");
    conn.execute(
        "INSERT INTO task_reminders \
           (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
         VALUES ('r-past', 't1', '2020-01-01T00:00:00.000000Z', '09:00', 'Asia/Tokyo', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2020-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    seed_pref_timezone(&conn, "\"Asia/Tokyo\"");

    set_preference_with_conn(
        &conn,
        "timezone",
        "\"America/New_York\"",
        "2026-04-16T12:00:00Z",
    )
    .unwrap();

    let reminder_at: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = 'r-past'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(reminder_at, "2020-01-01T00:00:00.000000Z");
}

#[test]
fn set_preference_with_conn_rejects_oversized_key_and_value() {
    // The Tauri path caps preference key+value sizes to match the
    // MCP contract so a malformed deep-link / settings autosave
    // cannot write multi-megabyte values.
    let conn = setup();

    // Key too long.
    let long_key = "x".repeat(lorvex_domain::validation::KV_KEY_MAX_CHARS + 1);
    let err = set_preference_with_conn(&conn, &long_key, "\"v\"", "2026-04-17T00:00:00Z")
        .expect_err("oversized key must be rejected");
    match err {
        AppError::Validation(msg) => assert!(msg.contains("key length")),
        other => panic!("expected Validation, got {other:?}"),
    }

    // Empty key.
    let err = set_preference_with_conn(&conn, "", "\"v\"", "2026-04-17T00:00:00Z")
        .expect_err("empty key must be rejected");
    assert!(matches!(err, AppError::Validation(_)));

    // Value too long.
    let long_value = format!(
        "\"{}\"",
        "x".repeat(lorvex_domain::validation::KV_VALUE_MAX_BYTES + 1)
    );
    let err = set_preference_with_conn(&conn, "theme", &long_value, "2026-04-17T00:00:00Z")
        .expect_err("oversized value must be rejected");
    match err {
        AppError::Validation(msg) => assert!(msg.contains("value length")),
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn set_preference_with_conn_clearing_existing_value_enqueues_delete() {
    let conn = setup();
    conn.execute(
        "INSERT INTO preferences (key, value, updated_at, version)
         VALUES ('theme', '\"dark\"', '2026-03-29T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        [],
    )
    .expect("seed preference row");

    set_preference_with_conn(&conn, "theme", "null", "2026-03-29T10:00:00Z")
        .expect("clear preference");

    let (operation, payload): (String, String) = conn
        .query_row(
            "SELECT operation, payload
             FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = 'theme'
             ORDER BY id DESC
             LIMIT 1",
            params![ENTITY_PREFERENCE],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .expect("load preference delete outbox row");
    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("preference delete payload should be valid json");

    assert_eq!(operation, OP_DELETE);
    assert_eq!(payload["key"], "theme");
}

#[test]
fn set_preference_with_conn_clearing_existing_value_surfaces_lookup_failures() {
    let conn = setup();
    conn.execute(
        "INSERT INTO preferences (key, value, updated_at, version)
         VALUES ('theme', '\"dark\"', '2026-03-29T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        [],
    )
    .expect("seed preference row");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "preferences",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = set_preference_with_conn(&conn, "theme", "null", "2026-03-29T10:00:00Z")
        .expect_err("preference lookup failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("access to preferences"),
        "unexpected error: {message}"
    );
}

#[test]
fn set_preference_with_conn_rejects_malformed_json_value() {
    let conn = setup();

    let error = set_preference_with_conn(&conn, "theme", "{not-valid-json", "2026-03-29T10:00:00Z")
        .expect_err("malformed preference json should fail");

    let message = error.to_string();
    assert!(
        message.contains("canonical JSON"),
        "unexpected error: {message}"
    );
}

/// Every writable preference key must be in the canonical allowlist
/// so a renderer XSS or malformed deep-link cannot write arbitrary
/// keys (polluting the preferences table or redirecting path-shaped
/// values).
#[test]
fn set_preference_with_conn_rejects_unknown_keys() {
    let conn = setup();

    let err = set_preference_with_conn(
        &conn,
        "definitely_not_a_known_preference_key",
        "\"hello\"",
        "2026-04-17T00:00:00Z",
    )
    .expect_err("unknown preference keys must be rejected");
    match err {
        AppError::Validation(msg) => assert!(
            msg.contains("not a known preference key"),
            "expected unknown-key validation error, got {msg}"
        ),
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn set_preference_with_conn_accepts_focus_safety_preferences() {
    let conn = setup();

    for key in [
        lorvex_domain::preference_keys::PREF_FOCUS_CONFIRM_SKIP_BREAK,
        lorvex_domain::preference_keys::PREF_FOCUS_CONFIRM_EXIT,
        lorvex_domain::preference_keys::PREF_FOCUS_BREAK_END_ALERT,
    ] {
        set_preference_with_conn(&conn, key, "true", "2026-04-17T00:00:00Z")
            .unwrap_or_else(|error| panic!("{key} should be accepted, got {error:?}"));

        let stored: String = conn
            .query_row(
                "SELECT value FROM preferences WHERE key = ?1",
                params![key],
                |row| row.get(0),
            )
            .expect("load persisted focus preference");
        assert_eq!(stored, "true");
    }
}

/// on a platform without a biometric backend
/// (Linux, mobile builds), enabling the memory-lock preference
/// would CRDT-sync from a macOS / Windows peer and leave the
/// settings panel showing "lock disabled" while the underlying
/// preference row claimed otherwise. Reject the truthy write at
/// the IPC boundary on those platforms.
#[test]
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn set_preference_with_conn_rejects_memory_lock_enabled_on_platforms_without_biometrics() {
    let conn = setup();

    let err = set_preference_with_conn(
        &conn,
        lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED,
        "true",
        "2026-04-17T00:00:00Z",
    )
    .expect_err("memory_lock_enabled=true must be rejected on platforms without biometrics");
    match err {
        AppError::Validation(msg) => assert!(
            msg.contains("biometric")
                && msg.contains(lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED),
            "expected biometric-unavailable rejection, got {msg}"
        ),
        other => panic!("expected Validation, got {other:?}"),
    }

    // Setting the value to `false` (or `null`) must always be
    // permitted so a synced "disable lock" row can land safely.
    set_preference_with_conn(
        &conn,
        lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED,
        "false",
        "2026-04-17T00:00:00Z",
    )
    .expect("memory_lock_enabled=false must be accepted on platforms without biometrics");
}

/// on platforms with a biometric
/// backend the memory-lock preference can be enabled.
#[test]
#[cfg(any(target_os = "macos", target_os = "windows"))]
fn set_preference_with_conn_accepts_memory_lock_enabled_on_biometric_platforms() {
    let conn = setup();

    set_preference_with_conn(
        &conn,
        lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED,
        "true",
        "2026-04-17T00:00:00Z",
    )
    .expect("memory_lock_enabled=true must be accepted on platforms with biometrics");
}
