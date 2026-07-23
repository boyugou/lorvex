use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::error::{AppError, AppResult};
#[cfg(test)]
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::naming::{EDGE_TASK_DEPENDENCY, OP_DELETE, OP_UPSERT};
use lorvex_domain::TaskId;
use lorvex_workflow::task_dependency_edges::{
    AddTaskDependencyMutation, DependencyEdgePrecheck, RemoveTaskDependencyMutation,
};

struct TaskDependencyWriteOutcome {
    task: crate::commands::Task,
    changed: bool,
}

/// Atomically add a single dependency edge (task_id depends on depends_on_task_id).
/// Validates both tasks exist, rejects self-dependency, and checks for cycles.
/// Returns the updated task.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_task_dependency(
    task_id: String,
    depends_on_task_id: String,
) -> Result<crate::commands::Task, String> {
    // both ids are UUIDv7 — shape-check before the
    // edge writer so the composite `entity_id` (task:dep) carried in
    // sync envelopes never holds a malformed half.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let depends_on_task_id_str =
        crate::commands::shared::validate_uuid_id(&depends_on_task_id, "depends_on_task_id")?;
    let task_id = TaskId::from_trusted(task_id_str);
    let depends_on_task_id = TaskId::from_trusted(depends_on_task_id_str);
    add_task_dependency_inner(&task_id, &depends_on_task_id).map_err(String::from)
}

fn add_task_dependency_inner(
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> AppResult<crate::commands::Task> {
    let conn = crate::db::get_conn()?;
    let outcome = add_task_dependency_with_conn(&conn, task_id, depends_on_task_id)?;
    if outcome.changed {
        crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);
    }
    Ok(outcome.task)
}

/// Testable entry point — runs the same transactional body as
/// `add_task_dependency_inner` but against a caller-supplied
/// connection so regression tests can assert both the dependency-edge
/// envelope payload and the app mutation sequence contract.
fn add_task_dependency_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> AppResult<TaskDependencyWriteOutcome> {
    if task_id == depends_on_task_id {
        return Err(AppError::Validation(
            "A task cannot depend on itself".to_string(),
        ));
    }

    lorvex_store::with_immediate_transaction(conn, |conn| {
        // Validate-task-existence + cycle guard run here (not on the
        // workflow descriptor) because they need the surface's
        // `fetch_task_by_id` helper and the surface's typed AppError
        // mapping — the workflow crate intentionally doesn't depend on
        // either. Everything below this point (idempotency probe,
        // payload assembly, edge mutation) flows through the descriptor.
        crate::commands::fetch_task_by_id(conn, task_id.as_str())?;
        crate::commands::fetch_task_by_id(conn, depends_on_task_id.as_str())?;
        lorvex_workflow::dependency_validation::validate_no_dependency_cycle(
            conn,
            task_id,
            &[depends_on_task_id.as_str().to_string()],
        )
        .map_err(AppError::from)?;

        let now = crate::commands::sync_timestamp_now();
        let mutation = AddTaskDependencyMutation {
            task_id,
            depends_on_task_id,
            now: &now,
        };
        // Idempotency probe lives on the descriptor — duplicate-add
        // returns NoOp and we skip HLC mint, outbox traffic, audit,
        // and the `local_change_seq` bump entirely.
        match mutation.pre_apply_check(conn).map_err(AppError::from)? {
            DependencyEdgePrecheck::NoOp => Ok(TaskDependencyWriteOutcome {
                task: crate::commands::fetch_task_by_id(conn, task_id.as_str())?,
                changed: false,
            }),
            DependencyEdgePrecheck::Proceed { .. } => {
                let entity_id = mutation.entity_id();
                execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
                    let payload = mutation.payload_for_envelope(&execution.output);
                    crate::commands::enqueue_to_outbox_typed(
                        conn,
                        EDGE_TASK_DEPENDENCY,
                        entity_id.as_str(),
                        OP_UPSERT,
                        &payload,
                    )?;
                    // Re-stamp the parent task version so peers see the
                    // dependency change as a coherent task update. Lives
                    // in the surface because it needs the surface's
                    // typed Task row.
                    let task = crate::commands::fetch_task_by_id(conn, task_id.as_str())?;
                    crate::commands::enqueue_task_upsert(conn, &task)?;
                    Ok(())
                })?;
                Ok(TaskDependencyWriteOutcome {
                    task: crate::commands::fetch_task_by_id(conn, task_id.as_str())?,
                    changed: true,
                })
            }
        }
    })
}

