use super::ai_changelog::{ai_changelog_payload_from_row, AI_CHANGELOG_SELECT_COLUMNS};
use super::calendar_subscription::{
    calendar_subscription_payload_from_row, CALENDAR_SUBSCRIPTION_SELECT_COLUMNS,
};
use super::habit::{habit_payload_from_row, load_habit_sync_payload, HABIT_SELECT_COLUMNS};
use super::habit_completion::{habit_completion_payload_from_row, HABIT_COMPLETION_SELECT_COLUMNS};
use super::habit_reminder_policy::{
    habit_reminder_policy_payload_from_row, HABIT_REMINDER_POLICY_SELECT_COLUMNS,
};
use super::memory::{load_memory_sync_payload, memory_payload_from_row, MEMORY_SELECT_COLUMNS};
use super::*;
use crate::open_db_in_memory;
use lorvex_domain::{
    ChecklistItemId, EventId, ListId, MemoryRevisionId, ReminderId, TagId, TaskId,
};
use rusqlite::{params, Connection};

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}
fn tag(id: &str) -> TagId {
    TagId::from_trusted(id.to_string())
}
fn evt(id: &str) -> EventId {
    EventId::from_trusted(id.to_string())
}
fn rid(id: &str) -> ReminderId {
    ReminderId::from_trusted(id.to_string())
}
fn cid(id: &str) -> ChecklistItemId {
    ChecklistItemId::from_trusted(id.to_string())
}
fn mrid(id: &str) -> MemoryRevisionId {
    MemoryRevisionId::from_trusted(id.to_string())
}
fn lid(id: &str) -> ListId {
    ListId::from_trusted(id.to_string())
}

const V: &str = "0000000000000_0000_a0a0a0a0a0a0a0a0";
const T0: &str = "2026-04-01T00:00:00.000Z";
const T1: &str = "2026-04-02T00:00:00.000Z";

fn seed_list(conn: &Connection) {
    crate::test_support::ListBuilder::new("list-default")
        .name("L")
        .version(V)
        .created_at(T0)
        .or_ignore(true)
        .insert(conn);
}

fn seed_task(conn: &Connection, id: &str) {
    seed_list(conn);
    crate::test_support::TaskBuilder::new(id)
        .title("T")
        .list_id(Some("list-default"))
        .version(V)
        .created_at(T0)
        .insert(conn);
}

// ---------------------------------------------------------------------------
// list
// ---------------------------------------------------------------------------

#[test]
fn list_payload_includes_archive_and_position_columns() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists
            (id, name, color, icon, description, ai_notes, created_at, updated_at,
             version, archived_at, position)
         VALUES
            ('list-sync', 'Sync List', '#224466', 'folder', 'desc', 'notes',
             ?1, ?2, ?3, '2026-04-03T00:00:00.000Z', 17)",
        params![T0, T1, V],
    )
    .unwrap();

    let row = crate::repositories::list_repo::get_list(&conn, &lid("list-sync"))
        .unwrap()
        .unwrap();
    let payload = list_payload(&row);

    assert_eq!(payload["id"], "list-sync");
    assert_eq!(payload["name"], "Sync List");
    assert_eq!(payload["color"], "#224466");
    assert_eq!(payload["icon"], "folder");
    assert_eq!(payload["description"], "desc");
    assert_eq!(payload["ai_notes"], "notes");
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T1);
    assert_eq!(payload["version"], V);
    assert_eq!(payload["archived_at"], "2026-04-03T00:00:00.000Z");
    assert_eq!(payload["position"], 17);
}

// ---------------------------------------------------------------------------
// habit
// ---------------------------------------------------------------------------

