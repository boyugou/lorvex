use super::*;
use crate::contract::{ControlAppUiArgs, UiAction};
use crate::db::open_database_for_path;
use rusqlite::params;
use rusqlite::Connection;
use serde_json::Value;
use tempfile::tempdir;

mod appearance_and_language;
mod corruption;
mod navigation;
mod shared_contracts;
mod task_targeting;

fn shared_const_string_values(const_name: &str) -> Vec<String> {
    let source = include_str!("../../../../../shared/src/types.ts");
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

fn shared_assistant_ui_actions() -> Vec<String> {
    shared_const_string_values("ASSISTANT_UI_ACTIONS")
}

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_list(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?, ?)",
        params![id, "Test List", "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"],
    )
    .expect("seed list");
}

fn seed_task(conn: &Connection, id: &str, status: &str) {
    // lift to canonical TaskBuilder.
    let title = format!("Task {id}");
    lorvex_store::test_support::TaskBuilder::new(id)
        .title(&title)
        .status(status)
        .created_at("2026-03-01T00:00:00Z")
        .insert(conn);
}
