use super::*;
use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::with_db_path_env_for_test;
use tempfile::tempdir;

/// Helper: run a closure with a fresh in-memory-ish DB and the
/// runtime's `DB_PATH` env var pointed at it.
///
/// Acquires the process-wide HLC test mutex up-front so the CLI
/// rate-limit + outbox singletons are serialized against other CLI
/// mutation tests (notably
/// `cli_rate_limit_funnel_rejects_after_hard_cap`, which drains the
/// 500-token bucket and depends on no concurrent test draining tokens
/// in parallel).
fn with_temp_db<F: FnOnce()>(f: F) {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    // Touch the DB so `open_db_at_path` finds it.
    let _conn = open_db_at_path(&db_path).expect("open db");
    let path_string = db_path.display().to_string();
    with_db_path_env_for_test(Some(path_string.as_str()), f);
}

/// Same HLC-mutex acquisition pattern as `with_temp_db`, but exposed as
/// a guard so callers that need to seed the DB before swapping
/// `DB_PATH` (e.g. tests that build a recurring or open task via
/// `TaskBuilder` directly) can hold the mutex across the whole test
/// body.
fn acquire_workflow_test_state() -> crate::commands::shared::test_support::HlcTestState {
    crate::commands::shared::test_support::acquire_hlc_test_state()
}

fn mcp_error_payload(
    kind: &str,
    message: &str,
    retryable: bool,
    docs_hint: Option<&str>,
    entity_id: Option<&str>,
) -> String {
    let mut payload = serde_json::Map::new();
    payload.insert("kind".to_string(), json!(kind));
    payload.insert("message".to_string(), json!(message));
    payload.insert("retryable".to_string(), json!(retryable));
    if let Some(value) = docs_hint {
        payload.insert("docs_hint".to_string(), json!(value));
    }
    if let Some(value) = entity_id {
        payload.insert("entity_id".to_string(), json!(value));
    }
    serde_json::to_string(&Value::Object(payload)).expect("serialize MCP error payload")
}

fn assert_mcp_tool_error(
    error: CliError,
    expected_kind: &str,
    expected_message: &str,
    expected_retryable: bool,
    expected_docs_hint: Option<&str>,
    expected_entity_id: Option<&str>,
) {
    let CliError::McpTool {
        kind,
        message,
        retryable,
        docs_hint,
        entity_id,
    } = error
    else {
        panic!("expected structured MCP tool error, got {error:?}");
    };
    assert_eq!(kind, expected_kind);
    assert_eq!(message, expected_message);
    assert_eq!(retryable, expected_retryable);
    assert_eq!(docs_hint.as_deref(), expected_docs_hint);
    assert_eq!(entity_id.as_deref(), expected_entity_id);
}

#[test]
fn map_public_api_error_decodes_structured_validation_payload() {
    let error = map_public_api_error(mcp_error_payload(
        "validation",
        "title cannot be empty",
        false,
        None,
        None,
    ));

    assert!(matches!(error, CliError::Validation(message) if message == "title cannot be empty"));
}

#[test]
fn map_public_api_error_decodes_structured_not_found_payload_with_entity_id() {
    let error = map_public_api_error(mcp_error_payload(
        "not_found",
        "task 'task-1' not found",
        false,
        None,
        Some("task-1"),
    ));

    assert_mcp_tool_error(
        error,
        "not_found",
        "task 'task-1' not found",
        false,
        None,
        Some("task-1"),
    );
}

#[test]
fn map_public_api_error_decodes_structured_conflict_retry_metadata() {
    let error = map_public_api_error(mcp_error_payload(
        "sync_conflict",
        "task was superseded by a newer version",
        true,
        Some("docs/execution/SYNC_RECOVERY_PLAYBOOK.md"),
        Some("task-2"),
    ));

    assert_mcp_tool_error(
        error,
        "sync_conflict",
        "task was superseded by a newer version",
        true,
        Some("docs/execution/SYNC_RECOVERY_PLAYBOOK.md"),
        Some("task-2"),
    );
}

#[test]
fn map_public_api_error_decodes_structured_retryable_without_entity() {
    let error = map_public_api_error(mcp_error_payload(
        "db_busy",
        "database is locked",
        true,
        Some("docs/design/ARCHITECTURE.md#sqlite-concurrency"),
        None,
    ));

    assert_mcp_tool_error(
        error,
        "db_busy",
        "database is locked",
        true,
        Some("docs/design/ARCHITECTURE.md#sqlite-concurrency"),
        None,
    );
}

