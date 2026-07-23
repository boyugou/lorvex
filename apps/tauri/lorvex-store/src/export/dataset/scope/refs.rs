//! Cross-reference extraction for closure expansion.
//!
//! [`referenced_entities`] dispatches on `record.entity_type` and pulls every
//! `(entity_type, entity_id)` foreign reference out of the record's payload.
//! [`push_optional_ref`] / [`push_array_refs`] are the small payload-field
//! helpers the dispatcher uses.

use super::super::super::ExportError;
use super::super::VersionedExportRecord;
use crate::error::StoreError;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
    ENTITY_CALENDAR_EVENT, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW, ENTITY_FOCUS_SCHEDULE,
    ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, ENTITY_LIST, ENTITY_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};

pub(super) fn referenced_entities(
    record: &VersionedExportRecord,
) -> Result<Vec<(String, String)>, ExportError> {
    let payload = record.payload.as_object().ok_or_else(|| {
        ExportError::Store(StoreError::Serialization(format!(
            "payload for `{}` must be an object",
            record.entity_type
        )))
    })?;

    let mut refs = Vec::new();
    match record.entity_type.as_str() {
        ENTITY_TASK => {
            push_optional_ref(payload, "list_id", ENTITY_LIST, &mut refs);
        }
        ENTITY_DAILY_REVIEW => {
            push_array_refs(payload, "linked_task_ids", ENTITY_TASK, &mut refs);
            push_array_refs(payload, "linked_list_ids", ENTITY_LIST, &mut refs);
        }
        ENTITY_CURRENT_FOCUS => {
            push_array_refs(payload, "task_ids", ENTITY_TASK, &mut refs);
        }
        ENTITY_FOCUS_SCHEDULE => {
            if let Some(blocks) = payload.get("blocks").and_then(|value| value.as_array()) {
                for block in blocks {
                    let Some(block) = block.as_object() else {
                        continue;
                    };
                    push_optional_ref(block, "task_id", ENTITY_TASK, &mut refs);
                    push_optional_ref(block, "event_id", ENTITY_CALENDAR_EVENT, &mut refs);
                }
            }
        }
        EDGE_TASK_TAG => {
            push_optional_ref(payload, "task_id", ENTITY_TASK, &mut refs);
            push_optional_ref(payload, "tag_id", ENTITY_TAG, &mut refs);
        }
        EDGE_TASK_DEPENDENCY => {
            push_optional_ref(payload, "task_id", ENTITY_TASK, &mut refs);
            push_optional_ref(payload, "depends_on_task_id", ENTITY_TASK, &mut refs);
        }
        EDGE_TASK_CALENDAR_EVENT_LINK => {
            push_optional_ref(payload, "task_id", ENTITY_TASK, &mut refs);
            push_optional_ref(
                payload,
                "calendar_event_id",
                ENTITY_CALENDAR_EVENT,
                &mut refs,
            );
        }
        EDGE_HABIT_COMPLETION | ENTITY_HABIT_REMINDER_POLICY => {
            push_optional_ref(payload, "habit_id", ENTITY_HABIT, &mut refs);
        }
        ENTITY_TASK_REMINDER | ENTITY_TASK_CHECKLIST_ITEM => {
            push_optional_ref(payload, "task_id", ENTITY_TASK, &mut refs);
        }
        _ => {}
    }
    Ok(refs)
}

fn push_optional_ref(
    payload: &serde_json::Map<String, serde_json::Value>,
    field: &str,
    entity_type: &str,
    refs: &mut Vec<(String, String)>,
) {
    if let Some(value) = payload.get(field).and_then(|value| value.as_str()) {
        refs.push((entity_type.to_string(), value.to_string()));
    }
}

fn push_array_refs(
    payload: &serde_json::Map<String, serde_json::Value>,
    field: &str,
    entity_type: &str,
    refs: &mut Vec<(String, String)>,
) {
    if let Some(values) = payload.get(field).and_then(|value| value.as_array()) {
        for value in values.iter().filter_map(|value| value.as_str()) {
            refs.push((entity_type.to_string(), value.to_string()));
        }
    }
}
