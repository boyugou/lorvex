use super::*;
use rusqlite::params;

use crate::error::AppError;
use crate::test_support::{fixture_uuid, test_conn};

fn seed_open_task(conn: &rusqlite::Connection, id: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Trash me")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-01T00:00:00Z")
        .list_id(Some("inbox"))
        .insert(conn);
}

fn task_archived_at(conn: &rusqlite::Connection, id: &str) -> Option<String> {
    conn.query_row(
        "SELECT archived_at FROM tasks WHERE id = ?1",
        params![id],
        |row| row.get::<_, Option<String>>(0),
    )
    .expect("read archived_at")
}

struct SeededChildIds {
    tag_edge_id: String,
    checklist_item_id: String,
    reminder_id: String,
    calendar_link_edge_id: String,
    outgoing_dep_edge_id: String,
    incoming_dep_edge_id: String,
}

fn seed_task_delete_children(
    conn: &rusqlite::Connection,
    task_id: &str,
    incoming_dep_task_id: &str,
    outgoing_dep_task_id: &str,
) -> SeededChildIds {
    let tag_id = fixture_uuid(&format!("tag-{task_id}"));
    let checklist_item_id = fixture_uuid(&format!("check-{task_id}"));
    let reminder_id = fixture_uuid(&format!("reminder-{task_id}"));
    let event_id = fixture_uuid(&format!("event-{task_id}"));

    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Delete tag', ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![tag_id, format!("delete-tag-{task_id}")],
    )
    .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![task_id, &tag_id],
    )
    .expect("seed task tag");

    conn.execute(
        "INSERT INTO task_checklist_items
            (id, task_id, position, text, version, created_at, updated_at)
         VALUES (?1, ?2, 0, 'Checklist', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![&checklist_item_id, task_id],
    )
    .expect("seed checklist item");

    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-04-20T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![&reminder_id, task_id],
    )
    .expect("seed reminder");

    conn.execute(
        "INSERT INTO calendar_events
            (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES (?1, 'Delete event', '2026-04-20', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![&event_id],
    )
    .expect("seed calendar event");
    conn.execute(
        "INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, created_at, updated_at, version)
         VALUES (?1, ?2, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        params![task_id, &event_id],
    )
    .expect("seed calendar link");

    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![task_id, outgoing_dep_task_id],
    )
    .expect("seed outgoing dependency");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![incoming_dep_task_id, task_id],
    )
    .expect("seed incoming dependency");

    SeededChildIds {
        tag_edge_id: format!("{task_id}:{tag_id}"),
        checklist_item_id,
        reminder_id,
        calendar_link_edge_id: format!("{task_id}:{event_id}"),
        outgoing_dep_edge_id: format!("{task_id}:{outgoing_dep_task_id}"),
        incoming_dep_edge_id: format!("{incoming_dep_task_id}:{task_id}"),
    }
}

fn count_delete_outbox(conn: &rusqlite::Connection, entity_type: &str, entity_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
        params![entity_type, entity_id],
        |row| row.get(0),
    )
    .expect("count delete outbox rows")
}

fn count_tombstones(conn: &rusqlite::Connection, entity_type: &str, entity_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_tombstones
         WHERE entity_type = ?1 AND entity_id = ?2",
        params![entity_type, entity_id],
        |row| row.get(0),
    )
    .expect("count tombstones")
}

/// helper: load the most-recent DELETE envelope payload
/// for an `(entity_type, entity_id)` pair. Used by the H2/H3
/// regressions to assert the payload carries `version` +
/// `created_at` rather than the legacy `{id}`-only /
/// `{updated_at}`-only shape.
fn read_delete_envelope_payload(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
) -> serde_json::Value {
    let raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete' \
             ORDER BY id DESC LIMIT 1",
            params![entity_type, entity_id],
            |row| row.get(0),
        )
        .expect("load delete envelope payload");
    serde_json::from_str(&raw).expect("parse delete envelope payload")
}