#[test]
fn map_public_api_error_preserves_structured_serialization_kind() {
    let error = map_public_api_error(mcp_error_payload(
        "serialization",
        "serialization error: invalid envelope",
        false,
        None,
        None,
    ));

    assert_mcp_tool_error(
        error,
        "serialization",
        "serialization error: invalid envelope",
        false,
        None,
        None,
    );
}

#[test]
fn run_overview_returns_envelope_with_payload_in_json_mode() {
    with_temp_db(|| {
        let out = run_overview(false, OutputFormat::Json).expect("overview");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("workflow.overview"));
        assert!(parsed["payload"].is_object());
        assert!(parsed["payload"]["stats"].is_object());
    });
}

#[test]
fn run_overview_compact_uses_compact_action_key() {
    with_temp_db(|| {
        let out = run_overview(true, OutputFormat::Json).expect("overview compact");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("workflow.overview_compact"));
    });
}

#[test]
fn run_session_context_includes_expected_top_level_keys() {
    with_temp_db(|| {
        let out = run_session_context(OutputFormat::Json).expect("session-context");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("workflow.session_context"));
        for key in ["overview", "current_focus", "today_events", "habits"] {
            assert!(
                parsed["payload"].get(key).is_some(),
                "session-context payload missing key {key}"
            );
        }
    });
}

#[test]
fn run_guide_returns_topic_field() {
    with_temp_db(|| {
        let out = run_guide(Some("getting_started"), OutputFormat::Json).expect("guide");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["payload"]["topic"].as_str(), Some("getting_started"));
    });
}

#[test]
fn run_recent_logs_returns_merged_payload_with_source_counts() {
    with_temp_db(|| {
        let out = run_recent_logs(None, None, &[], &[], false, true, OutputFormat::Json)
            .expect("recent-logs");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert!(parsed["payload"]["source_counts"].is_object());
        assert!(parsed["payload"]["entries"].is_array());
    });
}

#[test]
fn run_analyze_returns_window_days_and_metrics() {
    with_temp_db(|| {
        let out = run_analyze(Some(7), Some(3), OutputFormat::Json).expect("analyze");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["payload"]["window_days"].as_u64(), Some(7));
        assert!(parsed["payload"]["metrics"].is_object());
    });
}

/// Helper: seed a task row directly so we can exercise the
/// checklist/permanent-delete/set-recurrence handlers without
/// reaching for the full create_task pipeline. The seeded row is
/// open + open list assignment and carries a baseline HLC version.
fn seed_open_task(db_path: &std::path::Path, task_id: &str, title: &str) {
    // lift to canonical TaskBuilder.
    let conn = open_db_at_path(db_path).expect("open db");
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title(title)
        .created_at("2026-04-25T00:00:00Z")
        .list_id(Some("inbox"))
        .insert(&conn);
}

#[test]
fn run_checklist_add_returns_updated_task_with_item() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let task_id = "01949c00-0000-7000-8000-000000000001";
    seed_open_task(&db_path, task_id, "Checklist parent");
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out = run_checklist_add(task_id, "First step", None, OutputFormat::Json)
            .expect("checklist add");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("task.checklist_add"));
        assert!(parsed["task"].is_object());
    });
}

#[test]
fn run_set_recurrence_returns_task_envelope() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let task_id = "01949c00-0000-7000-8000-000000000002";
    // set_recurrence requires a due_date so the recurrence-config
    // domain invariant accepts the row.
    // lift to canonical TaskBuilder.
    let conn = open_db_at_path(&db_path).expect("open db");
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title("Standup")
        .created_at("2026-04-25T00:00:00Z")
        .due_date(Some("2026-05-01"))
        .insert(&conn);
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out = run_set_recurrence(
            &SetRecurrenceInputs {
                task_id,
                freq: "daily",
                interval: Some(1),
                byday: &[],
                bymonthday: &[],
                until: None,
                count: None,
            },
            OutputFormat::Json,
        )
        .expect("set recurrence");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("task.set_recurrence"));
        assert!(parsed["task"].is_object());
    });
}

#[test]
fn run_permanent_delete_dry_run_does_not_remove_row() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let task_id = "01949c00-0000-7000-8000-000000000003";
    seed_open_task(&db_path, task_id, "Doomed");
    // Move to trash first so the cascade preconditions are met.
    let trash_conn = open_db_at_path(&db_path).expect("open db");
    trash_conn
        .execute(
            "UPDATE tasks SET archived_at = '2026-04-26T00:00:00Z' WHERE id = ?1",
            [task_id],
        )
        .expect("archive task");
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out = run_permanent_delete(task_id, true, OutputFormat::Json)
            .expect("permanent delete dry-run");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("task.permanent_delete"));
        assert_eq!(parsed["dry_run"].as_bool(), Some(true));
    });
    // Row must still exist after dry-run.
    let after_conn = open_db_at_path(&db_path).expect("open db");
    let count: i64 = after_conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 1, "dry-run must not delete the row");
}

