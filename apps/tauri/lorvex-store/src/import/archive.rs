//! Archive-reading primitives for the import pipeline.
//!
//! Reads `manifest.json`, verifies per-file SHA-256 digests (audit
//! #2488), and enforces zip-bomb caps.

use crate::export::ScopedExportInventory;
use crate::export_scope::{ExportCategory, ExportDependencyMode, ExportScopeKind};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;

use super::ImportError;

/// SHA-256 hex digest of `data` — used to verify archive-file digests
/// against the values recorded in `manifest.json`.
fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// Maximum uncompressed size of a single archive file (100 MB).
/// Prevents memory exhaustion from crafted ZIP archives with disproportionately
/// large entries (zip bomb).
pub(super) const MAX_ARCHIVE_FILE_BYTES: u64 = 100 * 1024 * 1024;

pub(in crate::import) const REQUIRED_JSONL_FILES: [&str; 7] = [
    "entities.jsonl",
    "edges.jsonl",
    "children.jsonl",
    "audit.jsonl",
    "payload_shadows.jsonl",
    "tombstones.jsonl",
    "provider_links.jsonl",
];

/// Manifest for deserialization (more relaxed than ExportManifest — allows unknown fields).
#[derive(Deserialize)]
pub(super) struct ManifestRead {
    pub(super) format_version: u32,
    pub(super) schema_version: u32,
    pub(super) payload_schema_version: u32,
    /// Provenance: the device that produced the export and the wall-clock
    /// time of export. Surfaced through [`super::ImportSummary`] so the
    /// dry-run preview can show the user where the archive came from
    /// before they confirm the commit (#2368).
    pub(super) device_id: String,
    pub(super) created_at: String,
    pub(super) scope_kind: ExportScopeKind,
    #[serde(default)]
    pub(super) scope_categories: Vec<ExportCategory>,
    pub(super) dependency_mode: ExportDependencyMode,
    /// Scoped archives include an inventory of exactly which entity IDs were
    /// exported. Import uses this for provenance validation — detecting
    /// same-category overinclusion (extra records injected into the archive).
    #[serde(default)]
    pub(super) scoped_inventory: Option<ScopedExportInventory>,
    /// Per-JSONL-file SHA-256 digests written by the exporter.
    /// Current-format archives must include exactly the required JSONL
    /// section set; import rejects missing or extra entries before any
    /// rows are interpreted.
    pub(super) file_digests: BTreeMap<String, crate::export::FileDigest>,
}

pub(super) fn read_manifest<R: Read + std::io::Seek>(
    archive: &mut zip::ZipArchive<R>,
) -> Result<ManifestRead, ImportError> {
    let mut file = archive
        .by_name("manifest.json")
        .map_err(|_| ImportError::MissingFile("manifest.json".to_string()))?;

    // Zip-bomb guard: reject manifests larger than the per-file cap
    // BEFORE decompressing them. Without this, a crafted archive with a
    // 10 GB uncompressed manifest.json would allocate the full buffer
    // before the rest of import_from_zip got a chance to reject it.
    let uncompressed = file.size();
    if uncompressed > MAX_ARCHIVE_FILE_BYTES {
        return Err(ImportError::InvalidPayload(format!(
            "manifest.json exceeds maximum size ({uncompressed} bytes > {MAX_ARCHIVE_FILE_BYTES} bytes)"
        )));
    }

    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    let manifest: ManifestRead = serde_json::from_str(&contents)?;
    Ok(manifest)
}

pub(super) fn validate_manifest_file_digests(manifest: &ManifestRead) -> Result<(), ImportError> {
    let required: BTreeSet<&str> = REQUIRED_JSONL_FILES.iter().copied().collect();
    let actual: BTreeSet<&str> = manifest
        .file_digests
        .keys()
        .map(std::string::String::as_str)
        .collect();
    let missing: Vec<&str> = required.difference(&actual).copied().collect();
    let extra: Vec<&str> = actual.difference(&required).copied().collect();
    if missing.is_empty() && extra.is_empty() {
        return Ok(());
    }

    let mut details = Vec::new();
    if !missing.is_empty() {
        details.push(format!("missing: {}", missing.join(", ")));
    }
    if !extra.is_empty() {
        details.push(format!("extra: {}", extra.join(", ")));
    }
    Err(ImportError::InvalidPayload(format!(
        "manifest file_digests must list exactly the required JSONL files; {}",
        details.join("; ")
    )))
}

