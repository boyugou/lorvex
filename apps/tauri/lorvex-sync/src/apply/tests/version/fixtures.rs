use super::*;
pub(super) fn seed_memory_row(conn: &Connection, key: &str, content: &str, version: &str) {
    conn.execute(
        "INSERT INTO memories (id, key, content, version, updated_at) \
         VALUES (?1, ?2, ?3, ?4, '2026-03-23T12:00:00.000Z')",
        rusqlite::params![lorvex_domain::new_entity_id_string(), key, content, version],
    )
    .unwrap();
}

pub(super) fn make_memory_envelope(key: &str, version: &str, content: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Memory,
        entity_id: key.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(r#"{{"content":"{content}","updated_at":"2026-03-24T00:00:00.000Z"}}"#),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn seed_preference_row(conn: &Connection, key: &str, value: &str, version: &str) {
    let value = serde_json::to_string(value).unwrap();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) \
         VALUES (?1, ?2, ?3, '2026-03-23T12:00:00.000Z')",
        rusqlite::params![key, value, version],
    )
    .unwrap();
}

pub(super) fn make_preference_envelope(key: &str, version: &str, value: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Preference,
        entity_id: key.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(r#"{{"value":"{value}","updated_at":"2026-03-24T00:00:00.000Z"}}"#),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn seed_calendar_subscription_row(
    conn: &Connection,
    id: &str,
    name: &str,
    version: &str,
) {
    conn.execute(
        "INSERT INTO calendar_subscriptions \
         (id, name, url, enabled, version, created_at, updated_at) \
         VALUES (?1, ?2, 'https://example.com/feed', 1, ?3, \
                 '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z')",
        rusqlite::params![id, name, version],
    )
    .unwrap();
}

pub(super) fn make_calendar_subscription_envelope(
    id: &str,
    version: &str,
    name: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarSubscription,
        entity_id: id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(
            r#"{{"name":"{name}","url":"https://example.com/feed","enabled":true,"created_at":"2026-03-24T00:00:00.000Z","updated_at":"2026-03-24T00:00:00.000Z"}}"#
        ),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn seed_daily_review_row(conn: &Connection, date: &str, summary: &str, version: &str) {
    conn.execute(
        "INSERT INTO daily_reviews (date, summary, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z')",
        rusqlite::params![date, summary, version],
    )
    .unwrap();
}

pub(super) fn make_daily_review_envelope(date: &str, version: &str, summary: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::DailyReview,
        entity_id: date.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(
            r#"{{"summary":"{summary}","linked_task_ids":[],"linked_list_ids":[],"created_at":"2026-03-24T00:00:00.000Z","updated_at":"2026-03-24T00:00:00.000Z"}}"#
        ),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn seed_habit_parent(conn: &Connection, habit_id: &str) {
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) \
         VALUES (?1, 'Hab', '0000000000000_0000_0000000000000000', '', '')",
        [habit_id],
    )
    .unwrap();
}

pub(super) fn seed_habit_completion_row(
    conn: &Connection,
    habit_id: &str,
    date: &str,
    value: i64,
    version: &str,
) {
    conn.execute(
        "INSERT INTO habit_completions \
         (habit_id, completed_date, value, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z')",
        rusqlite::params![habit_id, date, value, version],
    )
    .unwrap();
}

pub(super) fn make_habit_completion_envelope(
    habit_id: &str,
    date: &str,
    version: &str,
    value: i64,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitCompletion,
        entity_id: format!("{habit_id}:{date}"),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(
            r#"{{"habit_id":"{habit_id}","completed_date":"{date}","value":{value},"created_at":"2026-03-24T00:00:00.000Z","updated_at":"2026-03-24T00:00:00.000Z"}}"#
        ),
        device_id: "remote-device".to_string(),
    }
}
