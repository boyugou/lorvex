//! Shared fixtures and re-exports for the habit write-tool test
//! suite. Each per-domain split file pulls these in via
//! `use super::support::*;`.

pub(super) use super::super::*;
pub(super) use crate::db::open_database_for_path;
pub(super) use crate::habits::Habit;
pub(super) use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
pub(super) use rusqlite::{params, Connection};
pub(super) use tempfile::tempdir;

pub(super) fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

pub(super) fn seed_habit(conn: &Connection, id: &str, name: &str) {
    let now = "2026-03-29T00:00:00Z";
    conn.execute(
        "INSERT INTO habits (id, name, created_at, updated_at, version) VALUES (?1, ?2, ?3, ?3, '0000000000000_0000_0000000000000000')",
        params![id, name, now],
    )
    .expect("insert habit");
}

/// Insert a habit completion row for a fixed test date.
pub(super) fn seed_completion(conn: &Connection, habit_id: &str, date: &str) {
    let now = "2026-03-29T00:00:00Z";
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
         VALUES (?1, ?2, 1, '0000000000000_0000_0000000000000000', ?3, ?3)",
        params![habit_id, date, now],
    )
    .expect("insert completion");
}

pub(super) fn seed_completion_with_note(
    conn: &Connection,
    habit_id: &str,
    date: &str,
    note: Option<&str>,
) {
    let now = "2026-03-29T00:00:00Z";
    conn.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, note, version, created_at, updated_at)
         VALUES (?1, ?2, 1, ?3, '0000000000000_0000_0000000000000000', ?4, ?4)",
        params![habit_id, date, note, now],
    )
    .expect("insert completion");
}

pub(super) fn deny_habit_completion_reads(conn: &Connection) {
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "habit_completions",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");
}

pub(super) fn clear_authorizer(conn: &Connection) {
    conn.authorizer(None::<fn(AuthContext<'_>) -> Authorization>)
        .expect("clear authorizer");
}

/// Insert a habit reminder policy row for tombstone coverage. The
/// unique (habit_id, reminder_time) index means each policy on the
/// same habit must carry a distinct time.
pub(super) fn seed_reminder_policy(
    conn: &Connection,
    id: &str,
    habit_id: &str,
    reminder_time: &str,
) {
    let now = "2026-03-29T00:00:00Z";
    conn.execute(
        "INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, 1, '0000000000000_0000_0000000000000000', ?4, ?4)",
        params![id, habit_id, reminder_time, now],
    )
    .expect("insert reminder policy");
}
