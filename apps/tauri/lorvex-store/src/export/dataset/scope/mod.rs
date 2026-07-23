//! Filter an [`ExportDataset`] down to a [`ScopedExportDataset`] using an
//! [`ExportScope`].
//!
//! The pipeline seeds a working set of selected entities/edges/children from
//! each requested [`ExportCategory`], iteratively expands the closure of
//! cross-references (so e.g. selecting a task pulls in its list, tags, and
//! dependencies), and then filters the dataset's tombstones, payload
//! shadows, and local-only provider links against that closure.
//!
//! Submodules:
//! - [`orchestrator`] hosts the top-level [`scope_export_dataset`] pipeline.
//! - [`seed`] hosts per-category seeders + the shared
//!   `versioned_record_key` / `build_record_lookup` / `should_attach_record`
//!   helpers used during closure expansion.
//! - [`refs`] hosts the `referenced_entities` cross-reference extractor +
//!   the `push_optional_ref` / `push_array_refs` payload helpers.
//! - [`match_helpers`] hosts the shadow + tombstone post-filter predicates.

mod match_helpers;
mod orchestrator;
mod refs;
mod seed;

pub(crate) use orchestrator::scope_export_dataset;
pub(crate) use seed::versioned_record_key;
