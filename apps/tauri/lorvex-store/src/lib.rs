// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-store` — SQLite storage layer for Lorvex.
//!
//! This crate owns:
//! - **Migrations**: versioned, checksummed SQL migrations applied at startup.
//! - **Connection**: open helpers that apply PRAGMAs + migrations.
//! - **Path resolution**: shared logic for finding the database file.
//! - **Transaction helpers**: `IMMEDIATE` transaction wrapper.
//! - **Projections**: maintenance framework for derived data (FTS, caches).
//! - **Export/Import**: ZIP-based full data export and import.

pub(crate) mod busy_retry;
pub mod calendar_timeline;
mod cancellation;
pub mod changelog;
pub mod connection;
pub mod connection_pool;
pub mod device_state;
pub mod error;
pub mod export_scope;
pub(crate) mod fs_durability;
pub(crate) mod jsonl_identity;

pub mod export;
pub mod focus_schedule_blocks;
pub mod focus_schedule_proposal;
pub mod focus_schedule_snapshot;
pub mod import;
pub mod interchange;
pub mod maintenance;
pub mod mcp_idempotency;
pub mod migration;
pub mod payload_loaders;
pub mod projection;
// Issue #3330: was `pub(crate)` until the lifecycle spawn-successor
// path moved to `lorvex-workflow`. The exception-date parser is now
// reached from outside the crate and must be `pub`.
pub mod recurrence_exceptions;
pub mod repositories;
pub mod review_metrics;
pub mod schema;
pub mod status_transition_sql;
pub mod sync_status;
pub mod task_classification;
#[cfg(any(test, feature = "test-support"))]
pub mod test_support;
pub mod transaction;

// ---------------------------------------------------------------------------
// Intentional public API surface for store subdomains used across crates.
//
// These namespaces are part of the store crate's current operator-facing
// boundary: callers depend on the domain name (`error_log`, `payload_shadow`,
// `current_focus_items`) rather than each submodule's internal folder layout.
// Keep this list curated; new exports should represent stable cross-crate
// ownership, not import-path compatibility.
// ---------------------------------------------------------------------------
pub use error::log as error_log;
pub use error::sanitize as error_sanitize;
pub use maintenance::disk_full;
pub use maintenance::hlc_seed;
pub use maintenance::setup_status;
pub use maintenance::startup as startup_maintenance;
pub use repositories::current_focus_items;
pub use repositories::daily_review_ops;

// EXPLAIN QUERY PLAN snapshot harness for hot read paths (#2292) lives
// at `tests/explain_query_plan.rs` so it links as an integration-test
// binary against the public crate surface.

// Re-export the most commonly used items at crate root.
pub use busy_retry::{with_busy_retry, DEFAULT_RETRY_BUDGET};
pub use cancellation::{CancellationToken, NeverCancelled};
pub use connection::{
    apply_standard_pragmas, open_db, open_db_at_path, persist_db_location_diagnostics,
    persist_pending_db_location_diagnostics, run_integrity_check, run_periodic_maintenance,
    OpenError,
};
// the in-memory helper is test-only because its
// cached-schema initializer panics on migration failures. Production
// binaries should not link a function that can panic on a path the
// `OpenError` chain already covers.
#[cfg(any(test, feature = "test-support"))]
pub use connection::open_db_in_memory;
pub use connection_pool::{ConnectionPool, PoolError};
pub use disk_full::{
    clear_tripped_for_tests as clear_disk_full_breaker_for_tests, is_disk_full_error,
    is_tripped as is_disk_full_tripped, probe_and_reset as probe_disk_full, DiskFullError,
};
pub use error::StoreError;
pub use export_scope::{
    ExportCategory, ExportDependencyMode, ExportScope, ExportScopeKind, ImportValidationFinding,
};

pub use export::{
    export_to_zip, export_to_zip_scoped, export_to_zip_scoped_with_cancellation,
    export_to_zip_with_cancellation, ExportError,
};
pub use import::{
    import_from_zip, import_from_zip_file_with_options,
    import_from_zip_file_with_options_and_cancellation, import_from_zip_with_options,
    import_from_zip_with_options_and_cancellation, ImportError, ImportOptions, ImportSummary,
};
pub use migration::{apply_migrations, Migration, MigrationError};
pub use repositories::task::read::{task_exists_active, validate_task_ids_live, TASK_ORDER_BY};
pub use repositories::task::write::INBOX_LIST_ID;
pub use review_metrics::{
    deferred_open_count, load_task_estimate_summary, overdue_open_count, someday_count,
};
pub use setup_status::{load_setup_status, SetupStatus};
pub use startup_maintenance::run_startup_preferences_integrity;
pub use sync_status::{load_sync_status_snapshot, SyncStatusSnapshot};
pub use task_classification::{resolve_required_task_list_id, validate_task_list_exists};
pub use transaction::{
    with_deferred_read_transaction, with_immediate_transaction, with_savepoint,
    with_savepoint_mapped, with_savepoint_then_rollback,
};
