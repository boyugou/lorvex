use crate::export::VersionedExportRecord;
use crate::export_scope::{ImportValidationFinding, ImportValidationSeverity};
use lorvex_domain::naming::{
    EntityKind, ENTITY_CALENDAR_EVENT, ENTITY_HABIT, ENTITY_LIST, ENTITY_TAG, ENTITY_TASK,
};

use crate::import::apply::{
    optional_string_field, required_object_array_field, required_string_array_field,
    required_string_field,
};
use crate::import::ImportError;

use super::index::ScopedArchiveIndex;

pub(super) fn validate_scoped_entity_dependencies(
    index: &ScopedArchiveIndex,
    entities: &[VersionedExportRecord],
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    for record in entities {
        let payload = &record.payload;
        // typed `EntityKind` dispatch.
        match Some(record.entity_type) {
            Some(EntityKind::Task) => {
                let task_id = required_string_field(payload, "id", "task payload")?;
                if let Some(list_id) = optional_string_field(payload, "list_id", "task payload")? {
                    push_scoped_missing_ref(
                        index,
                        findings,
                        ENTITY_LIST,
                        &list_id,
                        "missing_list_reference",
                        format!(
                            "scoped archive task `{task_id}` references missing list `{list_id}`"
                        ),
                    );
                }
            }
            Some(EntityKind::DailyReview) => {
                let review_date = required_string_field(payload, "date", "daily_review payload")?;
                for task_id in
                    required_string_array_field(payload, "linked_task_ids", "daily_review payload")?
                {
                    push_scoped_missing_ref(
                        index,
                        findings,
                        ENTITY_TASK,
                        &task_id,
                        "missing_entity_dependency",
                        format!("scoped archive daily_review `{review_date}` references missing task `{task_id}`"),
                    );
                }
                for list_id in
                    required_string_array_field(payload, "linked_list_ids", "daily_review payload")?
                {
                    push_scoped_missing_ref(
                        index,
                        findings,
                        ENTITY_LIST,
                        &list_id,
                        "missing_entity_dependency",
                        format!("scoped archive daily_review `{review_date}` references missing list `{list_id}`"),
                    );
                }
            }
            Some(EntityKind::CurrentFocus) => {
                let focus_date = required_string_field(payload, "date", "current_focus payload")?;
                for task_id in
                    required_string_array_field(payload, "task_ids", "current_focus payload")?
                {
                    push_scoped_missing_ref(
                        index,
                        findings,
                        ENTITY_TASK,
                        &task_id,
                        "missing_entity_dependency",
                        format!("scoped archive current_focus `{focus_date}` references missing task `{task_id}`"),
                    );
                }
            }
            Some(EntityKind::FocusSchedule) => {
                let schedule_date =
                    required_string_field(payload, "date", "focus_schedule payload")?;
                for (block_index, block) in
                    required_object_array_field(payload, "blocks", "focus_schedule payload")?
                        .iter()
                        .enumerate()
                {
                    let context = format!("focus_schedule payload.blocks[{block_index}]");
                    if let Some(task_id) = optional_string_field(block, "task_id", &context)? {
                        push_scoped_missing_ref(
                            index,
                            findings,
                            ENTITY_TASK,
                            &task_id,
                            "missing_entity_dependency",
                            format!("scoped archive focus_schedule `{schedule_date}` block {block_index} references missing task `{task_id}`"),
                        );
                    }
                    if let Some(event_id) = optional_string_field(block, "event_id", &context)? {
                        push_scoped_missing_ref(
                            index,
                            findings,
                            ENTITY_CALENDAR_EVENT,
                            &event_id,
                            "missing_entity_dependency",
                            format!("scoped archive focus_schedule `{schedule_date}` block {block_index} references missing calendar event `{event_id}`"),
                        );
                    }
                }
            }
            _ => {}
        }
    }
    Ok(())
}