/// Atomically remove a single dependency edge (task_id no longer depends on depends_on_task_id).
/// Returns the updated task.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn remove_task_dependency(
    task_id: String,
    depends_on_task_id: String,
) -> Result<crate::commands::Task, String> {
    // shape-check both UUIDv7 ids at the IPC boundary
    // so the delete edge writer never enqueues a malformed composite
    // `entity_id`.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let depends_on_task_id_str =
        crate::commands::shared::validate_uuid_id(&depends_on_task_id, "depends_on_task_id")?;
    let task_id = TaskId::from_trusted(task_id_str);
    let depends_on_task_id = TaskId::from_trusted(depends_on_task_id_str);
    remove_task_dependency_inner(&task_id, &depends_on_task_id).map_err(String::from)
}

fn remove_task_dependency_inner(
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> AppResult<crate::commands::Task> {
    let conn = crate::db::get_conn()?;
    let outcome = remove_task_dependency_with_conn(&conn, task_id, depends_on_task_id)?;
    if outcome.changed {
        crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);
    }
    Ok(outcome.task)
}

/// Testable entry point — runs the same transactional body as
/// `remove_task_dependency_inner` but against a caller-supplied
/// connection so regression tests can assert both the dependency-edge
/// delete payload and the app mutation sequence contract.
fn remove_task_dependency_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
) -> AppResult<TaskDependencyWriteOutcome> {
    lorvex_store::with_immediate_transaction(conn, |conn| {
        // Validate-task-existence stays in the surface — needs the
        // surface's typed AppError mapping. Pre-delete probe (loads
        // the `(version, created_at)` tuple the tombstone payload
        // needs for peer LWW) and no-op short-circuit live on the
        // descriptor.
        crate::commands::fetch_task_by_id(conn, task_id.as_str())?;

        let mutation = RemoveTaskDependencyMutation {
            task_id,
            depends_on_task_id,
        };
        match mutation.pre_apply_check(conn).map_err(AppError::from)? {
            DependencyEdgePrecheck::NoOp => Ok(TaskDependencyWriteOutcome {
                task: crate::commands::fetch_task_by_id(conn, task_id.as_str())?,
                changed: false,
            }),
            DependencyEdgePrecheck::Proceed { pre_delete } => {
                let pre_delete = pre_delete.expect(
                    "RemoveTaskDependencyMutation::pre_apply_check returns Proceed only with pre_delete",
                );
                let entity_id = mutation.entity_id();
                execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                    let payload = mutation.payload_for_envelope(&pre_delete);
                    crate::commands::enqueue_to_outbox_typed(
                        conn,
                        EDGE_TASK_DEPENDENCY,
                        entity_id.as_str(),
                        OP_DELETE,
                        &payload,
                    )?;
                    let task = crate::commands::fetch_task_by_id(conn, task_id.as_str())?;
                    crate::commands::enqueue_task_upsert(conn, &task)?;
                    Ok(())
                })?;
                Ok(TaskDependencyWriteOutcome {
                    task: crate::commands::fetch_task_by_id(conn, task_id.as_str())?,
                    changed: true,
                })
            }
        }
    })
}

#[cfg(test)]
mod tests {
    //! Dependency edge envelopes carry `version` + `created_at` on
    //! both upsert (add) and delete (remove), matching the canonical
    //! seed shape for `EDGE_TASK_DEPENDENCY`. Omitting them on
    //! upsert or shipping only the composite-id pair on delete would
    //! leave peer LWW on the edge tombstone path without a
    //! `(version, created_at)` tuple to compare, silently dropping
    //! every concurrent dep mutation.
    use super::*;
    use crate::test_support::test_conn;
    use rusqlite::params;

    fn seed_task(conn: &rusqlite::Connection, id: &str, title: &str) {
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(id)
            .title(title)
            .list_id(Some("inbox"))
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-04-01T08:00:00Z")
            .insert(conn);
    }