pub(super) fn read_archive_file<R: Read + std::io::Seek>(
    archive: &mut zip::ZipArchive<R>,
    name: &str,
) -> Result<String, ImportError> {
    match archive.by_name(name) {
        Ok(mut file) => {
            let uncompressed = file.size();
            if uncompressed > MAX_ARCHIVE_FILE_BYTES {
                return Err(ImportError::InvalidPayload(format!(
                    "Archive file '{name}' exceeds maximum size ({uncompressed} bytes > {MAX_ARCHIVE_FILE_BYTES} bytes)"
                )));
            }
            let mut contents = String::new();
            file.read_to_string(&mut contents)?;
            Ok(contents)
        }
        Err(zip::result::ZipError::FileNotFound) => Err(ImportError::MissingFile(name.to_string())),
        Err(error) => Err(ImportError::Zip(error)),
    }
}

/// verify a freshly-read archive file's SHA-256 matches
/// the digest recorded in `manifest.json`. Missing entry = corrupt or
/// malformed current-format archive; mismatch = corrupt or tampered archive.
pub(super) fn verify_archive_file_digest(
    manifest: &ManifestRead,
    name: &str,
    contents: &str,
) -> Result<(), ImportError> {
    let Some(expected) = manifest.file_digests.get(name) else {
        return Err(ImportError::InvalidPayload(format!(
            "manifest file_digests is missing required entry for '{name}'"
        )));
    };
    let bytes = contents.as_bytes();
    let actual_bytes = bytes.len() as u64;
    if actual_bytes != expected.bytes {
        return Err(ImportError::InvalidPayload(format!(
            "archive file '{name}' size mismatch: manifest says {expected_bytes} bytes, got {actual_bytes}",
            expected_bytes = expected.bytes,
        )));
    }
    let actual_hash = sha256_hex(bytes);
    if actual_hash != expected.sha256 {
        return Err(ImportError::InvalidPayload(format!(
            "archive file '{name}' digest mismatch: manifest SHA-256 {expected}, computed {actual_hash}",
            expected = expected.sha256,
        )));
    }
    Ok(())
}

#[cfg(test)]
pub(super) fn handle_optional_archive_lookup_error(
    error: zip::result::ZipError,
) -> Result<String, ImportError> {
    match error {
        // Missing file is acceptable for optional sections (e.g., empty exports).
        zip::result::ZipError::FileNotFound => Ok(String::new()),
        other => Err(ImportError::Zip(other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest_with_digest_names(names: &[&str]) -> ManifestRead {
        let file_digests = names
            .iter()
            .map(|&name| {
                (
                    name.to_string(),
                    crate::export::FileDigest {
                        sha256: "0".repeat(64),
                        bytes: 0,
                    },
                )
            })
            .collect();

        ManifestRead {
            format_version: lorvex_domain::version::EXPORT_FORMAT_VERSION,
            schema_version: lorvex_domain::version::SCHEMA_VERSION,
            payload_schema_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            device_id: "test-device".to_string(),
            created_at: "2026-03-29T00:00:00Z".to_string(),
            scope_kind: ExportScopeKind::Full,
            scope_categories: Vec::new(),
            dependency_mode: ExportDependencyMode::Closure,
            scoped_inventory: None,
            file_digests,
        }
    }

    #[test]
    fn validate_manifest_file_digests_rejects_missing_required_section() {
        let names: Vec<&str> = REQUIRED_JSONL_FILES
            .iter()
            .copied()
            .filter(|name| *name != "edges.jsonl")
            .collect();
        let err = validate_manifest_file_digests(&manifest_with_digest_names(&names))
            .expect_err("missing required digest should be rejected");
        let msg = err.to_string();
        assert!(
            msg.contains("file_digests") && msg.contains("missing: edges.jsonl"),
            "unexpected error: {msg}"
        );
    }

    #[test]
    fn validate_manifest_file_digests_rejects_extra_section() {
        let mut names = REQUIRED_JSONL_FILES.to_vec();
        names.push("future.jsonl");
        let err = validate_manifest_file_digests(&manifest_with_digest_names(&names))
            .expect_err("extra digest should be rejected");
        let msg = err.to_string();
        assert!(
            msg.contains("file_digests") && msg.contains("extra: future.jsonl"),
            "unexpected error: {msg}"
        );
    }
}