/// every cascaded `task_tag` DELETE
/// envelope ships the pre-delete snapshot (`version` +
/// `created_at`), not the legacy `{task_id, tag_id, updated_at}`
/// shape that defeated peer LWW on the edge tombstone path.
#[test]
fn empty_trash_task_tag_delete_envelope_carries_version_and_created_at() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000052");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000053");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000054");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000052").expect("archive");
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000052'",
        params![&stale_iso],
    )
    .expect("backdate stale archive");
    let child_ids = seed_task_delete_children(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000052",
        "01966a3f-7c8b-7d4e-8f3a-000000000053",
        "01966a3f-7c8b-7d4e-8f3a-000000000054",
    );

    empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");

    let payload = read_delete_envelope_payload(
        &conn,
        lorvex_domain::naming::EDGE_TASK_TAG,
        child_ids.tag_edge_id.as_str(),
    );
    assert!(
        payload.get("version").and_then(|v| v.as_str()).is_some(),
        "task_tag delete payload must carry pre-delete `version` (got {payload})"
    );
    assert!(
        payload.get("created_at").and_then(|v| v.as_str()).is_some(),
        "task_tag delete payload must carry pre-delete `created_at` (got {payload})"
    );
    assert_eq!(
        payload.get("task_id").and_then(|v| v.as_str()),
        Some("01966a3f-7c8b-7d4e-8f3a-000000000052"),
        "task_tag delete payload must include task_id"
    );
}

/// every cascaded
/// `task_calendar_event_link` DELETE envelope ships the pre-delete
/// snapshot (`version` + `created_at` + `updated_at`), not the
/// legacy `{task_id, calendar_event_id, updated_at}` shape.
#[test]
fn empty_trash_task_calendar_event_link_delete_envelope_carries_version_and_created_at() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000055");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000056");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000057");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000055").expect("archive");
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000055'",
        params![&stale_iso],
    )
    .expect("backdate stale archive");
    let child_ids = seed_task_delete_children(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000055",
        "01966a3f-7c8b-7d4e-8f3a-000000000056",
        "01966a3f-7c8b-7d4e-8f3a-000000000057",
    );

    empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");

    let payload = read_delete_envelope_payload(
        &conn,
        lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        child_ids.calendar_link_edge_id.as_str(),
    );
    assert!(
        payload.get("version").and_then(|v| v.as_str()).is_some(),
        "task_calendar_event_link delete payload must carry pre-delete `version` (got {payload})"
    );
    assert!(
        payload.get("created_at").and_then(|v| v.as_str()).is_some(),
        "task_calendar_event_link delete payload must carry pre-delete `created_at` (got {payload})"
    );
    assert!(
        payload.get("updated_at").and_then(|v| v.as_str()).is_some(),
        "task_calendar_event_link delete payload must carry pre-delete `updated_at` (got {payload})"
    );
}

#[test]
fn archive_task_sets_archived_at_and_enqueues_upsert() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000003d");

    let task = archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000003d")
        .expect("archive should succeed");
    assert!(task.archived_at.is_some(), "archived_at must be set");
    assert!(task_archived_at(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000003d").is_some());

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000003d'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert!(outbox_count >= 1, "archive must emit a sync envelope");
}

#[test]
fn archive_task_rejects_already_archived() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000047");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000047").expect("first archive");
    let err = archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000047")
        .expect_err("double-archive must fail");
    assert!(matches!(err, AppError::Validation(_)));
}

#[test]
fn restore_task_clears_archived_at() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006c");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006c").expect("archive");

    let task = restore_task_from_trash_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006c")
        .expect("restore");
    assert!(task.archived_at.is_none());
    assert!(task_archived_at(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006c").is_none());
}

#[test]
fn restore_task_rejects_non_archived() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000060");
    let err = restore_task_from_trash_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000060")
        .expect_err("restoring a live task must fail");
    assert!(matches!(err, AppError::Validation(_)));
}

#[test]
fn empty_trash_purges_only_rows_older_than_retention() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000050");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000078");
    // Fresh archive (now).
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000050").expect("archive fresh");
    // Stale archive — backdated to 31 days ago so it falls outside
    // the 30-day retention window.
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000078'",
        params![&stale_iso],
    )
    .expect("backdate stale archive");

    let result = empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");
    assert_eq!(result.deleted, 1, "only the stale row should be purged");
    assert_eq!(
        result.deleted_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000078".to_string()]
    );

    let fresh_still_there: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000050'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(fresh_still_there, 1);
    let stale_gone: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000078'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stale_gone, 0);
    let audit_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count app audit rows");
    assert_eq!(
        audit_count, 0,
        "app-originated Empty Trash must not persist ai_changelog rows"
    );
}

#[test]
fn empty_trash_with_empty_window_is_noop() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000063");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000063").expect("archive");

    let result = empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");
    assert_eq!(result.deleted, 0);
    assert_eq!(result.remaining, 1);
}

