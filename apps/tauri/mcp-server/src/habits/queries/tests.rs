use super::*;
use crate::db::open_database_for_path;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
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
#[serial_test::serial(hlc)]
fn get_habit_stats_surfaces_lookup_failures() {
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

    let error = String::from(
        get_habit_stats(
            &conn,
            &lorvex_domain::HabitId::from_trusted(
                "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            ),
        )
        .expect_err("habit lookup failure should surface"),
    );
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
#[serial_test::serial(hlc)]
fn get_habit_stats_surfaces_completion_aggregate_failures() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habit_completions",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = String::from(
        get_habit_stats(
            &conn,
            &lorvex_domain::HabitId::from_trusted(
                "01966a3f-7c8b-7d4e-8f3a-000000000201".to_string(),
            ),
        )
        .expect_err("completion aggregate failure should surface"),
    );
    assert!(
        error.contains("internal error") || error.contains("Please try again"),
        "unexpected error: {error}"
    );
    assert!(
        !error.contains("\"total_completions\":0"),
        "aggregate failure must not degrade into zeroed stats: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_habit_stats_rejects_invalid_completed_date() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000201', 'not-a-date', 1, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        [],
    )
    .expect("insert invalid completion");

    let error = get_habit_stats(
        &conn,
        &lorvex_domain::HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()),
    )
    .expect_err("invalid completion date should be rejected")
    .to_string();
    assert!(error.contains("not-a-date"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn get_habits_summary_rejects_invalid_completed_date() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000201", "Meditate");
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000201', '2026-99-99', 1, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        [],
    )
    .expect("insert invalid completion");

    let error = get_habits_summary(&conn, false)
        .expect_err("invalid completion date should be rejected")
        .to_string();
    assert!(error.contains("2026-99-99"), "unexpected error: {error}");
}
