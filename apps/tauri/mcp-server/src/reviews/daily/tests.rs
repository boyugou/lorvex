use super::{add_daily_review, amend_daily_review, get_daily_review, get_review_history};
use crate::contract::{
    AddDailyReviewArgs, AmendDailyReviewArgs, GetDailyReviewArgs, GetReviewHistoryArgs,
};
use crate::db::open_database_for_path;
use crate::runtime::change_tracking::{
    generate_hlc_version, hlc_test_mutex, reset_thread_hlc_for_tests,
};
use rusqlite::Connection;
use serde_json::Value;
use tempfile::tempdir;

// The active-task existence check used by the daily-review writer
// shape-checks each id, so the previous `task-1`/`task-2` fixtures
// need real UUIDs.
const FIX_TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000d01";
const FIX_TASK_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000000d02";
const FIX_LIST_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000e01";

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_timezone_preference(conn: &Connection, timezone: &str) {
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', ?1, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
        [serde_json::to_string(timezone).expect("serialize timezone")],
    )
    .expect("insert timezone preference");
}

/// Seed a task so that FK references in daily_review_task_links are valid.
fn seed_task(conn: &Connection, task_id: &str) {
    // lift to canonical TaskBuilder. The original
    // helper bound `id` and `title` to the same value, so preserve
    // that to avoid changing test data.
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title(task_id)
        .created_at("2026-03-01T00:00:00Z")
        .insert(conn);
}

/// Seed a list so that FK references in daily_review_list_links are valid.
fn seed_list(conn: &Connection, list_id: &str) {
    lorvex_store::test_support::ListBuilder::new(list_id)
        .name(list_id)
        .created_at("2026-03-01T00:00:00Z")
        .insert(conn);
}

fn seed_daily_review_with_version(conn: &Connection, date: &str, summary: &str, version: &str) {
    conn.execute(
        "INSERT INTO daily_reviews \
         (date, summary, timezone, version, created_at, updated_at) \
         VALUES (?1, ?2, 'UTC', ?3, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
        rusqlite::params![date, summary, version],
    )
    .expect("seed daily review");
}

fn count_rows(conn: &Connection, sql: &str) -> i64 {
    conn.query_row(sql, [], |row| row.get(0))
        .expect("count rows")
}

fn count_rows_for_review_date(conn: &Connection, sql: &str, review_date: &str) -> i64 {
    conn.query_row(sql, [review_date], |row| row.get(0))
        .expect("count rows")
}

fn review_date_for_test(conn: &Connection) -> String {
    lorvex_workflow::timezone::today_ymd_for_conn(conn).expect("resolve test review date")
}

fn review_date_offset_for_test(conn: &Connection, days: i64) -> String {
    let date = chrono::NaiveDate::parse_from_str(&review_date_for_test(conn), "%Y-%m-%d")
        .expect("parse test review date");
    (date + chrono::Duration::days(days))
        .format("%Y-%m-%d")
        .to_string()
}

