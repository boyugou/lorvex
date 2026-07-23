//! Import data from a ZIP archive.
//!
//! Restores entities, edges, children, audit entries, and tombstones
//! from a ZIP archive produced by [`crate::export::export_to_zip`].
//!
//! Import follows the protocol from spec Section 22:
//!
//! 1. Read `manifest.json`, check `format_version` compatibility.
//! 2. Enter projection maintenance mode.
//! 3. Within a transaction:
//!    a. Apply entities (ON CONFLICT: compare version, keep newer).
//!    b. Apply edges (ON CONFLICT: compare version, keep newer).
//!    c. Apply children.
//!    d. Restore forward-compat payload shadow state.
//!    e. Apply tombstones.
//! 4. Exit projection maintenance mode (rebuild all projections).
//! 5. Return import summary.
//!
//! Intentional public API hub for ZIP import operations. The implementation
//! lives in per-concern siblings:
//!
//! - [`types`]: `ImportSummary` + `ImportOptions` value types.
//! - [`error`]: `ImportError` plus `From`/`Display`/`Error` impls.
//! - [`entry`]: convenience wrappers (`import_from_zip`,
//!   `import_from_zip_with_options`) that open a path and forward to
//!   the TOCTOU-safe core.
//! - [`zip_pipeline`]: the heavy-lifting decode + apply pipeline.

mod apply;
mod archive;
mod entry;
mod error;
mod scoped;
mod types;
mod zip_pipeline;

pub use entry::{
    import_from_zip, import_from_zip_with_options, import_from_zip_with_options_and_cancellation,
};
pub use error::ImportError;
pub use types::{ImportOptions, ImportSummary};
pub use zip_pipeline::{
    import_from_zip_file_with_options, import_from_zip_file_with_options_and_cancellation,
};

// Test-only re-exports — the existing `import/tests/` harness imports
// these via `use super::*;` to drive helpers that aren't part of the
// public API. The re-exports of `Connection`, `Path`, and the
// export-scope types mirror what be plain `use` lines at the top of
// this file before the split; they keep the inner-test `super::*` glob
// resolving without forcing every test file to re-import the same
// primitives.
#[cfg(test)]
pub(in crate::import) use crate::export_scope::ExportCategory;
#[cfg(test)]
pub(in crate::import) use apply::required_bool_as_i64_field;
#[cfg(test)]
pub(in crate::import) use archive::{handle_optional_archive_lookup_error, REQUIRED_JSONL_FILES};
#[cfg(test)]
pub(in crate::import) use rusqlite::Connection;
#[cfg(test)]
pub(in crate::import) use std::path::Path;

#[cfg(test)]
mod tests;