#[test]
fn habit_payload_round_trips_through_select_columns() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO habits
            (id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
             target_count, milestone_target, archived, created_at, updated_at, lookup_key, position, version)
         VALUES
            ('habit-1', 'Read', 'book', '#4477aa', 'after coffee', 'weekly', 1, NULL,
             2, 30, 0, ?1, ?2, 'read', 11, ?3)",
        params![T0, T1, V],
    )
    .unwrap();
    // Weekly weekday set lives in the `habit_weekdays` child (Mon=0, Wed=2).
    conn.execute(
        "INSERT INTO habit_weekdays (habit_id, weekday) VALUES ('habit-1', 0), ('habit-1', 2)",
        [],
    )
    .unwrap();

    let payload = load_habit_sync_payload(
        &conn,
        &lorvex_domain::HabitId::from_trusted("habit-1".to_string()),
    )
    .unwrap()
    .unwrap();
    assert_eq!(payload["id"], "habit-1");
    assert_eq!(payload["name"], "Read");
    assert_eq!(payload["icon"], "book");
    assert_eq!(payload["color"], "#4477aa");
    assert_eq!(payload["cue"], "after coffee");
    assert_eq!(payload["frequency_type"], "weekly");
    assert_eq!(payload["weekdays"], serde_json::json!([0, 2]));
    assert_eq!(payload["per_period_target"], 1);
    assert!(payload["day_of_month"].is_null());
    assert!(payload.get("frequency_value").is_none());
    assert_eq!(payload["target_count"], 2);
    // Milestone target rides as a nullable scalar alongside `target_count`.
    assert_eq!(payload["milestone_target"], 30);
    assert_eq!(payload["archived"], false);
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T1);
    assert_eq!(payload["position"], 11);
    assert_eq!(payload["version"], V);

    let sql = format!("SELECT {HABIT_SELECT_COLUMNS} FROM habits WHERE id = ?1");
    let streamed = conn
        .query_row(&sql, params!["habit-1"], habit_payload_from_row)
        .unwrap();
    assert_eq!(payload, streamed);
}

#[test]
fn habit_payload_emits_null_milestone_target_when_unset() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO habits
            (id, name, frequency_type, per_period_target, day_of_month,
             target_count, milestone_target, archived, created_at, updated_at, lookup_key, version)
         VALUES
            ('habit-2', 'Stretch', 'daily', 1, NULL, 1, NULL, 0, ?1, ?2, 'stretch', ?3)",
        params![T0, T1, V],
    )
    .unwrap();

    let payload = load_habit_sync_payload(
        &conn,
        &lorvex_domain::HabitId::from_trusted("habit-2".to_string()),
    )
    .unwrap()
    .unwrap();
    // A habit with no milestone goal must emit the key as JSON null (not
    // drop it), so a same-version peer merge treats the owned key as unset
    // rather than a forward-compat unknown to preserve.
    assert!(payload.get("milestone_target").is_some());
    assert!(payload["milestone_target"].is_null());
}

// ---------------------------------------------------------------------------
// calendar_subscription
// ---------------------------------------------------------------------------

#[test]
fn calendar_subscription_payload_syncs_definition_without_local_retry_state() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO calendar_subscriptions
            (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES
            ('sub-1', 'Work', 'https://example.com/work.ics', '#ff0088', 0, ?1, ?2, ?3)",
        params![V, T0, T1],
    )
    .unwrap();

    let payload = load_calendar_subscription_sync_payload(&conn, "sub-1")
        .unwrap()
        .unwrap();
    assert_eq!(payload["id"], "sub-1");
    assert_eq!(payload["name"], "Work");
    assert_eq!(payload["url"], "https://example.com/work.ics");
    assert_eq!(payload["color"], "#ff0088");
    assert_eq!(payload["enabled"], false);
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T1);
    assert_eq!(payload["version"], V);
    assert!(payload.get("next_retry_at").is_none());
    assert!(payload.get("consecutive_failures").is_none());
    assert!(payload.get("last_retry_after_hint").is_none());

    let sql = format!(
        "SELECT {CALENDAR_SUBSCRIPTION_SELECT_COLUMNS} \
         FROM calendar_subscriptions WHERE id = ?1"
    );
    let streamed = conn
        .query_row(
            &sql,
            params!["sub-1"],
            calendar_subscription_payload_from_row,
        )
        .unwrap();
    assert_eq!(payload, streamed);
}

