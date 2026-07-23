use super::enrich::{enrich_tasks_with_reminders, fetch_task_json};
use super::suggestions::task_not_found_with_suggestions;
use super::task_id::required_task_id;
use crate::error::McpError;
use lorvex_store::connection::open_db_in_memory;
use lorvex_workflow::task_enrichment;
use serde_json::json;

fn insert_task(conn: &rusqlite::Connection, id: &str, title: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .version("v-test")
        .created_at("2026-04-04T00:00:00Z")
        .insert(conn);
}

/// #2371 regression: a prefix typo on the id surfaces the full id as
/// a suggestion so the assistant can retry in a single round-trip.
#[test]
#[serial_test::serial(hlc)]
fn task_not_found_suggests_prefix_match() {
    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "task-001-buy-milk", "Buy milk");
    insert_task(&conn, "task-042-unrelated", "Unrelated");

    let err = task_not_found_with_suggestions(&conn, "task-001");
    match err {
        McpError::NotFound(message) => {
            assert!(
                message.contains("Task 'task-001' not found"),
                "base message preserved: {message}",
            );
            assert!(
                message.contains("Did you mean"),
                "suggestion trailer present: {message}",
            );
            assert!(
                message.contains("task-001-buy-milk"),
                "prefix hit surfaced: {message}",
            );
            assert!(
                message.contains("Buy milk"),
                "matched task title surfaced: {message}",
            );
        }
        other => panic!("expected NotFound, got {other:?}"),
    }
}

/// #2371 regression: a non-UUID needle falls through to the title
/// substring search, so the assistant can type "milk" into an id
/// field and still get steered towards the right row.
#[test]
#[serial_test::serial(hlc)]
fn task_not_found_suggests_title_substring() {
    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "task-aaa", "Buy milk at the store");
    insert_task(&conn, "task-bbb", "Call mom");

    let err = task_not_found_with_suggestions(&conn, "milk");
    match err {
        McpError::NotFound(message) => {
            assert!(
                message.contains("task-aaa"),
                "title-substring hit surfaced: {message}",
            );
            assert!(
                !message.contains("task-bbb"),
                "unrelated task must not appear: {message}",
            );
        }
        other => panic!("expected NotFound, got {other:?}"),
    }
}

/// #2371 regression: when the local task set has nothing even
/// remotely similar, fall back to the plain "not found" prose
/// rather than inventing a suggestion.
#[test]
#[serial_test::serial(hlc)]
fn task_not_found_omits_suggestion_trailer_when_no_matches() {
    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "task-alpha", "Alpha task");

    let err = task_not_found_with_suggestions(&conn, "zzz-unrelated");
    match err {
        McpError::NotFound(message) => {
            assert!(
                message.contains("Task 'zzz-unrelated' not found"),
                "base message preserved: {message}",
            );
            assert!(
                !message.contains("Did you mean"),
                "no suggestion trailer when there are no matches: {message}",
            );
        }
        other => panic!("expected NotFound, got {other:?}"),
    }
}

/// Smoke test that `fetch_task_json` routes its not-found path
/// through the suggestion-enriched error (so every single-task
/// fetch across the MCP server benefits from #2371).
#[test]
#[serial_test::serial(hlc)]
fn fetch_task_json_uses_enriched_not_found() {
    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "task-hello-world", "Hello world");

    let err = fetch_task_json(&conn, "task-hello").unwrap_err();
    match err {
        McpError::NotFound(message) => {
            assert!(
                message.contains("task-hello-world"),
                "prefix suggestion surfaced via fetch_task_json: {message}",
            );
        }
        other => panic!("expected NotFound, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn required_task_id_rejects_missing_id() {
    let task = json!({ "title": "broken" });
    let err = required_task_id(&task, "test").unwrap_err();
    match err {
        McpError::Internal(message) => {
            assert!(message.contains("missing required non-empty `id`"));
        }
        other => panic!("expected internal error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn enrich_tasks_with_reminders_rejects_missing_task_id() {
    let conn = open_db_in_memory().unwrap();
    let mut tasks = vec![json!({ "title": "broken" })];
    let err = enrich_tasks_with_reminders(&conn, &mut tasks).unwrap_err();
    match err {
        McpError::Internal(message) => {
            assert!(message.contains("batched task reminder enrichment"));
        }
        other => panic!("expected internal error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn compute_enrichments_yields_no_tags_entry_when_task_has_no_tags() {
    let conn = open_db_in_memory().unwrap();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("t1")
        .title("Test")
        .version("v-test")
        .created_at("2026-04-04T00:00:00Z")
        .insert(&conn);

    let dates = [("t1", None, None)];
    let map = task_enrichment::compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert!(map.get("t1").and_then(|e| e.tags.clone()).is_none());
}

#[test]
#[serial_test::serial(hlc)]
fn compute_enrichments_yields_no_depends_on_entry_when_task_has_none() {
    let conn = open_db_in_memory().unwrap();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("t1")
        .title("Test")
        .version("v-test")
        .created_at("2026-04-04T00:00:00Z")
        .insert(&conn);

    let dates = [("t1", None, None)];
    let map = task_enrichment::compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert!(map.get("t1").and_then(|e| e.depends_on.clone()).is_none());
}