fn sample_add_review_args(date: &str) -> AddDailyReviewArgs {
    AddDailyReviewArgs {
        date: Some(date.to_string()),
        summary: "Solid day".to_string(),
        mood: Some(4),
        energy_level: Some(3),
        linked_task_ids: Some(vec![FIX_TASK_1.to_string(), FIX_TASK_2.to_string()]),
        linked_list_ids: Some(vec![FIX_LIST_1.to_string()]),
        wins: Some("Finished the hard thing".to_string()),
        blockers: Some("None".to_string()),
        learnings: Some("Ship smaller".to_string()),
        ai_synthesis: Some("Momentum stayed high".to_string()),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn add_daily_review_response_includes_linked_arrays() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    seed_list(&conn, FIX_LIST_1);
    let review_date = review_date_for_test(&conn);

    let response = add_daily_review(&conn, sample_add_review_args(&review_date))
        .expect("add daily review response");
    let payload: Value = serde_json::from_str(&response).expect("parse add daily review response");

    assert_eq!(
        payload.get("linked_task_ids"),
        Some(&serde_json::json!([FIX_TASK_1, FIX_TASK_2])),
    );
    assert_eq!(
        payload.get("linked_list_ids"),
        Some(&serde_json::json!([FIX_LIST_1])),
    );
    assert_eq!(
        payload.get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );
}

// #4423: `#[serial(hlc)]` schedules every test that touches the
// process-wide MCP HLC state (`HLC_RUNTIME`) one at a time so two
// tests opening distinct temp databases (with distinct device ids)
// cannot race through lazy first-init and trigger
// `SurfaceHlcError::DifferentIdentity` panics. The explicit
// `hlc_test_mutex()` lock is retained as a belt-and-braces guard for
// the existing reset window; serialization is the primary fix.
#[test]
#[serial_test::serial(hlc)]
fn review_reads_include_linked_arrays() {
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    seed_list(&conn, FIX_LIST_1);
    let first_review_date = review_date_offset_for_test(&conn, -1);
    let second_review_date = review_date_for_test(&conn);

    add_daily_review(&conn, sample_add_review_args(&first_review_date)).expect("seed first review");
    add_daily_review(&conn, sample_add_review_args(&second_review_date))
        .expect("seed second review");

    let single = get_daily_review(
        &conn,
        GetDailyReviewArgs {
            date: Some(second_review_date),
        },
    )
    .expect("get daily review response");
    let single_payload: Value =
        serde_json::from_str(&single).expect("parse get daily review response");
    assert_eq!(
        single_payload.get("linked_task_ids"),
        Some(&serde_json::json!([FIX_TASK_1, FIX_TASK_2])),
    );
    assert_eq!(
        single_payload.get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );

    let history = get_review_history(
        &conn,
        GetReviewHistoryArgs {
            limit: Some(2),
            offset: None,
            since: None,
        },
    )
    .expect("get review history response");
    let history_payload: Value =
        serde_json::from_str(&history).expect("parse get review history response");
    // #3029-M1: response is now wrapped in the canonical
    // pagination envelope. Tests read `reviews` instead of treating
    // the payload as a bare array.
    let rows = history_payload
        .get("reviews")
        .and_then(Value::as_array)
        .expect("history rows");
    assert_eq!(rows.len(), 2);
    assert_eq!(history_payload.get("count"), Some(&serde_json::json!(2)));
    assert_eq!(
        history_payload.get("total_matching"),
        Some(&serde_json::json!(2)),
    );
    assert_eq!(history_payload.get("next_offset"), Some(&Value::Null));
    assert_eq!(
        rows[0].get("linked_list_ids"),
        Some(&serde_json::json!([FIX_LIST_1])),
    );
    assert_eq!(
        rows[0].get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn empty_review_history_returns_empty_array() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");

    let history = get_review_history(
        &conn,
        GetReviewHistoryArgs {
            limit: Some(5),
            offset: None,
            since: None,
        },
    )
    .expect("get empty review history response");
    let history_payload: Value =
        serde_json::from_str(&history).expect("parse empty get review history response");
    // #3029-M1: empty history surfaces as the canonical pagination
    // envelope with `total_matching: 0` and `reviews: []`.
    let rows = history_payload
        .get("reviews")
        .and_then(Value::as_array)
        .expect("history rows");
    assert!(rows.is_empty(), "empty history should serialize as []");
    assert_eq!(history_payload.get("count"), Some(&serde_json::json!(0)));
    assert_eq!(
        history_payload.get("total_matching"),
        Some(&serde_json::json!(0)),
    );
    assert_eq!(history_payload.get("next_offset"), Some(&Value::Null));
}

#[test]
#[serial_test::serial(hlc)]
fn add_daily_review_without_links_returns_null_arrays() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let review_date = review_date_for_test(&conn);

    let args = AddDailyReviewArgs {
        date: Some(review_date),
        summary: "Quiet day".to_string(),
        mood: Some(3),
        energy_level: None,
        linked_task_ids: None,
        linked_list_ids: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
    };
    let response = add_daily_review(&conn, args).expect("add daily review");
    let payload: Value = serde_json::from_str(&response).expect("parse response");

    assert_eq!(
        payload.get("linked_task_ids"),
        Some(&Value::Array(Vec::new()))
    );
    assert_eq!(
        payload.get("linked_list_ids"),
        Some(&Value::Array(Vec::new()))
    );
}

#[test]
#[serial_test::serial(hlc)]
fn link_tables_populated_correctly() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    seed_list(&conn, FIX_LIST_1);
    let review_date = review_date_for_test(&conn);

    add_daily_review(&conn, sample_add_review_args(&review_date)).expect("add review");

    // Verify join table rows exist
    let task_link_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            [&review_date],
            |row| row.get(0),
        )
        .expect("count task links");
    assert_eq!(task_link_count, 2);

    let list_link_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_review_list_links WHERE review_date = ?1",
            [&review_date],
            |row| row.get(0),
        )
        .expect("count list links");
    assert_eq!(list_link_count, 1);
}

