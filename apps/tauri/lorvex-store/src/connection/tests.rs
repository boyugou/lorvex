use super::open_db_at_path;
use tempfile::tempdir;

#[test]
fn open_db_at_path_creates_inbox_list_and_default_list_preference() {
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");

    let conn = open_db_at_path(&path).expect("initialize database");

    // Inbox list should exist as seed data.
    let inbox_name: String = conn
        .query_row("SELECT name FROM lists WHERE id = 'inbox'", [], |row| {
            row.get(0)
        })
        .expect("inbox list exists");
    assert_eq!(inbox_name, "Inbox");

    // default_list_id preference should point to inbox.
    let default_list: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'default_list_id'",
            [],
            |row| row.get(0),
        )
        .expect("default_list_id preference exists");
    assert_eq!(default_list, "\"inbox\"");
}

#[test]
fn open_db_persists_db_locator_diagnostics() {
    let conn = crate::connection::open_db_in_memory().expect("initialize database");
    let diagnostics = vec![lorvex_runtime::DbLocationDiagnostic {
        code: lorvex_runtime::DbLocationDiagnosticCode::DbPathOverrideRejectedUnc,
        message: "DB_PATH override rejected; using platform default DB location".to_string(),
        details: Some(
            "UNC / network share paths are not supported because SQLite WAL mode is unsafe over SMB."
                .to_string(),
        ),
        level: "warn",
    }];

    super::persist_db_location_diagnostics(&conn, &diagnostics);

    let row: (String, String, String, Option<String>) = conn
        .query_row(
            "SELECT source, level, message, details FROM error_logs \
             WHERE source = 'store.db_locator.db_path_override_rejected_unc'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("db locator diagnostic is persisted");
    assert_eq!(row.0, "store.db_locator.db_path_override_rejected_unc");
    assert_eq!(row.1, "warn");
    assert!(row.2.contains("DB_PATH override rejected"));
    assert!(row
        .3
        .as_deref()
        .unwrap_or_default()
        .contains("UNC / network share paths"));
    assert!(!row.3.as_deref().unwrap_or_default().contains("fileserver"));
}

#[test]
fn apply_pragmas_enables_incremental_auto_vacuum() {
    // new installs must receive `auto_vacuum =
    // INCREMENTAL` so `PRAGMA incremental_vacuum(N)` actually has
    // pages to reclaim. Mode `0` (NONE) or `1` (FULL) would make
    // the maintenance pass a no-op or auto-vacuum on every commit.
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");
    let conn = open_db_at_path(&path).expect("initialize database");
    let mode: i64 = conn
        .query_row("PRAGMA auto_vacuum", [], |row| row.get(0))
        .expect("read auto_vacuum");
    assert_eq!(mode, 2, "expected INCREMENTAL (2) auto_vacuum mode");
}

#[test]
fn run_periodic_maintenance_is_a_noop_on_empty_db() {
    // Must not error on a fresh DB with no data — the cron runs
    // this from day 1 per.
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");
    let conn = open_db_at_path(&path).expect("initialize database");
    super::run_periodic_maintenance(&conn).expect("periodic maintenance succeeds on empty db");
}

#[test]
fn run_integrity_check_reports_empty_findings_on_healthy_db() {
    // the healthy-case contract — a fresh migrated
    // DB has no corruption and no orphan FK rows, so the vec is
    // empty. If this regresses (e.g. a migration forgets to
    // populate a FK-bearing column), the 6-hour cron will start
    // writing warn-level entries to error_logs and the UI can
    // surface them.
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");
    let conn = open_db_at_path(&path).expect("initialize database");
    let findings = super::run_integrity_check(&conn).expect("integrity check runs on healthy db");
    assert!(
        findings.is_empty(),
        "fresh DB must pass integrity_check + foreign_key_check, got: {findings:?}"
    );
}

/// the `foreign_key_check: …` push
/// branch must format orphan rows correctly. Without coverage,
/// a refactor that lost the `parent=`, `fkid=`, or rowid columns
/// would silently emit garbage findings into `error_logs` for
/// the 6-hour cron's audit trail.
#[test]
fn run_integrity_check_surfaces_orphan_foreign_key_rows() {
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");
    let conn = open_db_at_path(&path).expect("initialize database");

    // Inject an orphan task pointing at a non-existent list_id
    // by temporarily disabling foreign keys so the INSERT is
    // accepted, then re-enabling so `PRAGMA foreign_key_check`
    // surfaces the now-orphaned row.
    conn.execute_batch("PRAGMA foreign_keys = OFF;")
        .expect("disable FK enforcement for orphan injection");
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, version, created_at, updated_at, defer_count
         ) VALUES (
            'orphan-task', 'Orphan', 'open', 'nonexistent-list',
            '0000000000000_0000_0000000000000000',
            '2026-04-19T00:00:00Z', '2026-04-19T00:00:00Z', 0
         )",
        [],
    )
    .expect("orphan insert with FKs disabled");
    conn.execute_batch("PRAGMA foreign_keys = ON;")
        .expect("re-enable FK enforcement");

    let findings = super::run_integrity_check(&conn).expect("integrity check runs on corrupted db");
    let fk_findings: Vec<&String> = findings
        .iter()
        .filter(|f| f.starts_with("foreign_key_check:"))
        .collect();
    assert!(
        !fk_findings.is_empty(),
        "expected at least one foreign_key_check finding for the orphan task"
    );
    let line = fk_findings[0];
    assert!(line.contains("table=tasks"), "missing table=tasks: {line}");
    assert!(
        line.contains("parent=lists"),
        "missing parent=lists: {line}"
    );
    assert!(line.contains("fkid="), "missing fkid: {line}");
    assert!(line.contains("rowid="), "missing rowid: {line}");
}

#[test]
fn list_id_not_null_is_enforced() {
    let dir = tempdir().expect("create temp dir");
    let path = dir.path().join("lorvex.db");

    let conn = open_db_at_path(&path).expect("initialize database");

    let result = conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, version, created_at, updated_at, defer_count
         ) VALUES (
            'test-task', 'Test', 'open', NULL, '0000000000000_0000_0000000000000000',
            '2026-04-04T00:00:00Z', '2026-04-04T00:00:00Z', 0
         )",
        [],
    );
    assert!(
        result.is_err(),
        "NULL list_id should be rejected by NOT NULL constraint"
    );
}
