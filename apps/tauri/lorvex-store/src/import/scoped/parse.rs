use crate::export::{
    parse_versioned_records, ExportDataset, JsonExportRecord, VersionedExportRecord,
};
use lorvex_domain::hlc::Hlc;

use crate::import::ImportError;

/// Parse one of the three versioned JSONL streams (entities, edges, children)
/// once, validating HLC versions in the same walk. Mirrors the per-line HLC
/// check that `parse_versioned_jsonl_line` performs in the apply pass — we
/// hoist it here so preflight rejects malformed versions before any blob copy
/// or transaction begins, without re-parsing the JSON a second time.
pub(super) fn parse_scoped_versioned_stream(
    content: &str,
    stream_name: &str,
    has_entity_id: bool,
) -> Result<Vec<VersionedExportRecord>, ImportError> {
    let records = parse_versioned_records(content.as_bytes(), has_entity_id)
        .map_err(|error| ImportError::InvalidPayload(format!("invalid {stream_name}: {error}")))?;
    for record in &records {
        if record.version.trim().is_empty() {
            return Err(ImportError::InvalidPayload(format!(
                "{stream_name} entry for `{}` must include a non-empty version",
                record.entity_type
            )));
        }
        Hlc::parse(&record.version).map_err(|error| {
            ImportError::InvalidPayload(format!(
                "{stream_name} entry for `{}` must include a valid HLC version: {error}",
                record.entity_type
            ))
        })?;
    }
    Ok(records)
}

/// Assemble an [`ExportDataset`] from already-parsed slices for the scope
/// purity check. The slices are cloned because [`scope_export_dataset`]
/// takes owned `ExportDataset`-shaped input; the cost is bounded by the
/// archive size and replaces what be four redundant JSON
/// deserialization passes over the same bytes.
pub(super) fn build_archive_export_dataset(
    entities: &[VersionedExportRecord],
    edges: &[VersionedExportRecord],
    children: &[VersionedExportRecord],
    audit: &[JsonExportRecord],
    tombstones: &[serde_json::Value],
    shadows: &[serde_json::Value],
    provider_links: &[JsonExportRecord],
) -> ExportDataset {
    ExportDataset {
        entities: entities.to_vec(),
        edges: edges.to_vec(),
        children: children.to_vec(),
        audit: audit.to_vec(),
        tombstones: tombstones.to_vec(),
        shadows: shadows.to_vec(),
        provider_links: provider_links.to_vec(),
    }
}

pub(super) fn summarize_json_record(record: &JsonExportRecord) -> String {
    match record.entity_id.as_deref() {
        Some(entity_id) if !entity_id.is_empty() => format!("{}:{entity_id}", record.entity_type),
        _ => record.entity_type.as_str().to_string(),
    }
}