/// write-time gate: `add_daily_review` rejects an
/// archived (trashed) task in `linked_task_ids`. The assistant should
/// not be able to pin a freshly-trashed task into a new review — that
/// is almost always a stale-context bug. See `writes/add.rs` for the
/// full policy comment.
#[test]
#[serial_test::serial(hlc)]
fn add_daily_review_rejects_archived_linked_task_id() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    let review_date = review_date_for_test(&conn);
    // Archive FIX_TASK_2 BEFORE the add — this is the stale-context
    // case the gate is meant to catch.
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [FIX_TASK_2],
    )
    .expect("soft-delete FIX_TASK_2");

    let err = add_daily_review(
        &conn,
        AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "Day".to_string(),
            mood: None,
            energy_level: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string(), FIX_TASK_2.to_string()]),
            linked_list_ids: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
        },
    )
    .expect_err("archived linked_task_ids must be rejected");
    let message = err.to_string();
    assert!(message.contains("archived"), "unexpected error: {message}");
    assert!(message.contains(FIX_TASK_2), "expected id: {message}");

    // No partial review must persist on validation failure even when the
    // handler is called directly without the router savepoint wrapper.
    // The validation gate runs before the Mutation executor writes the
    // parent row or materializes link rows.
    let review_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_reviews WHERE date = ?1",
            [&review_date],
            |row| row.get(0),
        )
        .expect("count reviews");
    assert_eq!(review_count, 0);
    let task_link_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            [&review_date],
            |row| row.get(0),
        )
        .expect("count task links");
    assert_eq!(task_link_count, 0);
}

#[test]
#[serial_test::serial(hlc)]
fn add_daily_review_rejects_stale_lww_parent_before_links_or_audit() {
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    generate_hlc_version(&conn).expect("initialize MCP HLC before forcing stale row");
    let review_date = review_date_for_test(&conn);
    seed_daily_review_with_version(
        &conn,
        &review_date,
        "newer peer state",
        "9999999999999_9999_ffffffffffffffff",
    );

    let err = add_daily_review(
        &conn,
        AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "stale local attempt".to_string(),
            mood: None,
            energy_level: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string()]),
            linked_list_ids: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
        },
    )
    .expect_err("stale daily review upsert must reject before child/audit writes");

    match err {
        crate::error::McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_DAILY_REVIEW);
            assert_eq!(id, review_date);
        }
        other => panic!("expected stale daily review error, got {other:?}"),
    }

    let (summary, version): (String, String) = conn
        .query_row(
            "SELECT summary, version FROM daily_reviews WHERE date = ?1",
            [&review_date],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load unchanged review");
    assert_eq!(summary, "newer peer state");
    assert_eq!(version, "9999999999999_9999_ffffffffffffffff");
    assert_eq!(
        count_rows_for_review_date(
            &conn,
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            &review_date,
        ),
        0,
        "rejected parent write must not materialize task links",
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'daily_review'",
        ),
        0,
        "rejected parent write must not log audit rows",
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'daily_review'",
        ),
        0,
        "rejected parent write must not enqueue sync payloads",
    );
}

