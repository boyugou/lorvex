pub(super) use super::*;
pub(super) use crate::contract::*;
pub(super) use crate::json_row::query_one_as_json;
pub(super) use rmcp::handler::server::wrapper::Parameters;
pub(super) use serde_json::Value;

use lorvex_store::ConnectionPool;

mod calendar;
mod cancellation;
mod control_app_ui;
mod daily_review;
mod guidance;
mod habits;
mod lists_overview;
mod overview_setup;
mod planning;
mod save_focus_schedule;
mod spawn_blocking;
mod tasks;
mod triage_and_logs;
mod untrusted_fencing;
mod weekly_review;

/// In-memory `LorvexMcpServer` fixture for unit tests.
///
/// Construction resets the process-global HLC + clock state and seeds
/// a fresh sync device id into a per-call in-memory pool. Every test
/// in this tree carries `#[serial_test::serial(hlc)]`, which is the
/// single source of serialization against the shared HLC state — no
/// additional fixture-owned mutex is required. The fixture used to
/// hold its own mutex guard for the entire test lifetime, but that
/// duplicated `serial_test`'s lock and silently failed open on any
/// test that forgot to opt in (#4442).
///
/// Backed by `ConnectionPool::new_in_memory` (per-call shared-cache
/// `vfs=memdb` URI) so tests avoid the ~50 ms/test fs IO and the
/// WAL/SHM cleanup churn an on-disk SQLite DB would impose on
/// `/tmp`-quota CI runners.
pub(super) struct TestServer {
    server: LorvexMcpServer,
}

impl std::ops::Deref for TestServer {
    type Target = LorvexMcpServer;
    fn deref(&self) -> &Self::Target {
        &self.server
    }
}

fn make_server() -> TestServer {
    use crate::runtime::change_tracking::get_or_create_sync_device_id;

    // Keep the historical clock reset hook in the canonical fixture.
    // `utc_now_iso` now delegates to the domain sync timestamp helper,
    // but retaining the fixture call avoids scattering clock-reset
    // knowledge if a future test-only clock state is introduced.
    crate::system::handler_support::reset_clock_state_for_tests();
    // same class of cross-test pollution for the HLC
    // state. The first test's device_id + counter otherwise persist
    // for every subsequent test in the binary.
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();

    let pool = ConnectionPool::new_in_memory(2).expect("create connection pool");

    {
        let conn = pool.writer_result().expect("writer lock");
        get_or_create_sync_device_id(&conn).unwrap_or_else(|_| "test-device-00000000".to_string());
    }

    let server = LorvexMcpServer {
        pool: Arc::new(pool),
        tool_router: LorvexMcpServer::import_export_tool_router()
            + LorvexMcpServer::preferences_tool_router()
            + LorvexMcpServer::calendar_tool_router()
            + LorvexMcpServer::list_tool_router()
            + LorvexMcpServer::task_tool_router()
            + LorvexMcpServer::query_tool_router()
            + LorvexMcpServer::workflow_tool_router(),
        // Generous timeout for tests — #2385 watchdog is meant to
        // catch runaway handlers in production, not racy CI boxes.
        tool_timeout: std::time::Duration::from_secs(600),
        in_flight: crate::shutdown::InFlightTracker::default(),
    };
    TestServer { server }
}

#[test]
#[serial_test::serial(hlc)]
fn constructor_runs_shared_startup_trash_purge() {
    let hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex poisoned");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();

    let dir = tempfile::tempdir().expect("create tempdir");
    let db_path = dir.path().join("mcp-startup.sqlite");
    {
        let conn = lorvex_store::open_db_at_path(&db_path).expect("initialize db");
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000701",
        )
        .archived_at(Some("2020-01-01T00:00:00.000Z"))
        .insert(&conn);
    }
    let db_path_str = db_path.to_string_lossy().to_string();

    lorvex_runtime::test_support::with_db_path_env_for_test(Some(&db_path_str), || {
        let server = LorvexMcpServer::new().expect("construct server");
        let conn = server.pool.writer_result().expect("writer lock");
        let task_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000701'",
                [],
                |row| row.get(0),
            )
            .expect("count purged task");
        let delete_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = 'task'
                   AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000701'
                   AND operation = 'delete'",
                [],
                |row| row.get(0),
            )
            .expect("count task delete outbox");
        assert_eq!(task_count, 0);
        assert_eq!(delete_count, 1);
        let audit_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM ai_changelog
                 WHERE mcp_tool = 'startup_trash_purge'",
                [],
                |row| row.get(0),
            )
            .expect("count startup trash audit rows");
        assert_eq!(
            audit_count, 0,
            "startup trash purge is system maintenance and must not write ai_changelog rows"
        );
        let diagnostic_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM error_logs
                 WHERE source = 'mcp.startup.trash_purge_deleted'
                   AND level = 'info'
                   AND details = 'deleted=1'",
                [],
                |row| row.get(0),
            )
            .expect("count startup trash purge diagnostics");
        assert_eq!(
            diagnostic_count, 1,
            "MCP startup trash purge maintenance notices should persist structurally"
        );
    });

    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    drop(hlc_guard);
}