#[test]
fn calendar_subscription_seed_stream_uses_definition_payload_shape() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO calendar_subscriptions
            (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES
            ('sub-seed', 'Seed', 'https://example.com/seed.ics', NULL, 1, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let mut seen = Vec::new();
    let count = for_each_simple_sync_payload(
        &conn,
        SimpleSyncSeedKind::CalendarSubscription,
        |id, payload| {
            seen.push((id, payload));
            Ok::<_, crate::error::StoreError>(())
        },
    )
    .unwrap();

    assert_eq!(count, 1);
    assert_eq!(seen[0].0, "sub-seed");
    assert_eq!(seen[0].1["enabled"], true);
    assert!(seen[0].1["color"].is_null());
    assert!(seen[0].1.get("next_retry_at").is_none());
    assert!(seen[0].1.get("consecutive_failures").is_none());
    assert!(seen[0].1.get("last_retry_after_hint").is_none());
}

// ---------------------------------------------------------------------------
// memory
// ---------------------------------------------------------------------------

#[test]
fn memory_payload_round_trips_through_select_columns() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![lorvex_domain::new_entity_id_string(), "k1", "hello", V, T0],
    )
    .unwrap();

    let payload = load_memory_sync_payload(&conn, "k1").unwrap().unwrap();
    assert_eq!(payload["key"], "k1");
    assert_eq!(payload["content"], "hello");
    assert_eq!(payload["version"], V);
    assert_eq!(payload["updated_at"], T0);

    // Streaming-form parity: mapping the same row via the seed-style
    // path produces the identical payload.
    let sql = format!("SELECT {MEMORY_SELECT_COLUMNS} FROM memories WHERE key = ?1");
    let streamed = conn
        .query_row(&sql, params!["k1"], memory_payload_from_row)
        .unwrap();
    assert_eq!(payload, streamed);
}

#[test]
fn load_memory_sync_payload_returns_none_for_missing_key() {
    let conn = open_db_in_memory().unwrap();
    assert!(load_memory_sync_payload(&conn, "nope").unwrap().is_none());
}

// ---------------------------------------------------------------------------
// memory_revision
// ---------------------------------------------------------------------------

#[test]
fn memory_revision_payload_handles_optional_columns() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO memory_revisions
            (id, memory_key, content, operation, source_revision_id, actor, version, created_at)
         VALUES (?1, ?2, NULL, 'delete', NULL, 'human', ?3, ?4)",
        params!["rev-1", "k1", V, T0],
    )
    .unwrap();

    let payload = load_memory_revision_sync_payload(&conn, &mrid("rev-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["id"], "rev-1");
    assert_eq!(payload["memory_key"], "k1");
    assert!(payload["content"].is_null());
    assert_eq!(payload["operation"], "delete");
    assert!(payload["source_revision_id"].is_null());
    assert_eq!(payload["actor"], "human");
    assert_eq!(payload["version"], V);
    assert_eq!(payload["created_at"], T0);
}

// ---------------------------------------------------------------------------
// tag / task_tag
// ---------------------------------------------------------------------------

#[test]
fn tag_payload_includes_version_and_nullable_color() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
         VALUES ('tag-1', 'Work', 'work', NULL, ?1, ?2, ?3)",
        params![T0, T1, V],
    )
    .unwrap();

    let payload = load_tag_sync_payload(&conn, &tag("tag-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["id"], "tag-1");
    assert_eq!(payload["display_name"], "Work");
    assert_eq!(payload["lookup_key"], "work");
    assert!(payload["color"].is_null());
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T1);
    assert_eq!(payload["version"], V);
}

#[test]
fn task_tag_payload_carries_version() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('tag-1', 'Work', 'work', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES ('task-1', 'tag-1', ?1, ?2)",
        params![V, T0],
    )
    .unwrap();

    let payload = load_task_tag_sync_payload(&conn, &tid("task-1"), &tag("tag-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["task_id"], "task-1");
    assert_eq!(payload["tag_id"], "tag-1");
    assert_eq!(payload["version"], V);
    assert_eq!(payload["created_at"], T0);
}

// ---------------------------------------------------------------------------
// task_calendar_event_link
// ---------------------------------------------------------------------------

#[test]
fn task_calendar_event_link_payload_carries_version_and_updated_at() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO calendar_events
            (id, title, start_date, all_day, event_type, version, created_at, updated_at)
         VALUES ('ev-1', 'Meet', '2026-04-05', 0, 'event', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES ('task-1', 'ev-1', ?1, ?2, ?3)",
        params![V, T0, T1],
    )
    .unwrap();

    let payload = load_task_calendar_event_link_sync_payload(&conn, &tid("task-1"), &evt("ev-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["task_id"], "task-1");
    assert_eq!(payload["calendar_event_id"], "ev-1");
    assert_eq!(payload["version"], V);
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T1);
}

// ---------------------------------------------------------------------------
// habit (bool column: archived)
// ---------------------------------------------------------------------------

#[test]
fn habit_payload_emits_json_bool_for_archived() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
            day_of_month, target_count, archived, version, created_at, updated_at)
         VALUES ('h-1', 'Read', NULL, NULL, NULL, 'daily', 1, NULL, 1, 1, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let sql = format!("SELECT {HABIT_SELECT_COLUMNS} FROM habits WHERE id = ?1");
    let payload = conn
        .query_row(&sql, params!["h-1"], habit_payload_from_row)
        .unwrap();

    assert_eq!(payload["id"], "h-1");
    assert_eq!(payload["name"], "Read");
    assert!(payload["icon"].is_null());
    // A daily habit pins no weekdays — an empty materialized array.
    assert_eq!(payload["weekdays"], serde_json::json!([]));
    assert_eq!(payload["target_count"], 1);
    // Critical: SQLite int(1) MUST round-trip as JSON bool to match the
    // generic pragma reader's wire shape.
    assert_eq!(payload["archived"], true);
    assert_eq!(payload["version"], V);
}

