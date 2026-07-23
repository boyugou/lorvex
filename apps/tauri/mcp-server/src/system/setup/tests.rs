use super::*;
use crate::db::open_database_for_path;
use rusqlite::Connection;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

/// Regression for #2966-H9: a first-time `complete_setup` on a
/// brand-new DB emits a `create` audit row with `before_json` left
/// null (no prior preferences existed).
#[test]
#[serial_test::serial(hlc)]
fn complete_setup_first_run_logs_create_with_null_before_json() {
    let conn = open_temp_db();

    complete_setup(
        &conn,
        CompleteSetupArgs {
            summary: "Initial run".to_string(),
            idempotency_key: None,
        },
    )
    .expect("complete setup");

    let (operation, before_raw, after_raw): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT operation, before_json, after_json FROM ai_changelog \
             WHERE mcp_tool = 'complete_setup' \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("changelog row");
    assert_eq!(
        operation, "create",
        "first-run complete_setup should log a create"
    );
    assert!(
        before_raw.is_none(),
        "first-run before_json must be null (no prior prefs existed)"
    );
    let after_raw = after_raw.expect("after_json must be populated");
    let after: Value = serde_json::from_str(&after_raw).expect("parse after_json");
    assert!(after.get("setup_completed").is_some());
    assert!(after.get("setup_summary").is_some());
    assert!(after.get("setup_state").is_some());
}

/// Regression for #2966-H9: re-running `complete_setup` (the
/// assistant-driven onboarding can be re-run) MUST log an `update`
/// row whose `before_json` carries the prior values for the three
/// keys that already existed. Pre-fix the changelog hardcoded
/// `operation: "create"` and dropped `before_json`, erasing the
/// prior state from the audit trail.
#[test]
#[serial_test::serial(hlc)]
fn complete_setup_re_run_logs_update_with_prior_state_in_before_json() {
    let conn = open_temp_db();

    complete_setup(
        &conn,
        CompleteSetupArgs {
            summary: "First run".to_string(),
            idempotency_key: None,
        },
    )
    .expect("first complete setup");

    complete_setup(
        &conn,
        CompleteSetupArgs {
            summary: "Re-run".to_string(),
            idempotency_key: None,
        },
    )
    .expect("second complete setup");

    let (operation, before_raw, after_raw): (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT operation, before_json, after_json FROM ai_changelog \
             WHERE mcp_tool = 'complete_setup' \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("changelog row for re-run");
    assert_eq!(
        operation, "update",
        "re-running complete_setup must log an update, not a create"
    );
    let before_raw = before_raw.expect("before_json must be populated on re-run");
    let before: Value = serde_json::from_str(&before_raw).expect("parse before_json");
    let prior_summary = before
        .get("setup_summary")
        .and_then(|v| v.get("value"))
        .and_then(Value::as_str)
        .expect("prior setup_summary value present");
    assert_eq!(
        prior_summary, "First run",
        "before_json must carry the prior summary verbatim"
    );

    let after_raw = after_raw.expect("after_json must be populated");
    let after: Value = serde_json::from_str(&after_raw).expect("parse after_json");
    let new_summary = after
        .get("setup_summary")
        .and_then(|v| v.get("value"))
        .and_then(Value::as_str)
        .expect("new setup_summary value present");
    assert_eq!(new_summary, "Re-run");
}
