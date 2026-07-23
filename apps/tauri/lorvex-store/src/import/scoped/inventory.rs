use std::collections::{BTreeMap, BTreeSet, HashSet};

use crate::export::{versioned_record_key, JsonExportRecord, VersionedExportRecord};
use crate::export_scope::{ImportValidationFinding, ImportValidationSeverity};

use crate::import::archive::ManifestRead;
use crate::import::ImportError;

/// If the manifest includes a `scoped_inventory`, verify that the archive
/// contents match the declared entity IDs. Extra records not in the inventory
/// are flagged as `inventory_overinclusion` warnings; declared IDs missing
/// from the archive are flagged as `inventory_underinclusion` warnings.
pub(super) fn validate_scoped_inventory_provenance(
    manifest: &ManifestRead,
    entities: &[VersionedExportRecord],
    children: &[VersionedExportRecord],
    findings: &mut Vec<ImportValidationFinding>,
) {
    let Some(inventory) = manifest.scoped_inventory.as_ref() else {
        return;
    };

    // Build set of declared entity IDs per type from the inventory. Borrowed
    // `&str` keys throughout — the inventory itself owns the strings.
    let declared: BTreeMap<&str, BTreeSet<&str>> = inventory
        .versioned_record_ids_by_type
        .iter()
        .map(|(entity_type, ids)| {
            (
                entity_type.as_str(),
                ids.iter()
                    .map(std::string::String::as_str)
                    .collect::<BTreeSet<_>>(),
            )
        })
        .collect();

    // Over-inclusion: archive records whose IDs are not in the manifest.
    let over_inclusion = |records: &[VersionedExportRecord], noun: &str, findings: &mut Vec<_>| {
        for record in records {
            let entity_id = record.entity_id.as_deref().unwrap_or("");
            if let Some(declared_ids) = declared.get(record.entity_type.as_str()) {
                if !declared_ids.contains(entity_id) {
                    findings.push(ImportValidationFinding {
                            severity: ImportValidationSeverity::Warning,
                            code: "inventory_overinclusion".to_string(),
                            message: format!(
                                "{noun} {}/{entity_id} is in the archive but not in the manifest inventory",
                                record.entity_type
                            ),
                        });
                }
            }
        }
    };
    over_inclusion(entities, "entity", findings);
    over_inclusion(children, "child", findings);

    // Under-inclusion: declared IDs that don't appear anywhere in the
    // archive. Borrowed `&str` keys; the underlying strings live in the
    // pre-parsed `Vec<VersionedExportRecord>`.
    let mut archive_ids_by_type: BTreeMap<&str, HashSet<&str>> = BTreeMap::new();
    for record in entities.iter().chain(children.iter()) {
        let et = record.entity_type.as_str();
        let eid = record.entity_id.as_deref().unwrap_or("");
        if et.is_empty() || eid.is_empty() {
            continue;
        }
        archive_ids_by_type.entry(et).or_default().insert(eid);
    }
    for (entity_type, declared_ids) in &declared {
        let archive_ids = archive_ids_by_type.get(*entity_type);
        for id in declared_ids {
            let present = archive_ids.is_some_and(|set| set.contains(*id));
            if !present {
                findings.push(ImportValidationFinding {
                    severity: ImportValidationSeverity::Warning,
                    code: "inventory_underinclusion".to_string(),
                    message: format!(
                        "{entity_type}/{id} is in the manifest inventory but missing from the archive"
                    ),
                });
            }
        }
    }
}

pub(super) fn push_unexpected<T, F: Fn(&T) -> String>(
    items: impl IntoIterator<Item = T>,
    summarize: F,
    into: &mut Vec<ImportValidationFinding>,
) {
    for item in items {
        into.push(ImportValidationFinding {
            severity: ImportValidationSeverity::Error,
            code: "scope_purity_violation".to_string(),
            message: summarize(&item),
        });
    }
}

/// Compare two `[serde_json::Value]` slices keyed via [`json_value_key`]
/// and report any value present in `actual` but not in `expected` as a
/// scope-purity violation. Used by the tombstone + payload-shadow
/// branches of `validate_scoped_scope_purity`, which differ only in
/// the noun used in the diagnostic ("tombstone" vs "payload shadow").
pub(super) fn push_unexpected_keyed(
    actual: &[serde_json::Value],
    expected: &[serde_json::Value],
    noun: &str,
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    let expected_keys = expected
        .iter()
        .map(json_value_key)
        .collect::<Result<HashSet<_>, _>>()?;
    let mut unexpected = Vec::new();
    for value in actual {
        let key = json_value_key(value)?;
        if !expected_keys.contains(&key) {
            unexpected.push(key);
        }
    }
    push_unexpected(
        unexpected,
        |key| {
            format!(
                "scoped archive includes unexpected {noun} outside the manifest-declared closure: {key}"
            )
        },
        findings,
    );
    Ok(())
}

pub(super) fn push_unexpected_versioned(
    label: &str,
    actual: &[crate::export::VersionedExportRecord],
    expected: &[crate::export::VersionedExportRecord],
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    let expected_keys = expected
        .iter()
        .map(versioned_record_key)
        .collect::<Result<HashSet<_>, _>>()
        .map_err(|error| ImportError::InvalidPayload(format!("invalid scoped archive: {error}")))?;
    let mut unexpected = Vec::new();
    for record in actual {
        let key = versioned_record_key(record).map_err(|error| {
            ImportError::InvalidPayload(format!("invalid scoped archive: {error}"))
        })?;
        if !expected_keys.contains(&key) {
            unexpected.push(key);
        }
    }
    push_unexpected(
        unexpected,
        |key| {
            format!(
                "scoped archive includes unexpected {label} `{}` with id `{}` outside the manifest-declared closure",
                key.0, key.1
            )
        },
        findings,
    );
    Ok(())
}

pub(super) fn json_record_key(record: &JsonExportRecord) -> Result<String, ImportError> {
    Ok(format!(
        "{}:{}:{}",
        record.entity_type,
        record.entity_id.as_deref().unwrap_or_default(),
        serde_json::to_string(&record.payload)?,
    ))
}

pub(super) fn json_value_key(value: &serde_json::Value) -> Result<String, ImportError> {
    Ok(serde_json::to_string(value)?)
}
