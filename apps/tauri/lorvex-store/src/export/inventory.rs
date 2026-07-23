use std::collections::{BTreeMap, BTreeSet};

use super::{
    versioned_record_key, ExportError, JsonExportRecord, ScopedExportDataset, ScopedExportInventory,
};

pub(super) fn build_scoped_inventory(
    dataset: &ScopedExportDataset,
) -> Result<ScopedExportInventory, ExportError> {
    let mut versioned_record_ids_by_type: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for record in dataset
        .entities
        .iter()
        .chain(dataset.edges.iter())
        .chain(dataset.children.iter())
    {
        let (entity_type, entity_id) = versioned_record_key(record)?;
        versioned_record_ids_by_type
            .entry(entity_type)
            .or_default()
            .insert(entity_id);
    }

    Ok(ScopedExportInventory {
        versioned_record_ids_by_type: versioned_record_ids_by_type
            .into_iter()
            .map(|(entity_type, ids)| (entity_type, ids.into_iter().collect()))
            .collect(),
        audit_record_keys: dataset
            .audit
            .iter()
            .map(export_json_record_key)
            .collect::<Result<Vec<_>, _>>()?,
        tombstone_keys: dataset
            .tombstones
            .iter()
            .map(export_json_value_key)
            .collect::<Result<Vec<_>, _>>()?,
        payload_shadow_keys: dataset
            .shadows
            .iter()
            .map(export_json_value_key)
            .collect::<Result<Vec<_>, _>>()?,
    })
}

pub(super) fn export_json_record_key(record: &JsonExportRecord) -> Result<String, ExportError> {
    Ok(format!(
        "{}:{}:{}",
        record.entity_type,
        record.entity_id.as_deref().unwrap_or_default(),
        serde_json::to_string(&record.payload)?,
    ))
}

pub(super) fn export_json_value_key(value: &serde_json::Value) -> Result<String, ExportError> {
    Ok(serde_json::to_string(value)?)
}
