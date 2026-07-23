//! DB-path locator: discovers where the SQLite DB lives on the current
//! platform, with explicit precedence rules and structured diagnostics
//! for any rejected/ignored override.
//!
//! Originally a single 670-line `db_locator.rs`; split per-concern so
//! each file holds one cohesive surface. The public API is preserved
//! verbatim through the re-exports below — every external
//! `use lorvex_runtime::resolve_db_path` and friends continues to
//! resolve via the crate-root re-exports in `lib.rs` (which import
//! from `crate::db_locator::...`).

mod diagnostics_queue;
mod env;
mod platform_windows;
mod resolve;
mod types;

#[cfg(test)]
mod tests;

pub use resolve::{resolve_db_location_details, resolve_db_path, take_db_location_diagnostics};
pub use types::{DbLocationDetails, DbLocationDiagnostic, DbLocationDiagnosticCode, DbPathSource};

// Naming constants shared across the platform-specific resolvers.
const LORVEX_DIR: &str = "Lorvex";
const DB_FILE: &str = "db.sqlite";
