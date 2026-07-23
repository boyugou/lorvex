use super::*;
use crate::db::open_database_for_path;
use crate::error::McpError;
use serde_json::{json, Value};
use tempfile::tempdir;

fn shared_const_string_values(const_name: &str) -> Vec<String> {
    let source = include_str!("../../../shared/src/types.ts");
    let start = source
        .find(&format!("export const {const_name} = ["))
        .unwrap_or_else(|| panic!("shared {const_name} start"));
    let after_start = &source[start..];
    let end = after_start
        .find("] as const;")
        .unwrap_or_else(|| panic!("shared {const_name} end"));
    let block = &after_start[..end];

    block
        .split('\'')
        .skip(1)
        .step_by(2)
        .map(str::to_string)
        .collect()
}

fn shared_theme_modes() -> Vec<String> {
    shared_const_string_values("THEME_MODES")
}

fn shared_appearance_profiles() -> Vec<String> {
    shared_const_string_values("APPEARANCE_PROFILES")
}

fn shared_assistant_ui_views() -> Vec<String> {
    shared_const_string_values("ASSISTANT_UI_VIEWS")
}

fn shared_assistant_ui_languages() -> Vec<String> {
    let mut languages = vec!["system".to_string()];
    languages.extend(shared_const_string_values("SUPPORTED_LOCALES"));
    languages
}

fn open_temp_db() -> rusqlite::Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_response_parses_object_values_like_get_preference() {
    let conn = open_temp_db();

    let response = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "dashboard_layout".to_string(),
            value: json!({
                "theme": "midnight",
                "nested": {
                    "count": 2
                }
            }),
            idempotency_key: None,
        },
    )
    .expect("set preference response");

    let payload: Value = serde_json::from_str(&response).expect("parse set preference response");
    assert_eq!(
        payload.get("value"),
        Some(&json!({
            "theme": "midnight",
            "nested": {
                "count": 2
            }
        })),
    );

    let fetched = get_preference(
        &conn,
        crate::contract::GetPreferenceArgs {
            key: "dashboard_layout".to_string(),
        },
    )
    .expect("get preference response");
    let fetched_payload: Value =
        serde_json::from_str(&fetched).expect("parse get preference response");

    assert_eq!(
        payload.get("value"),
        fetched_payload.get("value"),
        "set_preference should echo the same typed value shape that get_preference returns",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_response_parses_scalar_values_like_get_preference() {
    let conn = open_temp_db();

    let response = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "notification_sound_enabled".to_string(),
            value: json!(true),
            idempotency_key: None,
        },
    )
    .expect("set preference response");

    let payload: Value = serde_json::from_str(&response).expect("parse set preference response");
    assert_eq!(payload.get("value"), Some(&json!(true)));

    let fetched = get_preference(
        &conn,
        crate::contract::GetPreferenceArgs {
            key: "notification_sound_enabled".to_string(),
        },
    )
    .expect("get preference response");
    let fetched_payload: Value =
        serde_json::from_str(&fetched).expect("parse get preference response");

    assert_eq!(
        payload.get("value"),
        fetched_payload.get("value"),
        "set_preference should keep scalar preference values type-stable with get_preference",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_rejects_double_encoded_string_literals() {
    let conn = open_temp_db();

    let error = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "default_list_id".to_string(),
            value: json!(r#""list-123""#),
            idempotency_key: None,
        },
    )
    .expect_err("double-encoded string literal should fail")
    .to_string();

    assert!(
        error.contains("plain strings") || error.contains("JSON-encoded string literals"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_accepts_plain_string_values_for_string_preferences() {
    let conn = open_temp_db();

    let response = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "default_list_id".to_string(),
            value: json!("list-123"),
            idempotency_key: None,
        },
    )
    .expect("plain string preference should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse set preference response");
    assert_eq!(payload.get("value"), Some(&json!("list-123")));

    let raw_stored: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'default_list_id'",
            [],
            |row| row.get(0),
        )
        .expect("load raw stored preference");
    assert_eq!(raw_stored, r#""list-123""#);
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_rejects_multibyte_values_over_byte_limit() {
    let conn = open_temp_db();
    let value = "é".repeat(lorvex_domain::validation::KV_VALUE_MAX_BYTES / 2);

    let error = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "dashboard_layout".to_string(),
            value: json!(value),
            idempotency_key: None,
        },
    )
    .expect_err("serialized preference values over the byte limit must fail")
    .to_string();

    assert!(
        error.contains("bytes") && error.contains("preference value"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_all_preferences_returns_typed_values_by_key() {
    // pick any assistant-settable string preference — the test's
    // real intent is that typed values round-trip through
    // get_all_preferences, not that any specific key is settable.
    let conn = open_temp_db();

    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "weekly_review_day".to_string(),
            value: json!("friday"),
            idempotency_key: None,
        },
    )
    .expect("set string preference");
    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "notification_sound_enabled".to_string(),
            value: json!(true),
            idempotency_key: None,
        },
    )
    .expect("set boolean preference");

    let payload: Value =
        serde_json::from_str(&get_all_preferences(&conn).expect("get all preferences"))
            .expect("parse all preferences");

    assert_eq!(payload.get("weekly_review_day"), Some(&json!("friday")));
    assert_eq!(
        payload.get("notification_sound_enabled"),
        Some(&json!(true))
    );
}

