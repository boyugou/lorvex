//! JSONL parsers for export records.
//!
//! These functions deserialize the line-delimited JSON buffers produced by
//! the row writers into the in-memory record types. They are also consumed
//! by `import/scoped.rs` to round-trip an archive back into an
//! [`ExportDataset`](super::ExportDataset) for verification.

use super::super::{edge_entity_id, ExportError};
use super::{JsonExportRecord, VersionedExportRecord};
use crate::error::StoreError;

pub(crate) fn parse_versioned_records(
    content: &[u8],
    has_entity_id: bool,
) -> Result<Vec<VersionedExportRecord>, ExportError> {
    let text = std::str::from_utf8(content)
        .map_err(|error| ExportError::Store(StoreError::Serialization(error.to_string())))?;
    let mut records = Vec::new();
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let mut record: VersionedExportRecord = serde_json::from_str(line)?;
        if has_entity_id {
            crate::jsonl_identity::validate_versioned_jsonl_identity(
                "versioned JSONL",
                record.entity_type,
                record.entity_id.as_deref(),
                &record.payload,
            )
            .map_err(|message| ExportError::Store(StoreError::Serialization(message)))?;
        }
        if !has_entity_id {
            let payload = record.payload.as_object().ok_or_else(|| {
                ExportError::Store(StoreError::Serialization(format!(
                    "edge payload for `{}` must be an object",
                    record.entity_type
                )))
            })?;
            record.entity_id = Some(edge_entity_id(record.entity_type.as_str(), payload)?);
        }
        records.push(record);
    }
    Ok(records)
}

pub(crate) fn parse_json_records(content: &[u8]) -> Result<Vec<JsonExportRecord>, ExportError> {
    let text = std::str::from_utf8(content)
        .map_err(|error| ExportError::Store(StoreError::Serialization(error.to_string())))?;
    text.lines()
        .filter(|line| !line.trim().is_empty())
        .map(serde_json::from_str)
        .collect::<Result<Vec<_>, _>>()
        .map_err(ExportError::from)
}

pub(crate) fn parse_json_values(content: &[u8]) -> Result<Vec<serde_json::Value>, ExportError> {
    let text = std::str::from_utf8(content)
        .map_err(|error| ExportError::Store(StoreError::Serialization(error.to_string())))?;
    text.lines()
        .filter(|line| !line.trim().is_empty())
        .map(serde_json::from_str)
        .collect::<Result<Vec<_>, _>>()
        .map_err(ExportError::from)
}
