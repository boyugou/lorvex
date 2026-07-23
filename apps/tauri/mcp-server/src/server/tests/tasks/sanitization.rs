//! Regression coverage for MCP lifecycle/batch reason hygiene. Free-form
//! cancel/defer reasons are persisted into `tasks.ai_notes`; they must pass
//! through the canonical user-text sanitizer before any write or summary echo.

use super::*;

const RAW_REASON: &str = "keep\u{1B}[31m\0\u{202E}safe\u{200B}";
const CLEAN_REASON: &str = "keep[31msafe";

fn persisted_ai_notes(server: &LorvexMcpServer, task_id: &str) -> String {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT ai_notes FROM tasks WHERE id = ?1",
                [task_id],
                |row| row.get::<_, String>(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("read persisted ai_notes")
}

fn latest_summary(server: &LorvexMcpServer, tool: &str) -> String {
    server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT summary FROM ai_changelog
                 WHERE mcp_tool = ?1
                 ORDER BY timestamp DESC LIMIT 1",
                [tool],
                |row| row.get::<_, String>(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("read changelog summary")
}

fn assert_clean_reason(text: &str) {
    assert!(
        text.contains(CLEAN_REASON),
        "expected sanitized reason {CLEAN_REASON:?} in {text:?}"
    );
    assert!(
        !text.contains('\u{1B}') && !text.contains('\0') && !text.contains('\u{202E}'),
        "control and bidi codepoints must be stripped from {text:?}"
    );
    assert!(
        !text.contains('\u{200B}'),
        "zero-width codepoints must be stripped from {text:?}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn cancel_task_sanitizes_reason_before_ai_notes_and_summary() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004177";
    seed_task(
        &server,
        task_id,
        "Cancel reason hygiene",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .cancel_task(Parameters(CancelTaskArgs {
            id: task_id.to_string(),
            reason: Some(RAW_REASON.to_string()),
            cancel_series: None,
            idempotency_key: None,
            dry_run: false,
        }))
        .expect("cancel_task should succeed");
    let payload: Value = serde_json::from_str(&response).expect("parse cancel_task response");
    let returned_notes = payload["cancelled"]["ai_notes"]
        .as_str()
        .expect("returned task has ai_notes");

    assert_eq!(
        persisted_ai_notes(&server, task_id),
        "Cancelled: keep[31msafe"
    );
    assert_eq!(returned_notes, "Cancelled: keep[31msafe");
    assert_clean_reason(&latest_summary(&server, "cancel_task"));
}

#[test]
#[serial_test::serial(hlc)]
fn defer_task_sanitizes_reason_before_ai_notes_and_summary() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004178";
    seed_task(
        &server,
        task_id,
        "Defer reason hygiene",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .defer_task(Parameters(DeferTaskArgs {
            id: task_id.to_string(),
            until_date: "2026-06-01".to_string(),
            reason: Some(RAW_REASON.to_string()),
            structured_reason: None,
            idempotency_key: None,
        }))
        .expect("defer_task should succeed");
    let payload: Value = serde_json::from_str(&response).expect("parse defer_task response");
    let returned_notes = payload["ai_notes"]
        .as_str()
        .expect("returned task has ai_notes");

    assert_eq!(
        persisted_ai_notes(&server, task_id),
        "Deferred (#1): keep[31msafe"
    );
    assert_eq!(returned_notes, "Deferred (#1): keep[31msafe");
    assert_clean_reason(&latest_summary(&server, "defer_task"));
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_sanitizes_reason_before_ai_notes_and_summary() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004179";
    seed_task(
        &server,
        task_id,
        "Batch cancel reason hygiene",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec![task_id.to_string()],
            reason: Some(RAW_REASON.to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        }))
        .expect("batch_cancel_tasks should succeed");
    let payload: Value =
        serde_json::from_str(&response).expect("parse batch_cancel_tasks response");
    let returned_notes = payload["cancelled"][0]["ai_notes"]
        .as_str()
        .expect("returned task has ai_notes");

    assert_eq!(
        persisted_ai_notes(&server, task_id),
        "Cancelled: keep[31msafe"
    );
    assert_eq!(returned_notes, "Cancelled: keep[31msafe");
    assert_clean_reason(&latest_summary(&server, "batch_cancel_tasks"));
}

#[test]
#[serial_test::serial(hlc)]
fn batch_defer_tasks_sanitizes_reason_before_ai_notes_and_summary() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004180";
    seed_task(
        &server,
        task_id,
        "Batch defer reason hygiene",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .batch_defer_tasks(Parameters(BatchDeferTasksArgs {
            task_ids: vec![task_id.to_string()],
            until_date: "2026-06-01".to_string(),
            reason: Some(RAW_REASON.to_string()),
            structured_reason: None,
            idempotency_key: None,
        }))
        .expect("batch_defer_tasks should succeed");
    let payload: Value = serde_json::from_str(&response).expect("parse batch_defer_tasks response");
    let returned_notes = payload["deferred"][0]["ai_notes"]
        .as_str()
        .expect("returned task has ai_notes");

    assert_eq!(
        persisted_ai_notes(&server, task_id),
        "Deferred (#1): keep[31msafe"
    );
    assert_eq!(returned_notes, "Deferred (#1): keep[31msafe");
    assert_clean_reason(&latest_summary(&server, "batch_defer_tasks"));
}