pub(super) fn validate_scoped_edge_dependencies(
    index: &ScopedArchiveIndex,
    edges: &[VersionedExportRecord],
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    for record in edges {
        let payload = &record.payload;
        // typed `EntityKind` dispatch.
        match Some(record.entity_type) {
            Some(EntityKind::TaskTag) => {
                let task_id = required_string_field(payload, "task_id", "task_tag payload")?;
                let tag_id = required_string_field(payload, "tag_id", "task_tag payload")?;
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_TASK,
                    &task_id,
                    "missing_entity_dependency",
                    format!("scoped archive task_tag references missing task `{task_id}`"),
                );
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_TAG,
                    &tag_id,
                    "missing_entity_dependency",
                    format!("scoped archive task_tag references missing tag `{tag_id}`"),
                );
            }
            Some(EntityKind::TaskDependency) => {
                let task_id = required_string_field(payload, "task_id", "task_dependency payload")?;
                let depends_on = required_string_field(
                    payload,
                    "depends_on_task_id",
                    "task_dependency payload",
                )?;
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_TASK,
                    &task_id,
                    "missing_entity_dependency",
                    format!("scoped archive task_dependency references missing task `{task_id}`"),
                );
                push_scoped_missing_ref(index, findings, ENTITY_TASK, &depends_on, "missing_entity_dependency", format!("scoped archive task_dependency references missing dependency task `{depends_on}`"));
            }
            Some(EntityKind::TaskCalendarEventLink) => {
                let task_id =
                    required_string_field(payload, "task_id", "task_calendar_event_link payload")?;
                let event_id = required_string_field(
                    payload,
                    "calendar_event_id",
                    "task_calendar_event_link payload",
                )?;
                push_scoped_missing_ref(index, findings, ENTITY_TASK, &task_id, "missing_entity_dependency", format!("scoped archive task_calendar_event_link references missing task `{task_id}`"));
                push_scoped_missing_ref(index, findings, ENTITY_CALENDAR_EVENT, &event_id, "missing_entity_dependency", format!("scoped archive task_calendar_event_link references missing calendar event `{event_id}`"));
            }
            Some(EntityKind::HabitCompletion) => {
                let habit_id =
                    required_string_field(payload, "habit_id", "habit_completion payload")?;
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_HABIT,
                    &habit_id,
                    "missing_entity_dependency",
                    format!(
                        "scoped archive habit_completion references missing habit `{habit_id}`"
                    ),
                );
            }
            _ => {}
        }
    }
    Ok(())
}

pub(super) fn validate_scoped_child_dependencies(
    index: &ScopedArchiveIndex,
    children: &[VersionedExportRecord],
    findings: &mut Vec<ImportValidationFinding>,
) -> Result<(), ImportError> {
    for record in children {
        let payload = &record.payload;
        // typed `EntityKind` dispatch.
        match Some(record.entity_type) {
            Some(EntityKind::TaskReminder) => {
                let task_id = required_string_field(payload, "task_id", "task_reminder payload")?;
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_TASK,
                    &task_id,
                    "missing_entity_dependency",
                    format!("scoped archive task_reminder references missing task `{task_id}`"),
                );
            }
            Some(EntityKind::TaskChecklistItem) => {
                let task_id =
                    required_string_field(payload, "task_id", "task_checklist_item payload")?;
                push_scoped_missing_ref(
                    index,
                    findings,
                    ENTITY_TASK,
                    &task_id,
                    "missing_entity_dependency",
                    format!(
                        "scoped archive task_checklist_item references missing task `{task_id}`"
                    ),
                );
            }
            Some(EntityKind::HabitReminderPolicy) => {
                let habit_id =
                    required_string_field(payload, "habit_id", "habit_reminder_policy payload")?;
                push_scoped_missing_ref(index, findings, ENTITY_HABIT, &habit_id, "missing_entity_dependency", format!("scoped archive habit_reminder_policy references missing habit `{habit_id}`"));
            }
            _ => {}
        }
    }
    Ok(())
}

fn push_scoped_missing_ref(
    index: &ScopedArchiveIndex,
    findings: &mut Vec<ImportValidationFinding>,
    entity_type: &str,
    id: &str,
    code: &str,
    message: String,
) {
    if index.contains(entity_type, id) {
        return;
    }
    findings.push(ImportValidationFinding {
        severity: ImportValidationSeverity::Error,
        code: code.to_string(),
        message,
    });
}
