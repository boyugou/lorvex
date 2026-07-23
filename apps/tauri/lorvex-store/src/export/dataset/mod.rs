//! Export dataset model and scope filtering.
//!
//! [`collect::collect_export_dataset`] walks the SQLite store and produces an
//! in-memory [`ExportDataset`]. [`scope::scope_export_dataset`] then filters
//! that dataset against an [`ExportScope`](crate::export_scope::ExportScope)
//! for the scoped-export path. [`parse`] hosts the JSONL parsers shared by
//! the export collector and the scoped-import verifier.

mod collect;
mod parse;
mod scope;

use lorvex_domain::naming::EntityKind;
use serde::{Deserialize, Serialize};

pub(crate) use collect::collect_export_dataset;
pub(crate) use parse::{parse_json_records, parse_json_values, parse_versioned_records};
pub(crate) use scope::{scope_export_dataset, versioned_record_key};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct VersionedExportRecord {
    pub(crate) entity_type: EntityKind,
    #[serde(default)]
    pub(crate) entity_id: Option<String>,
    pub(crate) version: String,
    pub(crate) payload: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct JsonExportRecord {
    pub(crate) entity_type: EntityKind,
    #[serde(default)]
    pub(crate) entity_id: Option<String>,
    pub(crate) payload: serde_json::Value,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ExportDataset {
    pub(crate) entities: Vec<VersionedExportRecord>,
    pub(crate) edges: Vec<VersionedExportRecord>,
    pub(crate) children: Vec<VersionedExportRecord>,
    pub(crate) audit: Vec<JsonExportRecord>,
    pub(crate) tombstones: Vec<serde_json::Value>,
    pub(crate) shadows: Vec<serde_json::Value>,
    /// Local-only task↔provider event link rows (unversioned).
    pub(crate) provider_links: Vec<JsonExportRecord>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ScopedExportDataset {
    pub(crate) entities: Vec<VersionedExportRecord>,
    pub(crate) edges: Vec<VersionedExportRecord>,
    pub(crate) children: Vec<VersionedExportRecord>,
    pub(crate) audit: Vec<JsonExportRecord>,
    pub(crate) tombstones: Vec<serde_json::Value>,
    pub(crate) shadows: Vec<serde_json::Value>,
    /// Local-only task↔provider event link rows (unversioned).
    pub(crate) provider_links: Vec<JsonExportRecord>,
}
