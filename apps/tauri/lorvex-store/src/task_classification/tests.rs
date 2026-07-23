use super::{resolve_required_task_list_id, validate_task_list_exists};
use crate::open_db_in_memory;
use rusqlite::params;

fn setup() -> rusqlite::Connection {
    open_db_in_memory().expect("open in-memory db")
}

#[test]
fn resolve_required_task_list_id_prefers_explicit_list() {
    let conn = setup();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-03T00:00:00Z', '2026-04-03T00:00:00Z')",
        [],
    )
    .expect("seed list");

    assert_eq!(
        resolve_required_task_list_id(&conn, Some("l1")).expect("resolve explicit list"),
        "l1"
    );
}

#[test]
fn resolve_required_task_list_id_uses_default_list_preference() {
    let conn = setup();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-03T00:00:00Z', '2026-04-03T00:00:00Z')",
        [],
    )
    .expect("seed list");
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-03T00:00:00Z')",
        params![
            lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID,
            "\"l1\""
        ],
    )
    .expect("seed default list preference");

    assert_eq!(
        resolve_required_task_list_id(&conn, None).expect("resolve default list"),
        "l1"
    );
}

#[test]
fn validate_task_list_exists_rejects_missing_list() {
    let conn = setup();
    let typed = lorvex_domain::ListId::from_trusted("missing".to_string());
    let error = validate_task_list_exists(&conn, &typed).expect_err("missing list should fail");
    assert!(error.to_string().contains("does not exist"));
}