/// write-time gate: `amend_daily_review` rejects an
/// archived task added via `linked_task_ids` on the amend path, in
/// parity with the add path.
#[test]
#[serial_test::serial(hlc)]
fn amend_daily_review_rejects_archived_linked_task_id() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    let review_date = review_date_for_test(&conn);

    // Seed an initial review with FIX_TASK_1 only — every linked id
    // here is live, so the seed succeeds.
    add_daily_review(
        &conn,
        AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "Initial".to_string(),
            mood: None,
            energy_level: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string()]),
            linked_list_ids: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
        },
    )
    .expect("seed review");

    // Now archive FIX_TASK_2 and try to amend the review to also pin
    // it — must be rejected.
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [FIX_TASK_2],
    )
    .expect("soft-delete FIX_TASK_2");

    let err = amend_daily_review(
        &conn,
        AmendDailyReviewArgs {
            date: review_date,
            summary: None,
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string(), FIX_TASK_2.to_string()]),
            linked_list_ids: None,
        },
    )
    .expect_err("archived linked_task_ids on amend must be rejected");
    let message = err.to_string();
    assert!(message.contains("archived"), "unexpected error: {message}");
    assert!(message.contains(FIX_TASK_2), "expected id: {message}");
}

#[test]
#[serial_test::serial(hlc)]
fn amend_daily_review_rejects_stale_lww_parent_before_links_or_audit() {
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    generate_hlc_version(&conn).expect("initialize MCP HLC before forcing stale row");
    let review_date = review_date_for_test(&conn);
    seed_daily_review_with_version(
        &conn,
        &review_date,
        "newer peer state",
        "9999999999999_9999_ffffffffffffffff",
    );

    let err = amend_daily_review(
        &conn,
        AmendDailyReviewArgs {
            date: review_date.clone(),
            summary: Some("stale amend".to_string()),
            mood: None,
            energy_level: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string()]),
            linked_list_ids: None,
        },
    )
    .expect_err("stale daily review amend must reject before child/audit writes");

    match err {
        crate::error::McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_DAILY_REVIEW);
            assert_eq!(id, review_date);
        }
        other => panic!("expected stale daily review error, got {other:?}"),
    }

    let (summary, version): (String, String) = conn
        .query_row(
            "SELECT summary, version FROM daily_reviews WHERE date = ?1",
            [&review_date],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load unchanged review");
    assert_eq!(summary, "newer peer state");
    assert_eq!(version, "9999999999999_9999_ffffffffffffffff");
    assert_eq!(
        count_rows_for_review_date(
            &conn,
            "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?1",
            &review_date,
        ),
        0,
        "rejected parent write must not materialize task links",
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'daily_review'",
        ),
        0,
        "rejected parent write must not log audit rows",
    );
    assert_eq!(
        count_rows(
            &conn,
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'daily_review'",
        ),
        0,
        "rejected parent write must not enqueue sync payloads",
    );
}

/// read-time tolerance: a task that was active when
/// the review was written and archived later still surfaces in the
/// stored `linked_task_ids` array. Daily review is record-keeping;
/// rewriting history when a target task is later trashed would erase
/// the audit trail. The mismatch with the focus surface is intentional
/// — focus is forward-looking (must be live), review is backward-
/// looking (preserve what was true at write-time).
#[test]
#[serial_test::serial(hlc)]
fn get_daily_review_preserves_pin_to_post_write_archived_task() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    seed_task(&conn, FIX_TASK_1);
    seed_task(&conn, FIX_TASK_2);
    let review_date = review_date_for_test(&conn);

    add_daily_review(
        &conn,
        AddDailyReviewArgs {
            date: Some(review_date.clone()),
            summary: "Day".to_string(),
            mood: None,
            energy_level: None,
            linked_task_ids: Some(vec![FIX_TASK_1.to_string(), FIX_TASK_2.to_string()]),
            linked_list_ids: None,
            wins: None,
            blockers: None,
            learnings: None,
            ai_synthesis: None,
        },
    )
    .expect("seed review with two live linked tasks");

    // Archive FIX_TASK_2 AFTER the review write — this simulates the
    // user trashing a task days later.
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [FIX_TASK_2],
    )
    .expect("soft-delete FIX_TASK_2 post-write");

    let response = get_daily_review(
        &conn,
        GetDailyReviewArgs {
            date: Some(review_date),
        },
    )
    .expect("get daily review");
    let payload: Value = serde_json::from_str(&response).expect("parse review json");
    // Both ids must still surface — the read tolerates post-write
    // archival to preserve historical context.
    assert_eq!(
        payload.get("linked_task_ids"),
        Some(&serde_json::json!([FIX_TASK_1, FIX_TASK_2])),
        "stale pin to since-archived task must remain visible: {payload}",
    );
}
