use crate::export_scope::{ExportCategory, ExportDependencyMode, ExportScopeKind};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Export manifest — written as `manifest.json` in the ZIP archive.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportManifest {
    pub format_version: u32,
    pub app_version: String,
    pub schema_version: u32,
    pub payload_schema_version: u32,
    pub created_at: String,
    pub device_id: String,
    pub scope_kind: ExportScopeKind,
    pub scope_categories: Vec<ExportCategory>,
    pub dependency_mode: ExportDependencyMode,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scoped_inventory: Option<ScopedExportInventory>,
    pub entity_counts: BTreeMap<String, u64>,
    pub edge_counts: BTreeMap<String, u64>,
    /// Per-JSONL-file SHA-256 digest and uncompressed size.
    /// `verify_file_digests` on read aborts with a clear error if
    /// any digest doesn't match. A bare "manifest.json is present"
    /// check would let a bit-flip during cloud storage transit
    /// silently truncate / corrupt any of the JSONL streams while
    /// the import path happily processed the partial data.
    pub file_digests: BTreeMap<String, FileDigest>,
}

/// SHA-256 digest + uncompressed byte count for a single JSONL file
/// inside an export ZIP.
///
/// The digest is computed inline by `archive::SectionDigestWriter` as
/// the section streams into the ZIP — see #3053 H1+M18; the previous
/// `from_bytes(&[u8])` constructor required materializing the entire
/// section in memory before hashing.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FileDigest {
    pub sha256: String,
    pub bytes: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScopedExportInventory {
    pub versioned_record_ids_by_type: BTreeMap<String, Vec<String>>,
    pub audit_record_keys: Vec<String>,
    pub tombstone_keys: Vec<String>,
    pub payload_shadow_keys: Vec<String>,
}
