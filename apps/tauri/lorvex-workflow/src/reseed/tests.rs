use super::*;
use lorvex_store::open_db_in_memory;

#[test]
fn clear_canonical_tables_succeeds_on_empty_db() {
    let mut conn = open_db_in_memory().unwrap();
    // caller is responsible for the surrounding
    // transaction. Use rusqlite's `Transaction` so the
    // `debug_assert!(!is_autocommit())` guard matches the
    // documented contract.
    let tx = conn.transaction().unwrap();
    let result = clear_canonical_tables_for_reseed(&tx).unwrap();
    tx.commit().unwrap();
    assert!(result.tables_cleared > 0);
}

/// misuse — calling the helper in autocommit
/// mode — must trip the debug-build guard. Verifies the
/// contract is enforced where it matters most (test runs).
#[test]
#[should_panic(expected = "must be called inside a transaction")]
#[cfg(debug_assertions)]
fn clear_canonical_tables_panics_in_autocommit_mode() {
    let conn = open_db_in_memory().unwrap();
    let _ = clear_canonical_tables_for_reseed(&conn);
}

#[test]
fn is_reseed_required_false_by_default() {
    let conn = open_db_in_memory().unwrap();
    assert!(!is_reseed_required(&conn).unwrap());
}

#[test]
fn is_reseed_required_true_when_flag_set() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true')",
        [],
    )
    .unwrap();
    assert!(is_reseed_required(&conn).unwrap());
}

#[test]
fn complete_reseed_clears_flag_and_outbox() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', 'dev-1')",
        [],
    )
    .unwrap();

    complete_reseed(&conn).unwrap();

    assert!(!is_reseed_required(&conn).unwrap());
    // device_id should be preserved... actually our DELETE WHERE key != 'device_id'
    // followed by DELETE FROM sync_checkpoints WHERE key = 'reseed_required'
    // The second DELETE already ran, and the first DELETE cleared everything except device_id.
    let device_id: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'device_id'",
            [],
            |row| row.get(0),
        )
        .ok();
    assert_eq!(device_id.as_deref(), Some("dev-1"));
}
