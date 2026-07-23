use lorvex_domain::naming::EntityKind;

pub(crate) fn validate_versioned_jsonl_identity(
    stream_name: &str,
    entity_type: EntityKind,
    top_level_entity_id: Option<&str>,
    payload: &serde_json::Value,
) -> Result<(), String> {
    let Some(expected_entity_id) = expected_entity_id(entity_type, payload)? else {
        return Ok(());
    };

    let Some(top_level_entity_id) = top_level_entity_id.filter(|value| !value.trim().is_empty())
    else {
        return Err(format!(
            "{stream_name} entry for `{}` must include a non-empty top-level entity_id",
            entity_type.as_str()
        ));
    };

    if top_level_entity_id != expected_entity_id {
        return Err(format!(
            "{stream_name} entry for `{}` has entity_id `{}` but payload identity is `{}`",
            entity_type.as_str(),
            top_level_entity_id,
            expected_entity_id,
        ));
    }

    Ok(())
}

fn expected_entity_id(
    entity_type: EntityKind,
    payload: &serde_json::Value,
) -> Result<Option<String>, String> {
    let field = match entity_type {
        EntityKind::List
        | EntityKind::Task
        | EntityKind::Tag
        | EntityKind::Habit
        | EntityKind::CalendarEvent
        | EntityKind::CalendarSubscription
        | EntityKind::MemoryRevision
        | EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy => Some("id"),
        EntityKind::Preference | EntityKind::Memory => Some("key"),
        EntityKind::DailyReview | EntityKind::CurrentFocus | EntityKind::FocusSchedule => {
            Some("date")
        }
        EntityKind::TaskTag
        | EntityKind::TaskDependency
        | EntityKind::TaskCalendarEventLink
        | EntityKind::HabitCompletion
        | EntityKind::TaskProviderEventLink
        | EntityKind::AiChangelog
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => None,
    };

    let Some(field) = field else {
        return Ok(None);
    };
    payload_identity_field(payload, field, entity_type).map(Some)
}

fn payload_identity_field(
    payload: &serde_json::Value,
    field: &str,
    entity_type: EntityKind,
) -> Result<String, String> {
    match payload.get(field) {
        Some(serde_json::Value::String(value)) if !value.trim().is_empty() => Ok(value.clone()),
        Some(serde_json::Value::Number(value)) => Ok(value.to_string()),
        _ => Err(format!(
            "payload for `{}` must include a non-empty `{field}` identity field",
            entity_type.as_str()
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_domain::naming::{ENTITY_LIST, ENTITY_PREFERENCE};

    #[test]
    fn validates_top_level_entity_id_against_payload_id() {
        let payload = serde_json::json!({"id": "list-1"});
        let kind = EntityKind::parse(ENTITY_LIST).unwrap();

        validate_versioned_jsonl_identity("entities.jsonl", kind, Some("list-1"), &payload)
            .unwrap();
    }

    #[test]
    fn rejects_top_level_entity_id_mismatch() {
        let payload = serde_json::json!({"id": "list-2"});
        let kind = EntityKind::parse(ENTITY_LIST).unwrap();

        let err =
            validate_versioned_jsonl_identity("entities.jsonl", kind, Some("list-1"), &payload)
                .unwrap_err();

        assert!(err.contains("entity_id `list-1`"));
        assert!(err.contains("payload identity is `list-2`"));
    }

    #[test]
    fn validates_keyed_payload_identities() {
        let payload = serde_json::json!({"key": "timezone"});
        let kind = EntityKind::parse(ENTITY_PREFERENCE).unwrap();

        validate_versioned_jsonl_identity("entities.jsonl", kind, Some("timezone"), &payload)
            .unwrap();
    }
}