// ---------------------------------------------------------------------------
// habit_completion
// ---------------------------------------------------------------------------

#[test]
fn habit_completion_payload_carries_version() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES ('h-1', 'Read', 'daily', 1, 0, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO habit_completions
            (habit_id, completed_date, value, note, version, created_at, updated_at)
         VALUES ('h-1', '2026-04-05', 1, 'good', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let sql = format!(
        "SELECT {HABIT_COMPLETION_SELECT_COLUMNS} FROM habit_completions \
         WHERE habit_id = ?1 AND completed_date = ?2"
    );
    let payload = conn
        .query_row(
            &sql,
            params!["h-1", "2026-04-05"],
            habit_completion_payload_from_row,
        )
        .unwrap();
    assert_eq!(payload["habit_id"], "h-1");
    assert_eq!(payload["completed_date"], "2026-04-05");
    assert_eq!(payload["value"], 1);
    assert_eq!(payload["note"], "good");
    assert_eq!(payload["version"], V);
}

// ---------------------------------------------------------------------------
// habit_reminder_policy (bool column: enabled)
// ---------------------------------------------------------------------------

#[test]
fn habit_reminder_policy_payload_emits_json_bool_for_enabled() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES ('h-1', 'Read', 'daily', 1, 0, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO habit_reminder_policies
            (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES ('p-1', 'h-1', '07:00', 0, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let sql = format!(
        "SELECT {HABIT_REMINDER_POLICY_SELECT_COLUMNS} FROM habit_reminder_policies WHERE id = ?1"
    );
    let payload = conn
        .query_row(&sql, params!["p-1"], habit_reminder_policy_payload_from_row)
        .unwrap();
    assert_eq!(payload["id"], "p-1");
    assert_eq!(payload["habit_id"], "h-1");
    assert_eq!(payload["reminder_time"], "07:00");
    // Critical: int(0) → JSON `false`.
    assert_eq!(payload["enabled"], false);
    assert_eq!(payload["version"], V);
}

// ---------------------------------------------------------------------------
// preference (upsert + delete-snapshot variants)
// ---------------------------------------------------------------------------

#[test]
fn preference_upsert_payload_parses_canonical_json() {
    let payload = preference_upsert_payload("theme", "\"dark\"", T0).unwrap();
    assert_eq!(payload["key"], "theme");
    assert_eq!(payload["value"], "dark");
    assert_eq!(payload["updated_at"], T0);
}

#[test]
fn preference_upsert_payload_rejects_malformed_json() {
    let err =
        preference_upsert_payload("theme", "{not json", T0).expect_err("malformed json should err");
    let msg = err.to_string();
    assert!(msg.contains("theme"), "unexpected error: {msg}");
}

#[test]
fn preference_delete_snapshot_carries_version() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO preferences (key, value, updated_at, version)
         VALUES ('theme', '\"dark\"', ?1, ?2)",
        params![T0, V],
    )
    .unwrap();

    let snap = load_preference_delete_snapshot(&conn, "theme")
        .unwrap()
        .unwrap();
    assert_eq!(snap["key"], "theme");
    assert_eq!(snap["value"], "\"dark\"");
    assert_eq!(snap["version"], V);
    assert_eq!(snap["updated_at"], T0);
}

// ---------------------------------------------------------------------------
// task_reminder / task_checklist_item
// ---------------------------------------------------------------------------

#[test]
fn task_reminder_payload_omits_updated_at_field() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, cancelled_at,
            version, created_at, original_local_time, original_tz)
         VALUES ('rem-1', 'task-1', ?1, NULL, ?2, ?3, ?4, '09:00', 'Asia/Tokyo')",
        params![T1, T0, V, T0],
    )
    .unwrap();

    let payload = load_task_reminder_sync_payload(&conn, &rid("rem-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["id"], "rem-1");
    assert_eq!(payload["task_id"], "task-1");
    assert_eq!(payload["reminder_at"], T1);
    assert!(payload["dismissed_at"].is_null());
    assert_eq!(payload["cancelled_at"], T0);
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["original_local_time"], "09:00");
    assert_eq!(payload["original_tz"], "Asia/Tokyo");
    // task_reminders has no `updated_at` column — invariant the runtime
    // helper carried; the consolidated mapper preserves it.
    assert!(payload.get("updated_at").is_none());
    // task_reminders does not currently round-trip `version` in the sync
    // envelope (see `child_items::load_task_reminder_sync_payload`).
    assert!(payload.get("version").is_none());
}

