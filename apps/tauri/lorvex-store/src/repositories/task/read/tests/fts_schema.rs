use super::super::search::is_fts_schema_missing;
use super::support::StoreError;
use rusqlite::Connection;

// pin `is_fts_schema_missing` against live SQLite
// error wording. The function decides whether search silently
// degrades to the LIKE fallback. A rusqlite / system-SQLite
// upgrade that reworded "no such table" / "no such module" would
// silently break the fallback on fresh installs — search would
// error where it used to degrade.
//
// `is_fts_schema_missing` now consumes `&StoreError`
// (#3027-M2). Wrap the live rusqlite error through the same
// classifier production code uses (`StoreError::from`) so the test
// pins the boundary contract end-to-end, not a private rusqlite
// shape that could drift away from the typed crate-error.
#[test]
fn is_fts_schema_missing_matches_live_sqlite_missing_table_text() {
    let conn = Connection::open_in_memory().unwrap();
    let err: StoreError = conn
        .prepare("SELECT rowid FROM tasks_fts WHERE tasks_fts MATCH 'x'")
        .unwrap_err()
        .into();
    assert!(
        is_fts_schema_missing(&err),
        "SQLite wording for missing-table drifted: {err}",
    );
}

#[test]
fn is_fts_schema_missing_rejects_real_errors() {
    // A generic "bad column" error must NOT be classified as
    // schema-missing — otherwise silent empty results would hide
    // real bugs in the search query.
    let conn = Connection::open_in_memory().unwrap();
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, title TEXT)", [])
        .unwrap();
    let err: StoreError = conn
        .prepare("SELECT no_such_column FROM t")
        .unwrap_err()
        .into();
    assert!(
        !is_fts_schema_missing(&err),
        "generic SQL error should not be classified as schema-missing: {err}",
    );
}