#[test]
#[serial_test::serial(hlc)]
fn startup_sync_warning_persistence_keeps_pending_retention_mcp_namespaced() {
    let conn = lorvex_store::test_support::test_conn();
    let warnings = vec![
        lorvex_sync::startup_maintenance::StartupMaintenanceWarning {
            source: "sync.startup.pending_queue_retention_failed",
            message: "shared pending retention failure".to_string(),
            details: Some("shared-details".to_string()),
            level: "warn",
        },
        lorvex_sync::startup_maintenance::StartupMaintenanceWarning {
            source: "sync.startup.pending_inbox_gc_failed",
            message: "pending inbox startup GC failed".to_string(),
            details: Some("inbox-details".to_string()),
            level: "warn",
        },
    ];

    super::startup::persist_mcp_startup_sync_warnings(&conn, &warnings);
    super::startup::record_startup_warning(
        &conn,
        "mcp.startup.pending_queue_retention_failed",
        "MCP pending queue retention failed during startup",
        "mcp-details",
    );

    let shared_pending_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.startup.pending_queue_retention_failed'",
            [],
            |row| row.get(0),
        )
        .expect("count shared pending retention diagnostics");
    assert_eq!(shared_pending_count, 0);
    let mcp_pending_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'mcp.startup.pending_queue_retention_failed'
               AND level = 'warn'
               AND details = 'mcp-details'",
            [],
            |row| row.get(0),
        )
        .expect("count MCP pending retention diagnostics");
    assert_eq!(mcp_pending_count, 1);
    let other_shared_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.startup.pending_inbox_gc_failed'
               AND level = 'warn'",
            [],
            |row| row.get(0),
        )
        .expect("count non-pending shared warning diagnostics");
    assert_eq!(other_shared_count, 0);
    let mcp_shared_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'mcp.startup.sync_pending_inbox_gc_failed'
               AND level = 'warn'
               AND details = 'inbox-details'",
            [],
            |row| row.get(0),
        )
        .expect("count remapped shared warning diagnostics");
    assert_eq!(mcp_shared_count, 1);
}

#[test]
#[serial_test::serial(hlc)]
fn runtime_diagnostic_helper_persists_expected_shape() {
    let conn = lorvex_store::test_support::test_conn();

    record_runtime_warning(
        &conn,
        "mcp.runtime.transaction_begin_failed",
        "MCP tool transaction BEGIN IMMEDIATE failed",
        "database is locked",
    );

    let runtime_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'mcp.runtime.transaction_begin_failed'
               AND level = 'warn'
               AND details = 'database is locked'",
            [],
            |row| row.get(0),
        )
        .expect("count runtime diagnostic");
    assert_eq!(runtime_count, 1);
}

#[test]
#[serial_test::serial(hlc)]
fn with_conn_persists_savepoint_diagnostics_after_outer_rollback() {
    let server = make_server();

    let result: Result<(), String> = server.with_conn(|conn| {
        conn.execute_batch("ROLLBACK;")
            .expect("force savepoint cleanup failure by ending outer transaction");
        Err("forced savepoint failure".to_string())
    });

    assert!(result.is_err());
    let conn = server.pool.writer_result().expect("writer lock");
    let diagnostic_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'mcp.runtime.transaction_savepoint_failed'
               AND level = 'warn'
               AND details LIKE '%forced savepoint failure%'",
            [],
            |row| row.get(0),
        )
        .expect("count savepoint diagnostics");
    assert_eq!(
        diagnostic_count, 1,
        "transaction diagnostics must be written after rollback so they survive"
    );
}

fn seed_list(server: &LorvexMcpServer, id: &str) {
    seed_list_named(server, id, "Test List");
}
fn seed_list_named(server: &LorvexMcpServer, id: &str, name: &str) {
    server
        .with_conn(|conn| {
            lorvex_store::test_support::ListBuilder::new(id)
                .name(name)
                .created_at("2026-03-01T00:00:00Z")
                .insert(conn);
            Ok(())
        })
        .expect("seed named list");
}
#[allow(clippy::too_many_arguments)]
fn seed_task(
    server: &LorvexMcpServer,
    id: &str,
    title: &str,
    status: &str,
    list_id: Option<&str>,
    due_date: Option<&str>,
    due_time: Option<&str>,
    defer_count: i64,
) {
    // lift to canonical TaskBuilder.
    let resolved_list_id = list_id.unwrap_or("inbox");
    server
        .with_conn(|conn| {
            lorvex_store::test_support::TaskBuilder::new(id)
                .title(title)
                .status(status)
                .list_id(Some(resolved_list_id))
                .due_date(due_date)
                .due_time(due_time)
                .defer_count(defer_count)
                .created_at("2026-03-01T00:00:00Z")
                .insert(conn);
            Ok(())
        })
        .expect("seed task");
}