    fn read_envelope_payload(
        conn: &rusqlite::Connection,
        entity_id: &str,
        operation: &str,
    ) -> serde_json::Value {
        let raw: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox \
                 WHERE entity_type = 'task_dependency' AND entity_id = ?1 AND operation = ?2 \
                 ORDER BY id DESC LIMIT 1",
                params![entity_id, operation],
                |row| row.get(0),
            )
            .expect("load task_dependency envelope payload");
        serde_json::from_str(&raw).expect("parse task_dependency envelope payload")
    }

    fn read_unsynced_outbox_row(
        conn: &rusqlite::Connection,
        entity_type: &str,
        entity_id: &str,
    ) -> (String, String, String) {
        conn.query_row(
            "SELECT operation, version, payload FROM sync_outbox \
             WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NULL \
             LIMIT 1",
            params![entity_type, entity_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load unsynced outbox row")
    }

    fn count_unsynced_outbox_rows(conn: &rusqlite::Connection) -> i64 {
        conn.query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count unsynced outbox rows")
    }

    fn read_local_change_seq(conn: &rusqlite::Connection) -> u64 {
        lorvex_runtime::read_local_change_seq(conn).expect("read local_change_seq")
    }

    #[test]
    fn add_task_dependency_bumps_local_change_seq_once() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006e", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006f", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000006e".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000006f".to_string());
        let seq_before = read_local_change_seq(&conn);

        let outcome = add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");

        assert!(outcome.changed, "first dependency add must report a write");
        assert_eq!(
            read_local_change_seq(&conn),
            seq_before + 1,
            "real dependency add must bump local_change_seq exactly once"
        );
    }

    #[test]
    fn duplicate_add_task_dependency_does_not_bump_local_change_seq() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000070", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000071", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000070".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000071".to_string());
        let seq_before = read_local_change_seq(&conn);

        let first_outcome =
            add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");
        let seq_after_add = read_local_change_seq(&conn);
        let duplicate_outcome =
            add_task_dependency_with_conn(&conn, &task, &dependency).expect("duplicate add dep");

        assert!(
            first_outcome.changed,
            "first dependency add must report a write"
        );
        assert_eq!(
            seq_after_add,
            seq_before + 1,
            "real dependency add must bump local_change_seq exactly once"
        );
        assert!(
            !duplicate_outcome.changed,
            "duplicate dependency add must report a no-op"
        );
        assert_eq!(
            read_local_change_seq(&conn),
            seq_after_add,
            "duplicate dependency add must not bump local_change_seq"
        );
    }

    #[test]
    fn remove_task_dependency_bumps_local_change_seq_once() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000074", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000075", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000074".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000075".to_string());
        add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");
        let seq_before_remove = read_local_change_seq(&conn);

        let outcome =
            remove_task_dependency_with_conn(&conn, &task, &dependency).expect("remove dep");

        assert!(
            outcome.changed,
            "existing dependency remove must report a write"
        );
        assert_eq!(
            read_local_change_seq(&conn),
            seq_before_remove + 1,
            "real dependency remove must bump local_change_seq exactly once"
        );
    }

    #[test]
    fn no_op_remove_task_dependency_does_not_bump_local_change_seq() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000072", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000073", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000072".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000073".to_string());
        add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");
        remove_task_dependency_with_conn(&conn, &task, &dependency).expect("remove dep");
        let seq_before_noop = read_local_change_seq(&conn);

        let outcome =
            remove_task_dependency_with_conn(&conn, &task, &dependency).expect("duplicate remove");

        assert!(
            !outcome.changed,
            "removing an already-absent dependency must report a no-op"
        );
        assert_eq!(
            read_local_change_seq(&conn),
            seq_before_noop,
            "no-op dependency remove must not bump local_change_seq"
        );
    }

    #[test]
    fn add_task_dependency_upsert_payload_carries_version_and_created_at() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005a", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005b", "B");

        let outcome = add_task_dependency_with_conn(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000005a".to_string()),
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000005b".to_string()),
        )
        .expect("add dep");
        assert!(outcome.changed, "first dependency add must report a write");

        let payload = read_envelope_payload(
            &conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000005a:01966a3f-7c8b-7d4e-8f3a-00000000005b",
            "upsert",
        );
        assert!(
            payload.get("version").and_then(|v| v.as_str()).is_some(),
            "upsert payload must carry `version` (got {payload})"
        );
        assert!(
            payload.get("created_at").and_then(|v| v.as_str()).is_some(),
            "upsert payload must carry `created_at` (got {payload})"
        );
    }

    #[test]
    fn remove_task_dependency_delete_payload_carries_version_and_created_at() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005c", "C");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005d", "D");
        let t_c = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000005c".to_string());
        let t_d = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000005d".to_string());
        add_task_dependency_with_conn(&conn, &t_c, &t_d).expect("add dep");

        let outcome = remove_task_dependency_with_conn(&conn, &t_c, &t_d).expect("remove dep");
        assert!(
            outcome.changed,
            "existing dependency remove must report a write"
        );

        let payload = read_envelope_payload(
            &conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000005c:01966a3f-7c8b-7d4e-8f3a-00000000005d",
            "delete",
        );
        assert!(
            payload.get("version").and_then(|v| v.as_str()).is_some(),
            "delete payload must carry pre-delete `version` (got {payload})"
        );
        assert!(
            payload.get("created_at").and_then(|v| v.as_str()).is_some(),
            "delete payload must carry pre-delete `created_at` (got {payload})"
        );
    }

    #[test]
    fn duplicate_add_task_dependency_does_not_rewrite_outbox() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004d", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004e", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000004d".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000004e".to_string());

        let first_outcome =
            add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");
        assert!(
            first_outcome.changed,
            "first dependency add must report a write"
        );

        let edge_entity_id =
            "01966a3f-7c8b-7d4e-8f3a-00000000004d:01966a3f-7c8b-7d4e-8f3a-00000000004e";
        let edge_before = read_unsynced_outbox_row(&conn, EDGE_TASK_DEPENDENCY, edge_entity_id);
        let task_before = read_unsynced_outbox_row(&conn, ENTITY_TASK, task.as_str());
        let row_count_before = count_unsynced_outbox_rows(&conn);

        let duplicate_outcome =
            add_task_dependency_with_conn(&conn, &task, &dependency).expect("duplicate add dep");
        assert!(
            !duplicate_outcome.changed,
            "duplicate dependency add must report a no-op"
        );

        assert_eq!(
            count_unsynced_outbox_rows(&conn),
            row_count_before,
            "duplicate add must not enqueue additional sync rows"
        );
        assert_eq!(
            read_unsynced_outbox_row(&conn, EDGE_TASK_DEPENDENCY, edge_entity_id),
            edge_before,
            "duplicate add must not rewrite the queued dependency edge upsert"
        );
        assert_eq!(
            read_unsynced_outbox_row(&conn, ENTITY_TASK, task.as_str()),
            task_before,
            "duplicate add must not rewrite the queued parent task upsert"
        );
    }

    #[test]
    fn remove_task_dependency_propagates_pre_delete_query_errors() {
        // Regression test: the pre-delete `query_row` must only
        // collapse `QueryReturnedNoRows` to `None`; any other rusqlite
        // error (SQLITE_BUSY / IO / corruption) must bubble out as
        // `Err` rather than turning a "remove dep" click into a
        // silent no-op. Force the failure by dropping the
        // `task_dependencies` table so the `SELECT` raises an
        // SQLITE_ERROR (no such table) — the cleanest table-level
        // fault synthesizable in a unit test without a
        // fault-injection harness.
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007a", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007b", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000007a".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000007b".to_string());

        conn.execute("DROP TABLE task_dependencies", [])
            .expect("drop task_dependencies for fault injection");

        let result = remove_task_dependency_with_conn(&conn, &task, &dependency);
        assert!(
            result.is_err(),
            "remove with a broken task_dependencies table must surface the SQL error, \
             not silently short-circuit to a no-op"
        );
    }

    #[test]
    fn no_op_remove_task_dependency_does_not_rewrite_outbox() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000069", "A");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006a", "B");
        let task = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000069".to_string());
        let dependency = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000006a".to_string());

        add_task_dependency_with_conn(&conn, &task, &dependency).expect("add dep");

        let edge_entity_id =
            "01966a3f-7c8b-7d4e-8f3a-000000000069:01966a3f-7c8b-7d4e-8f3a-00000000006a";
        remove_task_dependency_with_conn(&conn, &task, &dependency).expect("remove dep");
        let delete_before = read_unsynced_outbox_row(&conn, EDGE_TASK_DEPENDENCY, edge_entity_id);
        let task_before = read_unsynced_outbox_row(&conn, ENTITY_TASK, task.as_str());
        let row_count_before = count_unsynced_outbox_rows(&conn);

        let noop_outcome =
            remove_task_dependency_with_conn(&conn, &task, &dependency).expect("duplicate remove");
        assert!(
            !noop_outcome.changed,
            "removing an already-absent dependency must report a no-op"
        );
        assert_eq!(
            count_unsynced_outbox_rows(&conn),
            row_count_before,
            "no-op remove must not enqueue additional sync rows"
        );
        assert_eq!(
            read_unsynced_outbox_row(&conn, EDGE_TASK_DEPENDENCY, edge_entity_id),
            delete_before,
            "no-op remove must not rewrite the queued dependency edge delete"
        );
        assert_eq!(
            read_unsynced_outbox_row(&conn, ENTITY_TASK, task.as_str()),
            task_before,
            "no-op remove must not rewrite the queued parent task upsert"
        );
    }
}
