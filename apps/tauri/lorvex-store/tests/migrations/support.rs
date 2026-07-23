use rusqlite::{params, Connection};

pub(super) const V: &str = "0000000000000_0000_0000000000000000";
pub(super) const TS: &str = "2026-03-01T00:00:00Z";

pub(super) fn table_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?1",
            [name],
            |row| row.get(0),
        )
        .unwrap();
    count > 0
}

pub(super) fn column_exists(conn: &Connection, table: &str, column: &str) -> bool {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .unwrap();
    let cols: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect();
    cols.contains(&column.to_string())
}

pub(super) fn index_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?1",
            [name],
            |row| row.get(0),
        )
        .unwrap();
    count > 0
}

pub(super) fn insert_base_task(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?1, ?1, 'open', ?2, ?3, ?3)",
        params![id, V, TS],
    ).unwrap();
}

pub(super) fn column_set(conn: &Connection, table: &str) -> std::collections::BTreeSet<String> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .unwrap();
    stmt.query_map([], |row| row.get::<_, String>(1))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect()
}

pub(super) fn normalized_table_sql(conn: &Connection, table: &str) -> String {
    conn.query_row(
        "SELECT sql FROM sqlite_schema WHERE type = 'table' AND name = ?1",
        [table],
        |row| row.get::<_, String>(0),
    )
    .unwrap()
    .split_whitespace()
    .collect::<Vec<_>>()
    .join(" ")
}

pub(super) fn assert_sql_fails(conn: &Connection, sql: &str) {
    assert!(
        conn.execute(sql, []).is_err(),
        "expected SQL to fail at the schema boundary: {sql}"
    );
}

const STORE_ONLY_SQLITE_BOOL_COLUMNS: &[(&str, &str)] = &[
    ("provider_calendar_events", "all_day"),
    ("provider_scope_runtime_state", "enabled"),
];

pub(super) struct BoolColumnCheckCase {
    pub(super) invalid_insert: &'static str,
    pub(super) valid_insert: &'static str,
    pub(super) invalid_update: &'static str,
}

pub(super) fn semantic_sqlite_bool_columns() -> impl Iterator<Item = (&'static str, &'static str)> {
    lorvex_domain::storage_schema::SQLITE_BOOL_COLUMNS
        .iter()
        .copied()
        .chain(STORE_ONLY_SQLITE_BOOL_COLUMNS.iter().copied())
}
