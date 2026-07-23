//! Per-category seeders + the shared record-key / lookup / attachment
//! helpers used by the closure-expansion loop in [`super::orchestrator`].

use super::super::super::ExportError;
use super::super::{ExportDataset, VersionedExportRecord};
use super::refs::referenced_entities;
use crate::error::StoreError;
use crate::export_scope::ExportCategory;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
    ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW,
    ENTITY_FOCUS_SCHEDULE, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER,
};
use std::collections::{HashMap, HashSet};

pub(crate) fn versioned_record_key(
    record: &VersionedExportRecord,
) -> Result<(String, String), ExportError> {
    let entity_id = record.entity_id.clone().ok_or_else(|| {
        ExportError::Store(StoreError::Serialization(format!(
            "export record `{}` is missing entity_id",
            record.entity_type
        )))
    })?;
    Ok((record.entity_type.as_str().to_string(), entity_id))
}

pub(super) fn build_record_lookup(
    records: &[VersionedExportRecord],
) -> Result<HashMap<(String, String), usize>, ExportError> {
    let mut lookup = HashMap::new();
    for (index, record) in records.iter().enumerate() {
        lookup.insert(versioned_record_key(record)?, index);
    }
    Ok(lookup)
}

pub(super) fn seed_scope_category(
    dataset: &ExportDataset,
    category: ExportCategory,
    selected_entities: &mut HashSet<(String, String)>,
    selected_edges: &mut HashSet<(String, String)>,
    selected_children: &mut HashSet<(String, String)>,
    include_audit: &mut bool,
) -> Result<(), ExportError> {
    match category {
        ExportCategory::Tasks => {
            seed_entities_of_type(dataset, ENTITY_TASK, selected_entities)?;
            seed_edges_of_type(dataset, EDGE_TASK_TAG, selected_edges)?;
            seed_edges_of_type(dataset, EDGE_TASK_DEPENDENCY, selected_edges)?;
            seed_edges_of_type(dataset, EDGE_TASK_CALENDAR_EVENT_LINK, selected_edges)?;
            seed_children_of_type(dataset, ENTITY_TASK_REMINDER, selected_children)?;
        }
        ExportCategory::Lists => {
            seed_entities_of_type(dataset, ENTITY_LIST, selected_entities)?;
        }
        ExportCategory::Calendar => {
            seed_entities_of_type(dataset, ENTITY_CALENDAR_EVENT, selected_entities)?;
            seed_edges_of_type(dataset, EDGE_TASK_CALENDAR_EVENT_LINK, selected_edges)?;
        }
        ExportCategory::Habits => {
            seed_entities_of_type(dataset, ENTITY_HABIT, selected_entities)?;
            seed_edges_of_type(dataset, EDGE_HABIT_COMPLETION, selected_edges)?;
            seed_children_of_type(dataset, ENTITY_HABIT_REMINDER_POLICY, selected_children)?;
        }
        ExportCategory::DailyReviews => {
            seed_entities_of_type(dataset, ENTITY_DAILY_REVIEW, selected_entities)?;
        }
        ExportCategory::Memory => {
            seed_entities_of_type(dataset, ENTITY_MEMORY, selected_entities)?;
            seed_entities_of_type(dataset, ENTITY_MEMORY_REVISION, selected_entities)?;
        }
        ExportCategory::Preferences => {
            seed_entities_of_type(dataset, ENTITY_PREFERENCE, selected_entities)?;
        }
        ExportCategory::Focus => {
            seed_entities_of_type(dataset, ENTITY_CURRENT_FOCUS, selected_entities)?;
            seed_entities_of_type(dataset, ENTITY_FOCUS_SCHEDULE, selected_entities)?;
        }
        ExportCategory::Subscriptions => {
            seed_entities_of_type(dataset, ENTITY_CALENDAR_SUBSCRIPTION, selected_entities)?;
        }
        ExportCategory::Audit => {
            *include_audit = true;
        }
    }
    Ok(())
}

pub(super) fn tombstone_types_for_category(category: ExportCategory) -> &'static [&'static str] {
    match category {
        ExportCategory::Tasks => &[
            ENTITY_TASK,
            EDGE_TASK_TAG,
            EDGE_TASK_DEPENDENCY,
            EDGE_TASK_CALENDAR_EVENT_LINK,
            ENTITY_TASK_REMINDER,
            ENTITY_TASK_CHECKLIST_ITEM,
        ],
        ExportCategory::Lists => &[ENTITY_LIST],
        ExportCategory::Calendar => &[ENTITY_CALENDAR_EVENT, EDGE_TASK_CALENDAR_EVENT_LINK],
        ExportCategory::Habits => &[
            ENTITY_HABIT,
            EDGE_HABIT_COMPLETION,
            ENTITY_HABIT_REMINDER_POLICY,
        ],
        ExportCategory::DailyReviews => &[ENTITY_DAILY_REVIEW],
        ExportCategory::Memory => &[ENTITY_MEMORY, ENTITY_MEMORY_REVISION],
        ExportCategory::Preferences => &[ENTITY_PREFERENCE],
        ExportCategory::Focus => &[ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE],
        ExportCategory::Subscriptions => &[ENTITY_CALENDAR_SUBSCRIPTION],
        ExportCategory::Audit => &[],
    }
}

fn seed_entities_of_type(
    dataset: &ExportDataset,
    entity_type: &str,
    selected_entities: &mut HashSet<(String, String)>,
) -> Result<(), ExportError> {
    for record in dataset
        .entities
        .iter()
        .filter(|record| record.entity_type.as_str() == entity_type)
    {
        selected_entities.insert(versioned_record_key(record)?);
    }
    Ok(())
}

fn seed_edges_of_type(
    dataset: &ExportDataset,
    entity_type: &str,
    selected_edges: &mut HashSet<(String, String)>,
) -> Result<(), ExportError> {
    for record in dataset
        .edges
        .iter()
        .filter(|record| record.entity_type.as_str() == entity_type)
    {
        selected_edges.insert(versioned_record_key(record)?);
    }
    Ok(())
}

fn seed_children_of_type(
    dataset: &ExportDataset,
    entity_type: &str,
    selected_children: &mut HashSet<(String, String)>,
) -> Result<(), ExportError> {
    for record in dataset
        .children
        .iter()
        .filter(|record| record.entity_type.as_str() == entity_type)
    {
        selected_children.insert(versioned_record_key(record)?);
    }
    Ok(())
}

pub(super) fn should_attach_record(
    record: &VersionedExportRecord,
    selected_entities: &HashSet<(String, String)>,
) -> Result<bool, ExportError> {
    Ok(referenced_entities(record)?
        .into_iter()
        .any(|reference| selected_entities.contains(&reference)))
}
