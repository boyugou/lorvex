use rusqlite::Connection;

use crate::commands::tasks::{fetch_task_by_id, AppError, Task};

use super::tokens::UndoToken;

/// Restore the pre-mutation state of an `update_task` by replaying
/// `update_task_internal` with the snapshot (#2538).
///
/// Semantics:
/// 1. Validate and rebuild the update patch from the snapshot before
///    any mutation.
/// 2. Dispatch through `update_task_internal` so the restored row goes
///    through identical validation, tag-diffing, dependency-cycle
///    checks, and recurrence normalization as the forward mutation —
///    and enqueues a fresh upsert that LWW-beats the forward version
///    on peers.
pub(super) fn apply_update_undo(
    conn: &Connection,
    undo: &UndoToken,
    now: &str,
) -> Result<Task, AppError> {
    let snapshot = undo.pre_task_snapshot.as_ref().ok_or_else(|| {
        AppError::Validation("Update undo token is missing pre_task_snapshot".to_string())
    })?;
    let snapshot_obj = snapshot.as_object().ok_or_else(|| {
        AppError::Validation("Update undo snapshot is not a JSON object".to_string())
    })?;

    // Confirm the task still exists locally. A concurrent delete
    // between the mutation and the undo surfaces a clean NotFound
    // rather than a silent ghost write.
    let current = fetch_task_by_id(conn, &undo.task_id)?;

    let patch_value = build_update_undo_patch(snapshot_obj, &current)?;

    let restored = super::super::update_task_internal(conn, &undo.task_id, &patch_value, now)?;

    Ok(restored)
}

/// Field set the update-undo replay rebuilds from a pre-mutation `Task`
/// snapshot. Mirrors the renderer's `update_task` wire shape (i.e. the
/// `tags` array form) so [`super::super::updates::update_task_internal`]
/// can translate `tags → tags_set` at its IPC boundary along with every
/// other live update path. Excludes purely write-time controls like
/// `tags_add`/`tags_remove`/`raw_input`, which the snapshot does not
/// carry.
const UPDATE_UNDO_SNAPSHOT_FIELDS: &[&str] = &[
    "title",
    "body",
    "ai_notes",
    "status",
    "list_id",
    "tags",
    "priority",
    "due_date",
    "due_time",
    "planned_date",
    "estimated_minutes",
    "recurrence",
    "depends_on",
];

fn build_update_undo_patch(
    snapshot_obj: &serde_json::Map<String, serde_json::Value>,
    current: &Task,
) -> Result<serde_json::Value, AppError> {
    let mut patch = serde_json::Map::new();
    for field in UPDATE_UNDO_SNAPSHOT_FIELDS {
        let value = update_undo_snapshot_value(snapshot_obj, field)?;
        patch.insert((*field).to_string(), value);
    }

    // `title` is required (non-null) and `list_id` cannot be cleared:
    // if the snapshot somehow lost them, fall back to the current row's
    // values to avoid a validation error inside `update_task_internal`.
    if patch.get("title").is_none_or(serde_json::Value::is_null) {
        patch.insert(
            "title".to_string(),
            serde_json::Value::String(current.title.clone()),
        );
    }
    if patch.get("list_id").is_none_or(serde_json::Value::is_null) {
        patch.insert(
            "list_id".to_string(),
            serde_json::Value::String(current.list_id.clone()),
        );
    }

    Ok(serde_json::Value::Object(patch))
}

fn update_undo_snapshot_value(
    snapshot_obj: &serde_json::Map<String, serde_json::Value>,
    field: &str,
) -> Result<serde_json::Value, AppError> {
    let value = snapshot_obj
        .get(field)
        .cloned()
        .unwrap_or(serde_json::Value::Null);
    if field == "recurrence" {
        return decode_update_undo_recurrence(value);
    }
    Ok(value)
}

/// The undo snapshot stores `recurrence` as the DB-canonical JSON
/// string (mirroring `Task.recurrence: Option<String>`). The update
/// boundary accepts either form, but we decode here so a malformed
/// snapshot fails cleanly at validation, before any mutation runs.
fn decode_update_undo_recurrence(value: serde_json::Value) -> Result<serde_json::Value, AppError> {
    match value {
        serde_json::Value::String(rule) => serde_json::from_str::<serde_json::Value>(&rule)
            .map_err(|e| {
                AppError::Validation(format!(
                    "Update undo snapshot contains malformed recurrence JSON: {e}"
                ))
            }),
        other => Ok(other),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_domain::naming::TaskStatus;
    use rusqlite::params;

    use crate::commands::tasks::undo::LifecycleAction;
    use crate::test_support::test_conn;

    const TEST_VER: &str = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    const NOW_TS: &str = "2026-04-18T09:00:00.000000Z";

    #[test]
    fn rejects_malformed_snapshot_recurrence_without_mutating() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000024', 'Default', ?1, ?2, ?2)",
            params![TEST_VER, NOW_TS],
        )
        .unwrap();
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000013",
        )
        .title("Current")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .insert(&conn);

        let undo = UndoToken {
            task_id: "01966a3f-7c8b-7d4e-8f3a-000000000013".to_string(),
            action: LifecycleAction::Update,
            cancel_series: false,
            pre_status: TaskStatus::Open,
            pre_completed_at: None,
            pre_planned_date: None,
            pre_defer_count: 0,
            pre_last_deferred_at: None,
            pre_last_defer_reason: None,
            spawned_successor_id: None,
            cancelled_reminder_ids: vec![],
            deleted_dep_edges: vec![],
            affected_dependent_ids: vec![],
            expires_at: (chrono::Utc::now() + chrono::Duration::seconds(60))
                .to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
            pre_task_snapshot: Some(serde_json::json!({
                "title": "Original",
                "status": "open",
                "list_id": "01966a3f-7c8b-7d4e-8f3a-000000000024",
                "recurrence": "{not-json"
            })),
        };

        let err = apply_update_undo(&conn, &undo, NOW_TS)
            .expect_err("malformed recurrence snapshot must reject");
        match err {
            AppError::Validation(message) => assert!(
                message.contains("malformed recurrence JSON"),
                "unexpected: {message}"
            ),
            other => panic!("expected Validation, got {other:?}"),
        }

        // The rejection fires at snapshot validation — no reverse-write
        // upsert may have been enqueued for the task.
        let enqueued: i64 = conn
            .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
            .unwrap();
        assert_eq!(
            enqueued, 0,
            "invalid update undo token must fail before enqueueing any reverse write"
        );

        let title: String = conn
            .query_row(
                "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000013'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(title, "Current", "task row must be untouched");
    }
}
