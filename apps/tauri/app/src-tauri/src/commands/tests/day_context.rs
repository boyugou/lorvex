use super::*;

/// Test-only helper kept after the `commands/day_context/timezone.rs` module
/// was removed (issue #3001 H9). Mirrors the former delegating wrapper:
/// returns `due_date` when present, otherwise resolves today's local date
/// against the connection's timezone preference at `now`.
fn recurrence_base_date_for_conn_at(
    conn: &rusqlite::Connection,
    due_date: Option<&str>,
    now: chrono::DateTime<chrono::Utc>,
) -> Result<String, lorvex_store::StoreError> {
    match due_date {
        Some(value) => Ok(value.to_string()),
        None => lorvex_workflow::timezone::today_ymd_for_conn_at(conn, now),
    }
}

// every test-fixture seed in this file references the
// canonical [`TEST_VERSION`] (re-exported from
// `lorvex_store::test_support`) rather than open-coding a literal.
// `TEST_VERSION` lex-sorts strictly below every realistic post-update
// HLC, so a future apply-pipeline LWW gate cannot silently no-op the
// mutations these tests assert on.

#[test]
fn normalize_date_input_converts_rfc3339_to_target_local_calendar_day() {
    let pacific = FixedOffset::west_opt(8 * 60 * 60).expect("offset");
    assert_eq!(
        normalize_date_input_for_timezone("2026-03-08T01:00:00Z", &pacific)
            .expect("normalize rfc3339"),
        "2026-03-07"
    );
}

#[test]
fn today_ymd_for_conn_uses_timezone_preference_calendar_day() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    assert_eq!(
        lorvex_workflow::timezone::today_ymd_for_conn_at(&conn, now).expect("compute today"),
        "2026-03-07"
    );
}

#[test]
fn today_ymd_for_conn_rejects_non_json_raw_timezone_preference() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', 'America/Los_Angeles', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert malformed timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    let error = lorvex_workflow::timezone::today_ymd_for_conn_at(&conn, now)
        .expect_err("malformed timezone preference should fail");
    assert!(
        error.to_string().contains("timezone"),
        "unexpected error: {error}"
    );
}

#[test]
fn today_ymd_for_conn_rejects_invalid_json_timezone_preference() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"Not/AZone\"', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert invalid timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    let error = lorvex_workflow::timezone::today_ymd_for_conn_at(&conn, now)
        .expect_err("invalid timezone preference should fail");
    assert!(
        error.to_string().contains("timezone"),
        "unexpected error: {error}"
    );
}

#[test]
fn normalize_date_input_for_conn_uses_timezone_preference_calendar_day() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert timezone preference");

    assert_eq!(
        normalize_date_input_for_conn(&conn, "2026-03-08T01:00:00Z").expect("normalize due date"),
        "2026-03-07"
    );
}

#[test]
fn recurrence_base_date_for_conn_uses_timezone_preference_for_undated_tasks() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    assert_eq!(
        recurrence_base_date_for_conn_at(&conn, None, now).expect("resolve recurrence base"),
        "2026-03-07"
    );
    assert_eq!(
        recurrence_base_date_for_conn_at(&conn, Some("2026-03-01"), now)
            .expect("preserve explicit due date"),
        "2026-03-01"
    );
}

#[test]
fn trailing_day_window_bounds_for_conn_uses_timezone_midnight_boundaries() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', ?1, '2026-03-09T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 9, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    let bounds = trailing_day_window_bounds_for_conn_at(&conn, now, 7).expect("resolve day window");

    assert_eq!(bounds.from_day, "2026-03-02");
    assert_eq!(bounds.to_day, "2026-03-08");
    // Canonical fractional `Z` form matches the canonical write format
    // (`sync_timestamp_now()`). Seconds precision would flip the lex
    // comparison against fractional timestamp columns at position 19
    // (`.` vs `Z`), causing day-boundary rows to be incorrectly excluded.
    // See the fix + regression test in `window.rs`.
    assert_eq!(bounds.start_utc, "2026-03-02T08:00:00.000Z");
    assert_eq!(bounds.end_utc, "2026-03-09T07:00:00.000Z");
}

#[test]
fn query_list_tasks_with_recent_completed_excludes_rows_outside_retention_window() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', ?1, '2026-03-08T01:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert timezone preference");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-retention', 'List Retention', ?1, '2026-03-01T08:00:00Z', '2026-03-01T08:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert list");
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new("task-open")
        .title("Task Open")
        .version(TEST_VERSION)
        .created_at("2026-03-07T09:00:00Z")
        .list_id(Some("list-retention"))
        .insert(&conn);
    TaskBuilder::new("task-completed-recent")
        .title("Task Completed Recent")
        .status("completed")
        .version(TEST_VERSION)
        .created_at("2026-03-01T08:00:00Z")
        .list_id(Some("list-retention"))
        .completed_at(Some("2026-03-01T08:00:00Z"))
        .insert(&conn);
    TaskBuilder::new("task-completed-old")
        .title("Task Completed Old")
        .status("completed")
        .version(TEST_VERSION)
        .created_at("2026-03-01T07:59:59Z")
        .list_id(Some("list-retention"))
        .completed_at(Some("2026-03-01T07:59:59Z"))
        .insert(&conn);
    TaskBuilder::new("task-cancelled")
        .title("Task Cancelled")
        .status("cancelled")
        .version(TEST_VERSION)
        .created_at("2026-03-07T10:00:00Z")
        .list_id(Some("list-retention"))
        .insert(&conn);

    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    let retention_window =
        trailing_day_window_bounds_for_conn_at(&conn, now, 7).expect("resolve retention window");
    let result = query_list_tasks_with_recent_completed(
        &conn,
        &lorvex_domain::ListId::from_trusted("list-retention".to_string()),
        &retention_window.start_utc,
        &retention_window.end_utc,
        1000,
    )
    .expect("query list tasks");

    let task_ids = result
        .tasks
        .into_iter()
        .map(|task| task.id)
        .collect::<std::collections::HashSet<_>>();
    assert!(task_ids.contains("task-open"));
    assert!(task_ids.contains("task-completed-recent"));
    assert!(!task_ids.contains("task-completed-old"));
    assert!(!task_ids.contains("task-cancelled"));
}
