use super::effects::*;
use lorvex_store::open_db_in_memory;
use rusqlite::Connection;

fn seed_error_log(conn: &Connection, id: &str, source: &str, level: &str, ts: &str) {
    conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at) \
         VALUES (?1, ?2, ?3, 'oops', NULL, ?4)",
        rusqlite::params![id, source, level, ts],
    )
    .expect("seed log");
}

#[test]
fn list_recent_error_logs_returns_newest_first() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = open_db_in_memory().expect("open db");
    seed_error_log(&conn, "e-1", "sync", "error", "2026-04-10T00:00:00Z");
    seed_error_log(&conn, "e-2", "mcp", "warn", "2026-04-20T00:00:00Z");
    seed_error_log(&conn, "e-3", "sync", "error", "2026-04-15T00:00:00Z");

    let rows = list_recent_error_logs_with_conn(&conn, 10, None).expect("query");
    let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["e-2", "e-3", "e-1"]);
}

#[test]
fn list_recent_error_logs_filters_by_source() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = open_db_in_memory().expect("open db");
    seed_error_log(&conn, "e-1", "sync", "error", "2026-04-10T00:00:00Z");
    seed_error_log(&conn, "e-2", "mcp", "warn", "2026-04-20T00:00:00Z");
    let rows = list_recent_error_logs_with_conn(&conn, 10, Some("sync")).expect("filtered");
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].source, "sync");
}

#[test]
fn list_recent_error_logs_honors_limit() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = open_db_in_memory().expect("open db");
    for i in 0..5 {
        seed_error_log(
            &conn,
            &format!("e-{i}"),
            "sync",
            "error",
            &format!("2026-04-{:02}T00:00:00Z", 10 + i),
        );
    }
    let rows = list_recent_error_logs_with_conn(&conn, 2, None).expect("limited");
    assert_eq!(rows.len(), 2);
}
