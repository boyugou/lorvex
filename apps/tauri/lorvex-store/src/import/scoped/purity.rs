use std::collections::HashSet;

use crate::export::scope_export_dataset;
use crate::export_scope::{ExportScope, ImportValidationFinding};

use crate::import::archive::ManifestRead;
use crate::import::ImportError;

use super::inventory::{
    json_record_key, push_unexpected, push_unexpected_keyed, push_unexpected_versioned,
};
use super::parse::{build_archive_export_dataset, summarize_json_record};
use super::ParsedScopedImportArchive;

pub(super) fn validate_scoped_scope_purity(
    manifest: &ManifestRead,
    archive: &ParsedScopedImportArchive,
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    let scope = ExportScope {
        kind: manifest.scope_kind,
        categories: manifest.scope_categories.clone(),
        dependency_mode: manifest.dependency_mode,
    };
    let archive_dataset = build_archive_export_dataset(
        &archive.entities,
        &archive.edges,
        &archive.children,
        &archive.audit,
        &archive.tombstones,
        &archive.shadows,
        &archive.provider_links,
    );
    let expected = scope_export_dataset(&archive_dataset, &scope)
        .map_err(|error| ImportError::InvalidPayload(format!("invalid scoped archive: {error}")))?;

    push_unexpected_versioned(
        "entity",
        &archive_dataset.entities,
        &expected.entities,
        findings,
    )?;
    push_unexpected_versioned("edge", &archive_dataset.edges, &expected.edges, findings)?;
    push_unexpected_versioned(
        "child",
        &archive_dataset.children,
        &expected.children,
        findings,
    )?;
    // Audit records are reported with a per-record summary, so we keep
    // the typed Vec<&Value> shape for the formatter.
    {
        let expected_keys = expected
            .audit
            .iter()
            .map(json_record_key)
            .collect::<Result<HashSet<_>, _>>()?;
        let mut unexpected = Vec::new();
        for record in &archive_dataset.audit {
            let key = json_record_key(record)?;
            if !expected_keys.contains(&key) {
                unexpected.push(record);
            }
        }
        push_unexpected(
            unexpected,
            |record| {
                format!(
                "scoped archive includes unexpected audit record `{}` outside the manifest-declared closure",
                summarize_json_record(record)
            )
            },
            findings,
        );
    }
    // Tombstones + shadows are both keyed by the same `json_value_key`
    // helper and only differ in the message phrasing. Single helper
    // closes the previous 40-line copy/paste pair that diverged on
    // every refactor.
    push_unexpected_keyed(
        &archive_dataset.tombstones,
        &expected.tombstones,
        "tombstone",
        findings,
    )?;
    push_unexpected_keyed(
        &archive_dataset.shadows,
        &expected.shadows,
        "payload shadow",
        findings,
    )?;
    {
        let expected_keys = expected
            .provider_links
            .iter()
            .map(json_record_key)
            .collect::<Result<HashSet<_>, _>>()?;
        let mut unexpected = Vec::new();
        for record in &archive_dataset.provider_links {
            let key = json_record_key(record)?;
            if !expected_keys.contains(&key) {
                unexpected.push(record);
            }
        }
        push_unexpected(
            unexpected,
            |record| {
                format!(
                    "scoped archive includes unexpected provider link `{}` outside the manifest-declared closure",
                    summarize_json_record(record)
                )
            },
            findings,
        );
    }
    Ok(())
}
