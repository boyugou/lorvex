use std::collections::BTreeMap;
use std::io::Write;

use crate::cancellation::check_export_cancelled;
use crate::error::StoreError;
use crate::CancellationToken;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
};

use super::{ExportError, JsonExportRecord, VersionedExportRecord};

pub(super) fn serialize_versioned_records(
    records: &[VersionedExportRecord],
    include_entity_id: bool,
    counts: &mut BTreeMap<String, u64>,
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    for record in records {
        check_export_cancelled(cancellation)?;
        let mut line = serde_json::Map::new();
        line.insert(
            "entity_type".to_string(),
            serde_json::Value::String(record.entity_type.as_str().to_string()),
        );
        if include_entity_id {
            line.insert(
                "entity_id".to_string(),
                serde_json::Value::String(record.entity_id.clone().ok_or_else(|| {
                    ExportError::Store(StoreError::Serialization(format!(
                        "record `{}` is missing entity_id",
                        record.entity_type
                    )))
                })?),
            );
        }
        line.insert(
            "version".to_string(),
            serde_json::Value::String(record.version.clone()),
        );
        line.insert("payload".to_string(), record.payload.clone());
        serde_json::to_writer(&mut *buf, &line)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
        *counts
            .entry(record.entity_type.as_str().to_string())
            .or_insert(0) += 1;
    }
    Ok(())
}

pub(super) fn serialize_json_records(
    records: &[JsonExportRecord],
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    for record in records {
        check_export_cancelled(cancellation)?;
        serde_json::to_writer(&mut *buf, record)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
    }
    Ok(())
}

pub(super) fn serialize_json_values(
    values: &[serde_json::Value],
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    for value in values {
        check_export_cancelled(cancellation)?;
        serde_json::to_writer(&mut *buf, value)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
    }
    Ok(())
}

/// Write a single JSONL line: `{"entity_type":"...","entity_id":"...","version":"...","payload":{...}}`
pub(super) fn write_jsonl_entity_line(
    buf: &mut dyn Write,
    entity_type: &str,
    entity_id: &str,
    version: &str,
    payload: &serde_json::Value,
) -> Result<(), ExportError> {
    let line = serde_json::json!({
        "entity_type": entity_type,
        "entity_id": entity_id,
        "version": version,
        "payload": payload,
    });
    serde_json::to_writer(&mut *buf, &line)?;
    buf.write_all(b"\n").map_err(ExportError::Io)?;
    Ok(())
}

/// Write a single JSONL line for an edge (no single entity_id — uses composite key in payload).
pub(super) fn write_jsonl_edge_line(
    buf: &mut dyn Write,
    edge_type: &str,
    version: &str,
    payload: &serde_json::Value,
) -> Result<(), ExportError> {
    let line = serde_json::json!({
        "entity_type": edge_type,
        "version": version,
        "payload": payload,
    });
    serde_json::to_writer(&mut *buf, &line)?;
    buf.write_all(b"\n").map_err(ExportError::Io)?;
    Ok(())
}

pub(super) fn required_edge_component<'a>(
    payload: &'a serde_json::Map<String, serde_json::Value>,
    key: &str,
    edge_type: &str,
) -> Result<&'a str, ExportError> {
    payload
        .get(key)
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| {
            StoreError::Serialization(format!(
                "{edge_type} export payload missing required string field `{key}`"
            ))
            .into()
        })
}

pub(super) fn edge_entity_id(
    edge_type: &str,
    payload: &serde_json::Map<String, serde_json::Value>,
) -> Result<String, ExportError> {
    match edge_type {
        EDGE_TASK_TAG => Ok(format!(
            "{}:{}",
            required_edge_component(payload, "task_id", edge_type)?,
            required_edge_component(payload, "tag_id", edge_type)?,
        )),
        EDGE_TASK_DEPENDENCY => Ok(format!(
            "{}:{}",
            required_edge_component(payload, "task_id", edge_type)?,
            required_edge_component(payload, "depends_on_task_id", edge_type)?,
        )),
        EDGE_TASK_CALENDAR_EVENT_LINK => Ok(format!(
            "{}:{}",
            required_edge_component(payload, "task_id", edge_type)?,
            required_edge_component(payload, "calendar_event_id", edge_type)?,
        )),
        EDGE_HABIT_COMPLETION => Ok(format!(
            "{}:{}",
            required_edge_component(payload, "habit_id", edge_type)?,
            required_edge_component(payload, "completed_date", edge_type)?,
        )),
        _ => Ok(String::new()),
    }
}