#[test]
fn task_checklist_item_payload_round_trip() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO task_checklist_items
            (id, task_id, position, text, completed_at, version, created_at, updated_at)
         VALUES ('cli-1', 'task-1', 0, 'do it', NULL, ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let payload = load_task_checklist_item_sync_payload(&conn, &cid("cli-1"))
        .unwrap()
        .unwrap();
    assert_eq!(payload["id"], "cli-1");
    assert_eq!(payload["task_id"], "task-1");
    assert_eq!(payload["position"], 0);
    assert_eq!(payload["text"], "do it");
    assert!(payload["completed_at"].is_null());
    assert_eq!(payload["created_at"], T0);
    assert_eq!(payload["updated_at"], T0);
}

// ---------------------------------------------------------------------------
// ai_changelog
// ---------------------------------------------------------------------------

#[test]
fn ai_changelog_payload_emits_json_bool_for_is_preview() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, entity_id, summary,
             initiated_by, mcp_tool, source_device_id, before_json, after_json, undo_token,
             is_preview)
         VALUES ('chg-1', ?1, 'create', 'task', 'task-1', 'summary', 'ai',
                 'create_task', 'dev-1', NULL, NULL, NULL, 0)",
        params![T0],
    )
    .unwrap();

    let sql = format!("SELECT {AI_CHANGELOG_SELECT_COLUMNS} FROM ai_changelog WHERE id = ?1");
    let payload = conn
        .query_row(&sql, params!["chg-1"], ai_changelog_payload_from_row)
        .unwrap();
    assert_eq!(payload["id"], "chg-1");
    assert_eq!(payload["timestamp"], T0);
    assert_eq!(payload["operation"], "create");
    assert_eq!(payload["entity_type"], "task");
    assert_eq!(payload["entity_id"], "task-1");
    assert!(payload["entity_ids"].is_null());
    // The audit row column is INT 0/1; the wire shape is JSON bool.
    assert_eq!(payload["is_preview"], false);
}

// ---------------------------------------------------------------------------
// Batch pre-delete loaders
// ---------------------------------------------------------------------------

#[test]
fn task_reminder_pre_delete_snapshots_empty_input_returns_empty_map() {
    let conn = open_db_in_memory().unwrap();
    let out = load_task_reminder_pre_delete_snapshots(&conn, &[]).unwrap();
    assert!(
        out.is_empty(),
        "empty input must short-circuit to empty map"
    );
}