#[test]
#[serial_test::serial(hlc)]
fn load_preference_row_and_parse_preference_row_value_preserve_typed_values() {
    let conn = open_temp_db();

    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "dashboard_layout".to_string(),
            value: json!({
                "view": "today",
                "panel_open": true
            }),
            idempotency_key: None,
        },
    )
    .expect("set object preference");

    let row = load_preference_row(&conn, "dashboard_layout").expect("load stored preference row");
    let parsed = parse_preference_row_value(row).expect("parse stored preference row");

    assert_eq!(parsed["key"], "dashboard_layout");
    assert_eq!(
        parsed.get("value"),
        Some(&json!({
            "view": "today",
            "panel_open": true
        })),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn parse_preference_row_value_rejects_malformed_stored_json() {
    let conn = open_temp_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "broken_pref",
            "{not-valid-json",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert malformed preference");

    let row = load_preference_row(&conn, "broken_pref").expect("load stored preference row");
    let error = parse_preference_row_value(row)
        .expect_err("malformed preference should fail")
        .to_string();

    assert!(error.contains("broken_pref"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn get_preference_rejects_malformed_stored_json() {
    let conn = open_temp_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "broken_pref",
            "{not-valid-json",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert malformed preference");

    let error = get_preference(
        &conn,
        crate::contract::GetPreferenceArgs {
            key: "broken_pref".to_string(),
        },
    )
    .expect_err("malformed preference should fail get_preference")
    .to_string();

    assert!(error.contains("broken_pref"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn get_all_preferences_rejects_malformed_stored_json() {
    let conn = open_temp_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "broken_pref",
            "{not-valid-json",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert malformed preference");

    let error = get_all_preferences(&conn)
        .expect_err("malformed preference should fail get_all_preferences")
        .to_string();

    assert!(error.contains("broken_pref"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_enqueues_typed_preference_value_snapshot() {
    // pick any non-forbidden preference key for the
    // payload-shape assertion. `weekly_review_day` is an
    // assistant-settable string preference.
    let conn = open_temp_db();

    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "weekly_review_day".to_string(),
            value: json!("monday"),
            idempotency_key: None,
        },
    )
    .expect("set preference");

    let payload_raw: String = conn
        .query_row(
            "SELECT payload
             FROM sync_outbox
             WHERE entity_type = 'preference' AND entity_id = 'weekly_review_day'
             ORDER BY id DESC
             LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("load preference sync payload");
    let payload: Value = serde_json::from_str(&payload_raw).expect("parse preference sync payload");

    assert_eq!(payload["key"], "weekly_review_day");
    assert_eq!(payload["value"], json!("monday"));
}

#[test]
#[serial_test::serial(hlc)]
fn set_preference_rejects_forbidden_assistant_keys() {
    // every key on the MCP deny-list must refuse write.
    // The most trust-critical is `ai_changelog_retention_policy` —
    // the assistant could otherwise erase its own audit trail.
    let conn = open_temp_db();
    for key in [
        "timezone",
        "theme",
        "ai_changelog_retention_policy",
        "error_log_retention_days",
        "sync_enabled",
        "memory_lock_enabled",
        "language",
    ] {
        let result = set_preference(
            &conn,
            crate::contract::SetPreferenceArgs {
                key: key.to_string(),
                value: json!("anything"),
                idempotency_key: None,
            },
        );
        let err = result.expect_err(&format!("must reject {key}"));
        match err {
            McpError::Validation(msg) => {
                assert!(
                    msg.contains("user-scope only"),
                    "expected user-scope message for {key}, got: {msg}"
                );
            }
            other => panic!("expected Validation for {key}, got {other:?}"),
        }
    }
}

#[test]
#[serial_test::serial(hlc)]
fn delete_preference_rejects_forbidden_assistant_keys() {
    // Symmetric to set: clearing a forbidden pref is equivalent to
    // changing it (reverts to default behavior the user didn't pick).
    let conn = open_temp_db();
    let result = delete_preference(
        &conn,
        crate::contract::DeletePreferenceArgs {
            key: "ai_changelog_retention_policy".to_string(),
            dry_run: false,
            idempotency_key: None,
        },
    );
    let err = result.expect_err("must reject delete of retention pref");
    match err {
        McpError::Validation(msg) => assert!(msg.contains("user-scope only")),
        other => panic!("expected Validation, got {other:?}"),
    }
}

/// Regression for #2966-H2: the create branch of `set_preference`
/// must populate `after_json` with the post-write preference row.
/// Pre-fix it passed `(None, None)` and the changelog row had no
/// after-state to show even though the live `pref` was already in
/// scope.
#[test]
#[serial_test::serial(hlc)]
fn set_preference_create_logs_after_json_with_post_write_row() {
    let conn = open_temp_db();

    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "weekly_review_day".to_string(),
            value: json!("friday"),
            idempotency_key: None,
        },
    )
    .expect("create preference");

    let (operation, before_raw, after_raw): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT operation, before_json, after_json FROM ai_changelog \
             WHERE entity_type = 'preference' AND entity_id = 'weekly_review_day' \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("changelog row for create");
    assert_eq!(operation, "create");
    assert!(
        before_raw.is_none(),
        "create branch must not record a before snapshot"
    );
    let after_raw = after_raw.expect("after_json must be populated on create");
    let after: Value = serde_json::from_str(&after_raw).expect("parse after_json");
    assert_eq!(
        after.get("key").and_then(Value::as_str),
        Some("weekly_review_day")
    );
    // The stored value column is the raw JSON-encoded string. Confirm
    // it round-trips back to the typed value the caller passed in.
    let raw_value = after
        .get("value")
        .and_then(Value::as_str)
        .expect("after_json should preserve raw stored value");
    let parsed: Value = serde_json::from_str(raw_value).expect("parse stored value");
    assert_eq!(parsed, json!("friday"));
}

#[test]
#[serial_test::serial(hlc)]
fn rust_theme_modes_match_shared_contract() {
    let rust_theme_modes = THEME_MODES
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    assert_eq!(rust_theme_modes, shared_theme_modes());
}

#[test]
#[serial_test::serial(hlc)]
fn rust_appearance_profiles_match_shared_contract() {
    let rust_profiles = APPEARANCE_PROFILES
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    assert_eq!(rust_profiles, shared_appearance_profiles());
}

#[test]
#[serial_test::serial(hlc)]
fn rust_assistant_ui_views_match_shared_contract() {
    let rust_views = ASSISTANT_UI_VIEWS
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    assert_eq!(rust_views, shared_assistant_ui_views());
}

#[test]
#[serial_test::serial(hlc)]
fn rust_assistant_ui_languages_match_shared_contract() {
    let rust_languages = ASSISTANT_UI_LANGUAGES
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    assert_eq!(rust_languages, shared_assistant_ui_languages());
}

// set_preference returns an undo_token carrying the prior value so a
// reverse write can restore it. A first-time write (no prior row)
// yields a token whose `had_prior_value` is false so the reverse
// write clears the key instead of restoring.
#[test]
#[serial_test::serial(hlc)]
fn set_preference_returns_undo_token_for_new_key() {
    let conn = open_temp_db();

    let response = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "dashboard_layout".to_string(),
            value: json!({ "count": 3 }),
            idempotency_key: None,
        },
    )
    .expect("set_preference must succeed on fresh key");

    let payload: Value = serde_json::from_str(&response).expect("parse response");
    let undo_raw = payload
        .get("undo_token")
        .and_then(Value::as_str)
        .expect("response must carry undo_token");
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(undo_raw).expect("token parses");
    assert_eq!(token.kind, crate::runtime::undo::McpUndoKind::SetPreference);
    assert_eq!(token.entity_id.as_deref(), Some("dashboard_layout"));
    assert!(
        !token.had_prior_value,
        "fresh-key token must mark had_prior_value = false so revert clears the row"
    );
    assert!(token.prior_value_json.is_none());
}

// Updating an existing preference captures the prior value in the
// undo token, and the outbox envelope is enqueued plain (immediately
// dispatchable).
#[test]
#[serial_test::serial(hlc)]
fn set_preference_update_token_captures_prior_value_and_enqueues_plain() {
    let conn = open_temp_db();

    // First write establishes the prior state.
    set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "quiet_hours_start".to_string(),
            value: json!({ "start": "22:00", "end": "06:00" }),
            idempotency_key: None,
        },
    )
    .expect("seed prior value");

    // Second write is the one we test — token should carry the prior
    // shape and the outbox envelope should be enqueued plain.
    let response = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "quiet_hours_start".to_string(),
            value: json!({ "start": "21:00", "end": "07:00" }),
            idempotency_key: None,
        },
    )
    .expect("update preference");
    let payload: Value = serde_json::from_str(&response).expect("parse response");
    let undo_raw = payload
        .get("undo_token")
        .and_then(Value::as_str)
        .expect("undo_token present");
    let token: crate::runtime::undo::McpUndoToken = serde_json::from_str(undo_raw).unwrap();
    assert!(
        token.had_prior_value,
        "update token records prior_value_json"
    );
    let prior = token
        .prior_value_json
        .as_ref()
        .expect("prior_value_json populated on update");
    assert_eq!(prior["start"], json!("22:00"));

    let envelope_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'preference' AND entity_id = 'quiet_hours_start'",
            [],
            |row| row.get(0),
        )
        .expect("preference outbox envelope must exist");
    assert!(
        envelope_count >= 1,
        "preference update must enqueue an outbox envelope"
    );
}

/// the MCP `set_preference` writer must reject any
/// preference key not in `lorvex_domain::ALL_KNOWN_PREFERENCE_KEYS`.
/// Pre-fix the MCP path only enforced the deny-list of trust-critical
/// keys, leaving an unbounded `(key, value)` write where a hostile
/// assistant could pollute the preferences table with arbitrary keys
/// or redirect path-shaped values to attacker-chosen locations. This
/// mirrors the Tauri-side guard added in #2988-H8.
#[test]
#[serial_test::serial(hlc)]
fn set_preference_rejects_unknown_keys() {
    let conn = open_temp_db();

    let err = set_preference(
        &conn,
        crate::contract::SetPreferenceArgs {
            key: "definitely_not_a_known_preference_key".to_string(),
            value: json!("hello"),
            idempotency_key: None,
        },
    )
    .expect_err("unknown preference keys must be rejected by MCP path");
    match err {
        McpError::Validation(msg) => assert!(
            msg.contains("not a known preference key"),
            "expected unknown-key validation error, got {msg}"
        ),
        other => panic!("expected Validation, got {other:?}"),
    }
}