#[test]
fn startup_trash_purge_writes_diagnostic_not_ai_changelog() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000078");
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000078'",
        params![&stale_iso],
    )
    .expect("backdate stale archive");

    run_startup_trash_purge(&conn);

    let changelog_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count startup changelog rows");
    assert_eq!(
        changelog_count, 0,
        "startup trash purge is Tauri maintenance and must not write ai_changelog"
    );

    let diagnostic_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'maintenance.startup_trash_purge.purged'
               AND level = 'info'
               AND details LIKE '%01966a3f-7c8b-7d4e-8f3a-000000000078%'",
            [],
            |row| row.get(0),
        )
        .expect("count startup diagnostic rows");
    assert_eq!(diagnostic_count, 1);
}

#[test]
fn startup_trash_purge_success_persists_structured_diagnostic() {
    let conn = test_conn();
    let report = lorvex_sync::startup_trash_purge::StartupTrashPurgeReport {
        deleted: 2,
        deleted_ids: vec![
            "01966a3f-7c8b-7d4e-8f3a-000000000062".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000080".to_string(),
        ],
        remaining: 3,
    };

    log_startup_trash_purge_report(&conn, &report);

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'maintenance.startup_trash_purge.purged'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read startup trash purge diagnostic");

    assert_eq!(row.0, "maintenance.startup_trash_purge.purged");
    assert_eq!(row.1, "info");
    assert_eq!(row.2, "Startup trash purge hard-deleted expired tasks");
    assert!(row.3.contains("deleted=2"));
    assert!(row.3.contains("remaining=3"));
    assert!(row.3.contains("01966a3f-7c8b-7d4e-8f3a-000000000062"));
    assert!(row.3.contains("01966a3f-7c8b-7d4e-8f3a-000000000080"));
}

#[test]
fn startup_trash_purge_failure_persists_structured_diagnostic() {
    let conn = test_conn();

    log_startup_trash_purge_failure(&conn, "purge failed: fixture");

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'maintenance.startup_trash_purge.failed'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read startup trash purge failure diagnostic");

    assert_eq!(row.0, "maintenance.startup_trash_purge.failed");
    assert_eq!(row.1, "warn");
    assert_eq!(row.2, "Startup trash purge failed");
    assert!(row.3.contains("purge failed: fixture"));
}

#[test]
fn empty_trash_emits_child_delete_envelopes_and_tombstones() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000079");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007b");
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007c");
    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000079").expect("archive");
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    conn.execute(
        "UPDATE tasks SET archived_at = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000079'",
        params![&stale_iso],
    )
    .expect("backdate stale archive");
    let child_ids = seed_task_delete_children(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000079",
        "01966a3f-7c8b-7d4e-8f3a-00000000007b",
        "01966a3f-7c8b-7d4e-8f3a-00000000007c",
    );

    let result = empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");
    assert_eq!(result.deleted, 1);
    assert_eq!(
        result.deleted_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000079".to_string()]
    );

    let expected = [
        (
            lorvex_domain::naming::EDGE_TASK_TAG,
            child_ids.tag_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::ENTITY_TASK_CHECKLIST_ITEM,
            child_ids.checklist_item_id.as_str(),
        ),
        (
            lorvex_domain::naming::ENTITY_TASK_REMINDER,
            child_ids.reminder_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
            child_ids.calendar_link_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.outgoing_dep_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.incoming_dep_edge_id.as_str(),
        ),
    ];

    for (entity_type, entity_id) in expected {
        assert!(
            count_delete_outbox(&conn, entity_type, entity_id) >= 1,
            "expected delete outbox row for {entity_type}/{entity_id}"
        );
        assert_eq!(
            count_tombstones(&conn, entity_type, entity_id),
            1,
            "expected tombstone for {entity_type}/{entity_id}"
        );
    }

    let dependent_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000007b'
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count dependent task upserts");
    assert_eq!(
        dependent_upserts, 1,
        "empty_trash dependency cleanup must sync the dependent task aggregate"
    );
}

#[test]
fn archive_removes_task_from_current_focus_items() {
    let conn = test_conn();
    seed_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004f");
    conn.execute(
        "INSERT OR IGNORE INTO current_focus (date, briefing, version, created_at, updated_at) \
         VALUES ('2026-04-18', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-18T00:00:00Z', '2026-04-18T00:00:00Z')",
        [],
    )
    .expect("seed current_focus row");
    conn.execute(
        "INSERT INTO current_focus_items (date, task_id, position) \
         VALUES ('2026-04-18', '01966a3f-7c8b-7d4e-8f3a-00000000004f', 0)",
        [],
    )
    .expect("seed focus item");

    archive_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004f").expect("archive");

    let focus_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-00000000004f'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        focus_count, 0,
        "archived task must be removed from current_focus_items"
    );
}

