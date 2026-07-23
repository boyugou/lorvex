//! `LorvexMcpServer::new()` — the production constructor.
//!
//! The test-only constructor lives in `server/tests/mod.rs::make_server`
//! and inlines a different shape (in-memory pool, generous tool
//! timeout) so that test runs don't touch the real DB locator or
//! startup maintenance side effects.
//!
//! Each `startup::run_*_step` lifts one inline concern out
//! of this constructor; only step 1 (sync startup maintenance) is
//! fatal, the rest log and continue. See `server/startup.rs` for the
//! per-step contract.

use std::sync::Arc;

use lorvex_store::ConnectionPool;

use super::{startup, LorvexMcpServer, MCP_READ_POOL_SIZE};
use crate::runtime::change_tracking::get_or_create_sync_device_id;
use crate::runtime::tool_timeout::resolve_tool_timeout;
use crate::shutdown::InFlightTracker;

impl LorvexMcpServer {
    pub fn new() -> Result<Self, String> {
        let db_path = crate::db::resolve_db_path();
        let pool = ConnectionPool::new(&db_path, MCP_READ_POOL_SIZE)
            .map_err(|e| format!("failed to create connection pool: {e}"))?;
        let tool_timeout = resolve_tool_timeout();

        // Ensure the stable device ID exists and run startup maintenance.
        // Each `startup::run_*_step` lifts one inline concern
        // out of this constructor; only step 1 is fatal, the rest log
        // and continue. See `server/startup.rs` for the per-step contract.
        {
            let conn = pool
                .writer_result()
                .map_err(|e| format!("failed to lock writer connection: {e}"))?;
            lorvex_store::persist_pending_db_location_diagnostics(&conn);
            startup::run_sync_startup_maintenance_step(&conn)?;
            get_or_create_sync_device_id(&conn)?;
            startup::run_preferences_integrity_step(&conn);
            startup::run_trash_purge_step(&conn);
            startup::run_idempotency_sweep_step(&conn);
            startup::run_retention_sweep_step(&conn);
        }

        Ok(Self {
            pool: Arc::new(pool),
            tool_router: Self::import_export_tool_router()
                + Self::preferences_tool_router()
                + Self::calendar_tool_router()
                + Self::list_tool_router()
                + Self::task_tool_router()
                + Self::query_tool_router()
                + Self::workflow_tool_router(),
            tool_timeout,
            in_flight: InFlightTracker::default(),
        })
    }

    pub(crate) fn in_flight_tracker(&self) -> InFlightTracker {
        self.in_flight.clone()
    }
}
