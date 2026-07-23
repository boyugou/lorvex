//! router-dispatch tests for the daily-review surface.
//!
//! The `add_daily_review`, `amend_daily_review`, and
//! `get_daily_review` tools have no router-level coverage in the
//! main test bundle. These tests pin the wrapper / dispatch glue.

use super::*;

fn review_date_for_server(server: &TestServer) -> String {
    server
        .with_conn_typed(|conn| Ok(lorvex_workflow::timezone::today_ymd_for_conn(conn)?))
        .expect("resolve test review date")
}

#[test]
#[serial_test::serial(hlc)]
fn add_then_get_daily_review_via_router_round_trips() {
    let server = make_server();
    let review_date = review_date_for_server(&server);

    let response = server
        .add_daily_review(Parameters(AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "Shipped #3006 M+L items.".to_string(),
            mood: Some(4),
            energy_level: Some(3),
            linked_task_ids: None,
            linked_list_ids: None,
            wins: Some("MCP audit closed.".to_string()),
            blockers: None,
            learnings: Some("Idempotency cache must be checksum-gated.".to_string()),
            ai_synthesis: None,
        }))
        .expect("add_daily_review");
    let parsed: Value = serde_json::from_str(&response).expect("parse add_daily_review");
    assert_eq!(parsed.get("date"), Some(&Value::from(review_date.as_str())));

    // Audit log must record the create.
    let log_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'add_daily_review'",
                [],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("count ai_changelog");
    assert_eq!(log_count, 1);

    // Read-back via the read-only router path.
    let read = server
        .get_daily_review(Parameters(GetDailyReviewArgs {
            date: Some(review_date.clone()),
        }))
        .expect("get_daily_review");
    let parsed_read: Value = serde_json::from_str(&read).expect("parse get_daily_review");
    assert_eq!(
        parsed_read.get("date"),
        Some(&Value::from(review_date.as_str()))
    );
    assert_eq!(
        parsed_read.get("summary"),
        Some(&Value::from("Shipped #3006 M+L items."))
    );
}

#[test]
#[serial_test::serial(hlc)]
fn amend_daily_review_via_router_updates_field_and_logs_audit() {
    let server = make_server();
    let review_date = review_date_for_server(&server);
    server
        .add_daily_review(Parameters(AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "Initial draft.".to_string(),
            mood: None,
            energy_level: None,
            linked_task_ids: None,
            linked_list_ids: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
        }))
        .expect("seed daily review");

    let response = server
        .amend_daily_review(Parameters(AmendDailyReviewArgs {
            date: review_date,
            summary: Some("Revised after evening reflection.".to_string()),
            mood: Some(5),
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: None,
            linked_list_ids: None,
        }))
        .expect("amend_daily_review");
    let parsed: Value = serde_json::from_str(&response).expect("parse amend_daily_review");
    assert_eq!(
        parsed.get("summary"),
        Some(&Value::from("Revised after evening reflection."))
    );
    assert_eq!(parsed.get("mood"), Some(&Value::from(5)));

    let log_count: i64 = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'amend_daily_review'",
                [],
                |row| row.get(0),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("count ai_changelog");
    assert_eq!(log_count, 1);
}