#[test]
fn task_reminder_pre_delete_snapshots_round_trip_matches_per_id_loader() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, cancelled_at,
                                       version, created_at, original_local_time, original_tz)
         VALUES
            ('rem-1', 'task-1', '2026-04-01T09:00:00.000Z', NULL, NULL,
             ?1, ?2, '09:00', 'America/New_York'),
            ('rem-2', 'task-1', '2026-04-02T10:30:00.000Z',
             '2026-04-02T10:31:00.000Z', NULL, ?1, ?2, NULL, NULL)",
        params![V, T0],
    )
    .unwrap();

    let ids = vec![
        "rem-1".to_string(),
        "rem-2".to_string(),
        "rem-missing".to_string(),
    ];
    let snapshots = load_task_reminder_pre_delete_snapshots(&conn, &ids).unwrap();
    assert_eq!(
        snapshots.len(),
        2,
        "missing ids must be absent from the map"
    );

    // Per-id sibling produces the same payload shape.
    let per_id = load_task_reminder_sync_payload(&conn, &rid("rem-1"))
        .unwrap()
        .unwrap();
    assert_eq!(snapshots["rem-1"], per_id);
    // Spot-check rem-2 carries the dismissed_at value.
    assert_eq!(
        snapshots["rem-2"]["dismissed_at"],
        "2026-04-02T10:31:00.000Z"
    );
}

#[test]
fn task_checklist_item_pre_delete_snapshots_round_trip() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, completed_at,
                                             version, created_at, updated_at)
         VALUES
            ('item-1', 'task-1', 0, 'first', NULL, ?1, ?2, ?2),
            ('item-2', 'task-1', 1, 'second', '2026-04-03T08:00:00Z', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let ids = vec!["item-1".to_string(), "item-2".to_string()];
    let snapshots = load_task_checklist_item_pre_delete_snapshots(&conn, &ids).unwrap();
    assert_eq!(snapshots.len(), 2);
    let per_id = load_task_checklist_item_sync_payload(&conn, &cid("item-1"))
        .unwrap()
        .unwrap();
    assert_eq!(snapshots["item-1"], per_id);
    assert!(snapshots["item-1"]["completed_at"].is_null());
    assert_eq!(snapshots["item-2"]["completed_at"], "2026-04-03T08:00:00Z");
}

#[test]
fn task_tag_pre_delete_snapshots_round_trip_keyed_on_tag_id() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('tag-a', 'A', 'a', ?1, ?2, ?2),
                ('tag-b', 'B', 'b', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES ('task-1', 'tag-a', ?1, ?2),
                ('task-1', 'tag-b', ?1, ?2)",
        params![V, T0],
    )
    .unwrap();

    let tag_ids = vec![
        "tag-a".to_string(),
        "tag-b".to_string(),
        "tag-absent".to_string(),
    ];
    let snapshots = load_task_tag_pre_delete_snapshots(&conn, &tid("task-1"), &tag_ids).unwrap();
    assert_eq!(snapshots.len(), 2);
    assert_eq!(snapshots["tag-a"]["task_id"], "task-1");
    assert_eq!(snapshots["tag-a"]["tag_id"], "tag-a");
    assert_eq!(snapshots["tag-a"]["version"], V);
    // Per-id sibling produces the same payload shape.
    let per_id = load_task_tag_sync_payload(&conn, &tid("task-1"), &tag("tag-a"))
        .unwrap()
        .unwrap();
    assert_eq!(snapshots["tag-a"], per_id);
}

#[test]
fn task_calendar_event_link_pre_delete_snapshots_keyed_on_event_id() {
    let conn = open_db_in_memory().unwrap();
    seed_task(&conn, "task-1");
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, version, created_at, updated_at)
         VALUES ('evt-a', 'A', '2026-04-01', ?1, ?2, ?2),
                ('evt-b', 'B', '2026-04-02', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version,
                                                  created_at, updated_at)
         VALUES ('task-1', 'evt-a', ?1, ?2, ?2),
                ('task-1', 'evt-b', ?1, ?2, ?2)",
        params![V, T0],
    )
    .unwrap();

    let event_ids = vec!["evt-a".to_string(), "evt-b".to_string()];
    let snapshots =
        load_task_calendar_event_link_pre_delete_snapshots(&conn, &tid("task-1"), &event_ids)
            .unwrap();
    assert_eq!(snapshots.len(), 2);
    assert_eq!(snapshots["evt-a"]["calendar_event_id"], "evt-a");
    assert_eq!(snapshots["evt-a"]["version"], V);
    assert_eq!(snapshots["evt-a"]["updated_at"], T0);
    let per_id = load_task_calendar_event_link_sync_payload(&conn, &tid("task-1"), &evt("evt-a"))
        .unwrap()
        .unwrap();
    assert_eq!(snapshots["evt-a"], per_id);
}