#[test]
fn run_permanent_delete_removes_archived_task_and_logs_delete() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let task_id = "01949c00-0000-7000-8000-000000000079";
    seed_open_task(&db_path, task_id, "Delete for real");
    let trash_conn = open_db_at_path(&db_path).expect("open db");
    trash_conn
        .execute(
            "UPDATE tasks SET archived_at = '2026-04-26T00:00:00Z' WHERE id = ?1",
            [task_id],
        )
        .expect("archive task");

    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out =
            run_permanent_delete(task_id, false, OutputFormat::Json).expect("permanent delete");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("task.permanent_delete"));
        assert_eq!(parsed["dry_run"].as_bool(), Some(false));
        assert_eq!(parsed["result"]["deleted"].as_bool(), Some(true));
    });

    let after_conn = open_db_at_path(&db_path).expect("open db");
    let count: i64 = after_conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count task");
    assert_eq!(count, 0, "non-dry-run must delete the row");
    let changelog_count: i64 = after_conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'permanent_delete'",
            [lorvex_domain::naming::ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count changelog");
    assert_eq!(changelog_count, 1, "delete changelog must be written");
}

#[test]
fn run_habit_completions_returns_per_day_timeline() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let conn = open_db_at_path(&db_path).expect("open db");
    let habit_id = "01949c00-0000-7000-8000-000000000004";
    conn.execute(
        "INSERT INTO habits (id, name, created_at, updated_at, version)
         VALUES (?1, 'Walk', '2026-04-20T00:00:00Z', '2026-04-20T00:00:00Z', \
                 '0000000000000_0000_0000000000000000')",
        [habit_id],
    )
    .expect("seed habit");
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out = run_habit_completions(habit_id, Some(7), OutputFormat::Json)
            .expect("habit completions");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(
            parsed["action"].as_str(),
            Some("workflow.habit_completions")
        );
        assert_eq!(parsed["payload"]["habit_id"].as_str(), Some(habit_id));
        assert!(parsed["payload"]["completions"].is_array());
    });
}

#[test]
fn run_batch_create_persists_when_dry_run_false() {
    with_temp_db(|| {
        let payload = r#"[{"title":"BC1"},{"title":"BC2"}]"#;
        let out = run_batch_create(payload, false, None, false, OutputFormat::Json)
            .expect("batch create");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("task.batch_create"));
        assert_eq!(parsed["dry_run"].as_bool(), Some(false));
        assert!(parsed["result"]["tasks"].is_array());
    });
}

#[test]
fn run_batch_create_dry_run_does_not_persist_rows() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let payload = r#"[{"title":"DR1"}]"#;
        let _out = run_batch_create(payload, false, None, true, OutputFormat::Json)
            .expect("batch create dry-run");
    });
    let conn = open_db_at_path(&db_path).expect("open db");
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE title = 'DR1'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 0, "dry-run must not persist rows");
}

#[test]
fn run_reorganize_priority_strategy_returns_ordered_tasks() {
    let _hlc = acquire_workflow_test_state();
    let dir = tempdir().expect("tempdir");
    let db_path = dir.path().join("db.sqlite");
    let _conn = open_db_at_path(&db_path).expect("open db");
    let conn = open_db_at_path(&db_path).expect("open db");
    for (id, priority) in [
        ("01949c00-0000-7000-8000-000000000010", 3i64),
        ("01949c00-0000-7000-8000-000000000011", 1i64),
        ("01949c00-0000-7000-8000-000000000012", 2i64),
    ] {
        // lift to canonical TaskBuilder.
        let title = format!("T{priority}");
        lorvex_store::test_support::fixtures::TaskBuilder::new(id)
            .title(&title)
            .created_at("2026-04-25T00:00:00Z")
            .list_id(Some("inbox"))
            .priority(Some(priority))
            .insert(&conn);
    }
    with_db_path_env_for_test(Some(db_path.display().to_string().as_str()), || {
        let out = run_reorganize_list("inbox", "priority", &[], false, OutputFormat::Json)
            .expect("reorganize");
        let parsed: Value = serde_json::from_str(&out).expect("valid json");
        assert_eq!(parsed["action"].as_str(), Some("list.reorganize"));
        let tasks = parsed["result"]["tasks"].as_array().expect("tasks array");
        assert_eq!(tasks.len(), 3);
    });
}
