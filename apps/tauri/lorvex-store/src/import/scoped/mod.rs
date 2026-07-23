//! Preflight validation for scoped imports.
//!
//! When a manifest declares `scope_kind = Scoped`, we run a preflight pass over
//! the archive contents to verify scope purity (no records outside declared
//! categories), inventory provenance (no records beyond what the manifest
//! declared), and dependency closure (no dangling refs in edges/children).
//!
//! Findings are emitted to the caller as
//! [`crate::export_scope::ImportValidationFinding`] entries; the calling code
//! decides whether to bail or proceed based on severity.
//!
//! ## Single-pass parsing
//!
//! Each JSONL stream is parsed exactly once at the top of
//! [`preflight_validate_scoped_import`] and the resulting typed `Vec`s are
//! threaded through every downstream validator. Re-parsing raw `&str`
//! contents in each consumer was the previous design and turned a 100k-row
//! archive into ~400k JSON deserializations.

use std::collections::BTreeSet;

use crate::export::parse_json_records;
use crate::export::parse_json_values;
use crate::export_scope::{ExportScopeKind, ImportValidationFinding, ImportValidationSeverity};

use super::archive::ManifestRead;
use super::ImportError;

mod dependencies;
mod index;
mod inventory;
mod parse;
mod purity;

use dependencies::{
    validate_scoped_child_dependencies, validate_scoped_edge_dependencies,
    validate_scoped_entity_dependencies,
};
use index::build_scoped_archive_index;
use inventory::validate_scoped_inventory_provenance;
use parse::parse_scoped_versioned_stream;
use purity::validate_scoped_scope_purity;

pub(super) struct ScopedImportArchiveContents<'a> {
    pub entities_jsonl: &'a str,
    pub edges_jsonl: &'a str,
    pub children_jsonl: &'a str,
    pub audit_jsonl: &'a str,
    pub tombstones_jsonl: &'a str,
    pub shadows_jsonl: &'a str,
    pub provider_links_jsonl: &'a str,
}

struct ParsedScopedImportArchive {
    entities: Vec<crate::export::VersionedExportRecord>,
    edges: Vec<crate::export::VersionedExportRecord>,
    children: Vec<crate::export::VersionedExportRecord>,
    audit: Vec<crate::export::JsonExportRecord>,
    tombstones: Vec<serde_json::Value>,
    shadows: Vec<serde_json::Value>,
    provider_links: Vec<crate::export::JsonExportRecord>,
}

impl ParsedScopedImportArchive {
    fn parse(contents: ScopedImportArchiveContents<'_>) -> Result<Self, ImportError> {
        // ── Single-pass JSONL materialization ──
        // Each stream is parsed exactly once here; every downstream validator
        // borrows the resulting typed slices. Audit/tombstone/shadow streams
        // are also parsed once via the same helpers used by
        // `build_archive_export_dataset`.
        let entities =
            parse_scoped_versioned_stream(contents.entities_jsonl, "entities.jsonl", true)?;
        let edges = parse_scoped_versioned_stream(contents.edges_jsonl, "edges.jsonl", false)?;
        let children =
            parse_scoped_versioned_stream(contents.children_jsonl, "children.jsonl", true)?;
        let audit = parse_json_records(contents.audit_jsonl.as_bytes()).map_err(|error| {
            ImportError::InvalidPayload(format!("invalid audit.jsonl: {error}"))
        })?;
        let tombstones =
            parse_json_values(contents.tombstones_jsonl.as_bytes()).map_err(|error| {
                ImportError::InvalidPayload(format!("invalid tombstones.jsonl: {error}"))
            })?;
        let shadows = parse_json_values(contents.shadows_jsonl.as_bytes()).map_err(|error| {
            ImportError::InvalidPayload(format!("invalid payload_shadows.jsonl: {error}"))
        })?;
        let provider_links =
            parse_json_records(contents.provider_links_jsonl.as_bytes()).map_err(|error| {
                ImportError::InvalidPayload(format!("invalid provider_links.jsonl: {error}"))
            })?;

        Ok(Self {
            entities,
            edges,
            children,
            audit,
            tombstones,
            shadows,
            provider_links,
        })
    }
}

pub(super) fn preflight_validate_scoped_import(
    manifest: &ManifestRead,
    contents: ScopedImportArchiveContents<'_>,
) -> Result<Vec<ImportValidationFinding>, ImportError> {
    if manifest.scope_kind != ExportScopeKind::Scoped {
        return Ok(Vec::new());
    }

    let mut findings = Vec::new();
    if manifest.scope_categories.is_empty() {
        findings.push(ImportValidationFinding {
            severity: ImportValidationSeverity::Error,
            code: "empty_scoped_categories".to_string(),
            message: "scoped archive must declare at least one scope category".to_string(),
        });
        return Ok(findings);
    }

    let archive = ParsedScopedImportArchive::parse(contents)?;

    let index = build_scoped_archive_index(&archive.entities)?;
    validate_scoped_scope_purity(manifest, &archive, &mut findings)?;
    validate_scoped_entity_dependencies(&index, &archive.entities, &mut findings)?;
    validate_scoped_edge_dependencies(&index, &archive.edges, &mut findings)?;
    validate_scoped_child_dependencies(&index, &archive.children, &mut findings)?;
    validate_scoped_inventory_provenance(
        manifest,
        &archive.entities,
        &archive.children,
        &mut findings,
    );

    let mut seen = BTreeSet::new();
    findings.retain(|finding| {
        seen.insert((
            finding.severity as u8,
            finding.code.clone(),
            finding.message.clone(),
        ))
    });
    Ok(findings)
}