/// hard-deleting an expired Trash row
/// via `empty_trash_with_conn` MUST re-enqueue parent-aggregate
/// upserts for every `current_focus` and `focus_schedule` day the
/// task touched. Pre-fix the inline DELETE wiped the local rows
/// without telling peers, so peers' plan aggregates kept pointing
/// at the hard-deleted task. The fix routes through
/// `removal::cleanup_plan_refs_after_removal` which collects the
/// affected dates BEFORE the DELETE and emits parent-aggregate
/// upsert envelopes for each.
///
/// To isolate the empty_trash code path we seed an
/// already-archived task directly and re-attach plan-ref rows to
/// it. Going through `archive_task_with_conn` first would empty
/// the plan-ref rows during archive (its own copy of the helper)
/// and leave nothing for `empty_trash` to react to — but the
/// production hard-delete path is reachable for ANY task whose
/// `archived_at` is older than retention, regardless of how it
/// got there. A peer-applied archive envelope, an external
/// migration, or a recovery script can all leave the row in this
/// shape.
#[test]
fn empty_trash_reenqueues_parent_aggregate_upserts_for_focus_and_schedule_days() {
    let conn = test_conn();

    // Seed an already-archived task whose archived_at is older
    // than retention — this mirrors a row that reached the Trash
    // via a peer-applied envelope, NOT via local archive_task.
    let stale_iso = (chrono::Utc::now() - chrono::Duration::days(31))
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000059")
        .title("Trash me")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-01T00:00:00Z")
        .list_id(Some("inbox"))
        .archived_at(Some(&stale_iso))
        .insert(&conn);

    // Seed parent-aggregate rows for both date-keyed surfaces with
    // live plan-ref rows pointing at the doomed task.
    conn.execute(
        "INSERT OR IGNORE INTO current_focus (date, briefing, version, created_at, updated_at) \
         VALUES ('2026-04-18', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-18T00:00:00Z', '2026-04-18T00:00:00Z')",
        [],
    )
    .expect("seed current_focus row");
    conn.execute(
        "INSERT INTO current_focus_items (date, task_id, position) \
         VALUES ('2026-04-18', '01966a3f-7c8b-7d4e-8f3a-000000000059', 0)",
        [],
    )
    .expect("seed focus item");
    conn.execute(
        "INSERT OR IGNORE INTO focus_schedule (date, version, created_at, updated_at) \
         VALUES ('2026-04-19', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-19T00:00:00Z', '2026-04-19T00:00:00Z')",
        [],
    )
    .expect("seed focus_schedule row");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
            (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES ('2026-04-19', 0, 'task', 540, 600, '01966a3f-7c8b-7d4e-8f3a-000000000059')",
        [],
    )
    .expect("seed focus_schedule block");

    let result = empty_trash_with_conn(&conn, TRASH_RETENTION_DAYS).expect("empty_trash");
    assert_eq!(result.deleted, 1, "stale archived row should be purged");

    // Post-fix expectation: at least one parent-aggregate upsert
    // envelope per affected day must have been enqueued. The
    // `entity_id` for date-keyed aggregates is the date string.
    let current_focus_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'current_focus' AND operation = 'upsert' \
               AND entity_id = '2026-04-18'",
            [],
            |row| row.get(0),
        )
        .expect("count current_focus envelopes for affected day");
    assert!(
        current_focus_after >= 1,
        "empty_trash must enqueue a current_focus parent-aggregate upsert for 2026-04-18 (got {current_focus_after})"
    );
    let focus_schedule_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'focus_schedule' AND operation = 'upsert' \
               AND entity_id = '2026-04-19'",
            [],
            |row| row.get(0),
        )
        .expect("count focus_schedule envelopes for affected day");
    assert!(
        focus_schedule_after >= 1,
        "empty_trash must enqueue a focus_schedule parent-aggregate upsert for 2026-04-19 (got {focus_schedule_after})"
    );

    // Sanity: the local rows are gone (this preserves the existing
    // behavior covered by `archive_removes_task_from_current_focus_items`).
    let live_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000059'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(live_items, 0);
    let live_blocks: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000059'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(live_blocks, 0);
}
