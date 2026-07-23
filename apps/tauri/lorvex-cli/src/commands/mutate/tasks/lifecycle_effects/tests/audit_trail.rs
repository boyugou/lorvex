use super::super::*;
use super::support::*;

/// end-to-end regression test for the CLI audit-trail
/// before/after snapshot threading and the cascade-tombstone full payload
/// fix. Three phases:
/// 1. **Capture** — capture creates a task; `ai_changelog.after_json` must
///    be a non-null typed shape, `before_json` must be NULL (creates have no
///    before-state).
/// 2. **Update** — `update_task_with_conn` patches the title;
///    `ai_changelog.before_json` carries the pre-update title and
///    `after_json` carries the post-update title.
/// 3. **Permanent delete with cascade** — every cascade tombstone in
///    `sync_outbox` ships a typed payload (NOT the empty `{}` sentinel
///    that #2939-H2 fixed). For task_tags / task_checklist_items /
///    task_reminders / task_calendar_event_links / task_dependencies
///    the JSON object must contain the row's identifying keys.
#[test]
fn cli_audit_trail_threads_before_after_and_cascade_tombstones() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    use crate::commands::mutate::tasks::capture_effects::{
        create_captured_task_with_conn, CaptureTaskOptions,
    };
    use crate::commands::mutate::tasks::lifecycle_effects::{
        archive_task_with_conn, permanent_delete_task_with_conn, update_task_with_conn,
    };

    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    // Phase 1: capture.
    let task_id = create_captured_task_with_conn(
        &mut conn,
        "Audit-trail probe",
        CaptureTaskOptions::default(),
    )
    .expect("capture task");

    let (create_before, create_after): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT before_json, after_json FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'create'",
            [ENTITY_TASK, task_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read create changelog");
    assert!(
        create_before.is_none(),
        "create-path before_json must be NULL (no pre-state)"
    );
    let create_after_json: serde_json::Value =
        serde_json::from_str(&create_after.expect("create after_json must be populated"))
            .expect("parse create after_json");
    assert_eq!(
        create_after_json.get("id").and_then(|v| v.as_str()),
        Some(task_id.as_str())
    );
    assert_eq!(
        create_after_json.get("title").and_then(|v| v.as_str()),
        Some("Audit-trail probe")
    );

    // Phase 2: update — assert before/after carry the title transition.
    update_task_with_conn(
        &mut conn,
        &tid(&task_id),
        &TaskUpdateFields {
            title: Some("Audit-trail probe v2"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("update task");
    let (update_before, update_after): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT before_json, after_json FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'update'",
            [ENTITY_TASK, task_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read update changelog");
    let before_value: serde_json::Value =
        serde_json::from_str(&update_before.expect("update before_json must be populated"))
            .expect("parse update before_json");
    let after_value: serde_json::Value =
        serde_json::from_str(&update_after.expect("update after_json must be populated"))
            .expect("parse update after_json");
    assert_eq!(
        before_value.get("title").and_then(|v| v.as_str()),
        Some("Audit-trail probe")
    );
    assert_eq!(
        after_value.get("title").and_then(|v| v.as_str()),
        Some("Audit-trail probe v2")
    );

    // Phase 3: cascade-delete payload check. Seed the four cascade child
    // types directly so the tombstone payloads are observable without
    // exercising every CLI mutator.
    let tag_id = "01949c00-0000-7000-8000-000000000074";
    let checklist_id = "01949c00-0000-7000-8000-000000000075";
    let reminder_id = "01949c00-0000-7000-8000-000000000076";
    let calendar_event_id = "01949c00-0000-7000-8000-000000000077";
    let dependency_target_id = "01949c00-0000-7000-8000-000000000078";
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Audit Tag', 'audit-tag', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [tag_id],
    )
    .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [&task_id, tag_id],
    )
    .expect("seed task_tag");
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, completed_at, version, created_at, updated_at)
         VALUES (?1, ?2, 1, 'subitem', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [checklist_id, &task_id],
    )
    .expect("seed checklist");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-05-01T13:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [reminder_id, &task_id],
    )
    .expect("seed reminder");
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES (?1, 'Audit event', '2026-05-01', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [calendar_event_id],
    )
    .expect("seed event");
    conn.execute(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [&task_id, calendar_event_id],
    )
    .expect("seed event link");
    seed_task(&conn, dependency_target_id, "Dep target", "open");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [&task_id, dependency_target_id],
    )
    .expect("seed dependency");

    archive_task_with_conn(&conn, &tid(&task_id)).expect("archive");
    permanent_delete_task_with_conn(&mut conn, &tid(&task_id), false).expect("permanent delete");

    // Each cascade tombstone must ship a TYPED payload (not `{}`).
    let assert_cascade_payload = |entity_type: &str, entity_id: &str, required_keys: &[&str]| {
        let payload_str: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox
                     WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![entity_type, entity_id, OP_DELETE],
                |row| row.get(0),
            )
            .unwrap_or_else(|err| {
                panic!("no delete tombstone in sync_outbox for {entity_type} / {entity_id}: {err}")
            });
        let payload: serde_json::Value =
            serde_json::from_str(&payload_str).expect("parse cascade payload");
        assert_ne!(
            payload,
            serde_json::json!({}),
            "cascade tombstone for {entity_type} / {entity_id} must NOT be empty `{{}}`"
        );
        for key in required_keys {
            assert!(
                payload.get(*key).is_some(),
                "cascade tombstone for {entity_type} / {entity_id} missing key '{key}': {payload}"
            );
        }
    };

    assert_cascade_payload(
        EDGE_TASK_TAG,
        &format!("{task_id}:{tag_id}"),
        &["task_id", "tag_id", "version"],
    );
    assert_cascade_payload(
        ENTITY_TASK_CHECKLIST_ITEM,
        checklist_id,
        &["id", "task_id", "text", "position", "version"],
    );
    assert_cascade_payload(
        ENTITY_TASK_REMINDER,
        reminder_id,
        &["id", "task_id", "reminder_at", "version"],
    );
    assert_cascade_payload(
        EDGE_TASK_CALENDAR_EVENT_LINK,
        &format!("{task_id}:{calendar_event_id}"),
        &["task_id", "calendar_event_id", "version"],
    );
    assert_cascade_payload(
        EDGE_TASK_DEPENDENCY,
        &format!("{task_id}:{dependency_target_id}"),
        &["task_id", "depends_on_task_id", "version"],
    );

    // The parent task tombstone must also carry a typed payload.
    let task_tombstone: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK, task_id, OP_DELETE],
            |row| row.get(0),
        )
        .expect("task tombstone payload");
    let task_payload: serde_json::Value =
        serde_json::from_str(&task_tombstone).expect("parse task tombstone");
    assert_ne!(
        task_payload,
        serde_json::json!({}),
        "task tombstone must carry the pre-delete row, not `{{}}`"
    );
    assert_eq!(
        task_payload.get("id").and_then(|v| v.as_str()),
        Some(task_id.as_str())
    );

    // The delete changelog row must also carry the pre-delete task as
    // `before_json` (audit-trail H1).
    let delete_before: Option<String> = conn
        .query_row(
            "SELECT before_json FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK, task_id, OP_DELETE],
            |row| row.get(0),
        )
        .expect("delete changelog row");
    let delete_before_value: serde_json::Value =
        serde_json::from_str(&delete_before.expect("delete before_json populated"))
            .expect("parse delete before_json");
    assert_eq!(
        delete_before_value.get("id").and_then(|v| v.as_str()),
        Some(task_id.as_str())
    );
}
