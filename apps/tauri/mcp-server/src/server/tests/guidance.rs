use super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_guide_reports_current_focus_presence_from_conn_local_day() {
    let server = make_server();
    let today = server
        .with_conn_typed(|conn| Ok(lorvex_workflow::timezone::today_ymd_for_conn(conn)?))
        .expect("resolve today");

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO current_focus (date, briefing, version, created_at, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?, ?)",
                (
                    today.clone(),
                    "Daily focus".to_string(),
                    "2026-03-01T00:00:00Z".to_string(),
                    "2026-03-01T00:00:00Z".to_string(),
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed current focus");

    let payload = server
        .get_guide(Parameters(GetGuideArgs {
            topic: Some(GuideTopic::Overview),
        }))
        .expect("guide should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid guide json");

    assert_eq!(value["topic"], "overview");
    assert_eq!(value["state"]["has_current_focus"], true);
}

#[test]
#[serial_test::serial(hlc)]
fn get_guide_rejects_malformed_setup_completed_preference() {
    let server = make_server();
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z')",
                (
                    lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
                    "{not-valid-json",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("insert malformed setup preference");

    let error = server
        .get_guide(Parameters(GetGuideArgs {
            topic: Some(GuideTopic::Overview),
        }))
        .expect_err("malformed setup_completed should fail");
    assert!(
        error.contains("setup_completed"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_guide_keeps_getting_started_until_working_hours_are_configured() {
    let server = make_server();
    // The schema seeds 'inbox' list + default_list_id preference,
    // so no extra seeding is needed for normal_task_creation_ready.

    let payload = server
        .get_guide(Parameters(GetGuideArgs { topic: None }))
        .expect("guide should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid guide json");
    assert_eq!(value["topic"], "getting_started");
    assert_eq!(value["state"]["setup_completed"], false);

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z')",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    "{\"start\":\"09:00\",\"end\":\"17:00\"}",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed working hours");

    let payload = server
        .get_guide(Parameters(GetGuideArgs { topic: None }))
        .expect("guide should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid guide json");
    assert_ne!(value["topic"], "getting_started");
    assert_eq!(value["state"]["setup_completed"], true);
}

#[tokio::test]
async fn analyze_task_patterns_surfaces_behavioral_metrics_and_samples() {
    let server = make_server();
    seed_task(
        &server,
        "deferred-overdue",
        "Deferred overdue task",
        "open",
        None,
        Some("2000-01-01"),
        None,
        3,
    );
    // The trailing-day window is computed from Utc::now() with timezone
    // adjustments. Previously this seeded with Utc::now()
    // truncated to whole seconds, which could alias the query's
    // query-time cutoff at boundaries (test-seed clock vs. query-time
    // clock drift). Anchor 1 hour in the past so the row is
    // unambiguously inside the 30-day window regardless of clock skew
    // or TZ-shift-based boundary math.
    let recent = (chrono::Utc::now() - chrono::Duration::hours(1))
        .to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET updated_at = ? WHERE id = 'deferred-overdue'",
                [&recent],
            )
            .map_err(to_error_message)?;
            // Stays raw: TaskBuilder doesn't expose `estimated_minutes`,
            // and the dynamic completed/due timestamps drive the
            // due-date-miss analytics this test exercises.
            conn.execute(
                "INSERT INTO tasks (id, title, status, due_date, estimated_minutes, completed_at, list_id, version, created_at, updated_at)
                 VALUES ('done-late', 'Late completed task', 'completed', '2000-01-02', 30, ?, 'inbox', '0000000000000_0000_0000000000000000', ?, ?)",
                [&recent, &recent, &recent],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("update updated_at");

    let payload = server
        .analyze_task_patterns(
            Parameters(AnalyzeTaskPatternsArgs {
                window_days: Some(30),
                top_n: Some(5),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect("analyze task patterns should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid insights json");

    assert_eq!(value["metrics"]["frequently_deferred"], 1);
    assert_eq!(value["metrics"]["overdue_backlog"], 1);
    assert_eq!(value["metrics"]["completed_total"], 1);
    assert_eq!(value["metrics"]["due_date_miss_total"], 1);
    assert!(
        value["sections"]
            .as_array()
            .expect("sections array")
            .iter()
            .filter_map(|entry| entry.get("type").and_then(Value::as_str))
            .any(|entry_type| entry_type == "frequently_deferred"),
        "expected frequently_deferred insight",
    );
    assert!(
        value["sections"]
            .as_array()
            .expect("sections array")
            .iter()
            .filter_map(|entry| entry.get("type").and_then(Value::as_str))
            .any(|entry_type| entry_type == "due_date_miss_rate"),
        "expected due_date_miss_rate section",
    );
    assert!(
        value["source_refs"]
            .as_array()
            .expect("source refs array")
            .iter()
            .filter_map(Value::as_str)
            .any(|source_ref| source_ref == "task:deferred-overdue"),
        "expected deferred task source ref",
    );
    assert!(
        value["source_refs"]
            .as_array()
            .expect("source refs array")
            .iter()
            .filter_map(Value::as_str)
            .any(|source_ref| source_ref == "task:done-late"),
        "expected late completed task source ref",
    );
}
