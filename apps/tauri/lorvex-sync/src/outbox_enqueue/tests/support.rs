pub(super) use crate::apply::apply_envelope;
pub(super) use crate::canonicalize::canonicalize_json;
pub(super) use crate::envelope::{SyncEnvelope, SyncOperation};
pub(super) use crate::outbox;
pub(super) use crate::test_db;
pub(super) use lorvex_domain::hlc_state::HlcState;
pub(super) use lorvex_domain::naming;
pub(super) use lorvex_domain::version::PAYLOAD_SCHEMA_VERSION;
pub(super) use rusqlite::{params, Connection};
pub(super) use serde_json::Value;

pub(super) use super::super::snapshot::entity_type_to_table;
pub(super) use super::super::{
    enqueue_entity_upsert, enqueue_payload_delete, enqueue_payload_upsert,
    tombstone_completions_for_habit_delete, tombstone_edges_for_calendar_event_delete,
    tombstone_reminder_policies_for_habit_delete, EnqueueError, OutboxWriteContext,
};

pub(super) fn setup_hlc() -> HlcState {
    HlcState::new("decafdec00000001").unwrap()
}

/// Insert a minimal task row for snapshot testing.
/// delegated to the shared TaskBuilder.
pub(super) fn insert_task(conn: &Connection, id: &str, title: &str) {
    lorvex_store::test_support::TaskBuilder::new(id)
        .title(title)
        .insert(conn);
}

/// Insert a minimal list row for snapshot testing.
pub(super) fn insert_list(conn: &Connection, id: &str, name: &str) {
    lorvex_store::test_support::ListBuilder::new(id)
        .name(name)
        .insert(conn);
}

/// Insert a minimal tag row for snapshot testing.
pub(super) fn insert_tag(conn: &Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, ?2, ?2, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')",
        params![id, name],
    )
    .unwrap();
}

pub(super) fn insert_habit(conn: &Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES (?1, ?2, 'daily', 1, 0, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')",
        params![id, name],
    )
    .unwrap();
}

pub(super) fn insert_calendar_event(conn: &Connection, id: &str, all_day: i64) {
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, all_day, event_type, version, created_at, updated_at)
         VALUES (?1, 'Planning', '2026-03-20', ?2, 'event', '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')",
        params![id, all_day],
    )
    .unwrap();
}

pub(super) fn insert_calendar_subscription(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO calendar_subscriptions
            (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES
            (?1, 'Work ICS', 'https://example.com/work.ics', '#ff0088', 1,
             '0000000000000_0000_0000000000000000',
             '2026-03-20T00:00:00.000Z', '2026-03-21T00:00:00.000Z')",
        params![id],
    )
    .unwrap();
}

pub(super) fn insert_preference(conn: &Connection, key: &str, value: &str) {
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z')",
        params![key, value],
    )
    .unwrap();
}

pub(super) fn insert_task_calendar_event_link(conn: &Connection, task_id: &str, event_id: &str) {
    insert_task(conn, task_id, task_id);
    insert_calendar_event(conn, event_id, 1);
    conn.execute(
        "INSERT INTO task_calendar_event_links
         (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2,
                 '0000000000000_0000_edgeedgeedgeedge',
                 '2026-04-02T08:00:00.000Z',
                 '2026-04-02T09:00:00.000Z')",
        params![task_id, event_id],
    )
    .unwrap();
}

pub(super) fn insert_task_tag(conn: &Connection, task_id: &str, tag_id: &str) {
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
         VALUES (?1, ?2, '2026-03-20T00:00:00.000Z', '0000000000000_0000_0000000000000000')",
        params![task_id, tag_id],
    )
    .unwrap();
}

pub(super) fn parse_outbox_payload(conn: &Connection, entity_type: &str, entity_id: &str) -> Value {
    let raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![entity_type, entity_id],
            |r| r.get(0),
        )
        .expect("outbox row should exist");
    serde_json::from_str(&raw).expect("outbox payload must be valid JSON")
}

pub(super) fn seed_default_list_and_tasks(conn: &Connection, task_ids: &[&str]) {
    lorvex_store::test_support::ListBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000002136")
        .name("Default")
        .created_at("2026-04-01T00:00:00.000Z")
        .or_ignore(true)
        .insert(conn);
    for id in task_ids {
        lorvex_store::test_support::TaskBuilder::new(id)
            .title("T")
            .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000002136"))
            .created_at("2026-04-01T00:00:00.000Z")
            .insert(conn);
    }
}
