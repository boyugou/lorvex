//! Top-level scope-filter pipeline:
//! seed selected sets per category → expand closure of cross-references →
//! filter shadows/tombstones/provider-links against the closure.

use super::super::super::ExportError;
use super::super::{ExportDataset, JsonExportRecord, ScopedExportDataset};
use super::match_helpers::{
    build_selected_record_keys, shadow_matches_selected, tombstone_matches_selected_type,
};
use super::refs::referenced_entities;
use super::seed::{
    build_record_lookup, seed_scope_category, should_attach_record, tombstone_types_for_category,
    versioned_record_key,
};
use crate::export_scope::ExportScope;
use lorvex_domain::naming::ENTITY_TASK;
use std::collections::HashSet;

pub(crate) fn scope_export_dataset(
    dataset: &ExportDataset,
    scope: &ExportScope,
) -> Result<ScopedExportDataset, ExportError> {
    if scope.is_full() {
        return Ok(ScopedExportDataset {
            entities: dataset.entities.clone(),
            edges: dataset.edges.clone(),
            children: dataset.children.clone(),
            audit: dataset.audit.clone(),
            tombstones: dataset.tombstones.clone(),
            shadows: dataset.shadows.clone(),
            provider_links: dataset.provider_links.clone(),
        });
    }

    let mut selected_entities: HashSet<(String, String)> = HashSet::new();
    let mut selected_edges: HashSet<(String, String)> = HashSet::new();
    let mut selected_children: HashSet<(String, String)> = HashSet::new();
    let mut selected_tombstone_types: HashSet<String> = HashSet::new();
    let mut include_audit = false;

    for category in &scope.categories {
        selected_tombstone_types.extend(
            tombstone_types_for_category(*category)
                .iter()
                .map(|entity_type| (*entity_type).to_string()),
        );
        seed_scope_category(
            dataset,
            *category,
            &mut selected_entities,
            &mut selected_edges,
            &mut selected_children,
            &mut include_audit,
        )?;
    }

    let entity_lookup = build_record_lookup(&dataset.entities)?;

    let mut changed = true;
    while changed {
        changed = false;

        for record in &dataset.entities {
            let key = versioned_record_key(record)?;
            if selected_entities.contains(&key) {
                for (entity_type, entity_id) in referenced_entities(record)? {
                    if entity_lookup.contains_key(&(entity_type.clone(), entity_id.clone()))
                        && selected_entities.insert((entity_type, entity_id))
                    {
                        changed = true;
                    }
                }
            }
        }

        for record in &dataset.edges {
            let key = versioned_record_key(record)?;
            if selected_edges.contains(&key) {
                for (entity_type, entity_id) in referenced_entities(record)? {
                    if entity_lookup.contains_key(&(entity_type.clone(), entity_id.clone()))
                        && selected_entities.insert((entity_type, entity_id))
                    {
                        changed = true;
                    }
                }
            } else if should_attach_record(record, &selected_entities)?
                && selected_edges.insert(key)
            {
                changed = true;
            }
        }

        for record in &dataset.children {
            let key = versioned_record_key(record)?;
            if selected_children.contains(&key) {
                for (entity_type, entity_id) in referenced_entities(record)? {
                    if entity_lookup.contains_key(&(entity_type.clone(), entity_id.clone()))
                        && selected_entities.insert((entity_type, entity_id))
                    {
                        changed = true;
                    }
                }
            } else if should_attach_record(record, &selected_entities)?
                && selected_children.insert(key)
            {
                changed = true;
            }
        }
    }

    // `versioned_record_key` returns `Err` on a record
    // with a null `entity_id` (partially-hydrated row, malformed
    // import-then-export round-trip, stale tombstone). The previous
    // `.filter(... .unwrap())` closure crashed the export process on
    // that error. Propagate instead — the outer function already
    // returns `Result<_, ExportError>`.
    let entities = dataset
        .entities
        .iter()
        .filter_map(|record| match versioned_record_key(record) {
            Ok(key) if selected_entities.contains(&key) => Some(Ok(record.clone())),
            Ok(_) => None,
            Err(e) => Some(Err(e)),
        })
        .collect::<Result<Vec<_>, _>>()?;
    let edges = dataset
        .edges
        .iter()
        .filter_map(|record| match versioned_record_key(record) {
            Ok(key) if selected_edges.contains(&key) => Some(Ok(record.clone())),
            Ok(_) => None,
            Err(e) => Some(Err(e)),
        })
        .collect::<Result<Vec<_>, _>>()?;
    let children = dataset
        .children
        .iter()
        .filter_map(|record| match versioned_record_key(record) {
            Ok(key) if selected_children.contains(&key) => Some(Ok(record.clone())),
            Ok(_) => None,
            Err(e) => Some(Err(e)),
        })
        .collect::<Result<Vec<_>, _>>()?;

    let selected_record_keys = build_selected_record_keys(
        selected_entities
            .iter()
            .chain(selected_edges.iter())
            .chain(selected_children.iter())
            .cloned(),
    );

    let selected_entity_types = selected_record_keys.keys().cloned().collect::<HashSet<_>>();
    selected_tombstone_types.extend(selected_entity_types);

    let shadows = dataset
        .shadows
        .iter()
        .filter(|value| shadow_matches_selected(value, &selected_record_keys))
        .cloned()
        .collect::<Vec<_>>();
    let tombstones = dataset
        .tombstones
        .iter()
        .filter(|value| tombstone_matches_selected_type(value, &selected_tombstone_types))
        .cloned()
        .collect::<Vec<_>>();
    let audit = if include_audit {
        dataset.audit.clone()
    } else {
        Vec::new()
    };

    // Filter provider links to only include links for selected tasks.
    let selected_task_ids: HashSet<&str> = selected_entities
        .iter()
        .filter(|(et, _)| et == ENTITY_TASK)
        .map(|(_, id)| id.as_str())
        .collect();
    let provider_links: Vec<JsonExportRecord> = dataset
        .provider_links
        .iter()
        .filter(|record| {
            record
                .payload
                .get("task_id")
                .and_then(|v| v.as_str())
                .is_some_and(|tid| selected_task_ids.contains(tid))
        })
        .cloned()
        .collect();

    Ok(ScopedExportDataset {
        entities,
        edges,
        children,
        audit,
        tombstones,
        shadows,
        provider_links,
    })
}
