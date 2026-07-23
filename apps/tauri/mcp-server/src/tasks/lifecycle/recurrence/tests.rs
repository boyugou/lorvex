use super::*;
use crate::db::open_database_for_path;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

/// pre-fix the `set_recurrence` boundary UPDATE
/// wrote `updated_at` only, leaving `version` stale even after
/// `apply_recurrence_change` rewrote the recurrence rule. Peers'
/// apply pipeline silently dropped the resulting upsert envelope
/// under the `excluded.version > tasks.version` LWW gate. Pin
/// the bump.
#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_bumps_parent_task_version() {
    let conn = open_temp_db();
    let now = "2026-04-05T00:00:00Z";
    let initial_version = "0000000000000_0000_0000000000000000";
    // set_recurrence requires a due_date (the recurrence-config
    // domain invariant rejects recurring tasks without one).
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000116")
        .title("Task H3")
        .version(initial_version)
        .created_at(now)
        .due_date(Some("2026-04-15"))
        .insert(&conn);

    let read_version = |c: &Connection| -> String {
        c.query_row(
            "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000116'",
            [],
            |row| row.get::<_, String>(0),
        )
        .expect("read version")
    };
    assert_eq!(read_version(&conn), initial_version);

    set_recurrence(
        &conn,
        SetRecurrenceArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000116".to_string(),
            rule: crate::contract::RecurrenceRuleArgs {
                freq: crate::contract::RecurrenceFreq::Daily,
                interval: Some(1),
                byday: None,
                bymonth: None,
                bymonthday: None,
                bysetpos: None,
                wkst: None,
                until: None,
                count: None,
            },
            idempotency_key: None,
        },
    )
    .expect("set recurrence");

    let after_version = read_version(&conn);
    assert_ne!(
        after_version, initial_version,
        "set_recurrence must mint a fresh HLC version on the parent task"
    );
    assert!(
        after_version.as_str() > initial_version,
        "fresh HLC must be strictly greater than the seed (#2975-H3)"
    );
}
