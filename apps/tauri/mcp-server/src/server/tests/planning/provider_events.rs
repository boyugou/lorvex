use super::super::*;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

/// Verify that `propose_daily_schedule` avoids scheduling task blocks during
/// a provider calendar event (e.g., an Apple Calendar meeting imported via
/// EventKit).  Before this fix, only canonical `calendar_events` were
/// considered, causing the scheduler to double-book provider meetings.
#[tokio::test]
async fn propose_focus_schedule_avoids_provider_event_conflict() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    // 1. Insert working_hours preference and set full_details AI access mode
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?)",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    r#"{"start":"09:00","end":"17:00"}"#,
                    "2026-03-01T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            // Set full_details so provider event titles are visible in the schedule
            conn.execute(
                "INSERT INTO device_state (key, value) VALUES (?, ?)",
                (
                    lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                    "\"full_details\"",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed working hours + access mode");

    // 2. Create a task and add it to current_focus for today
    seed_task(
        &server,
        "provider-evt-task",
        "Write quarterly report",
        "open",
        None,
        Some(&date),
        None,
        0,
    );
    // Set estimated_minutes so the task needs a sizeable block
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET estimated_minutes = 120 WHERE id = ?",
                ["provider-evt-task"],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("set estimated_minutes");

    // Add to current_focus
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?, '0000000000000_0000_0000000000000000', ?, ?)",
                (&date, "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus_items (date, task_id, position) VALUES (?, ?, ?)",
                (&date, "provider-evt-task", 0),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed current focus");

    // 3. Insert a provider event at 14:00–15:00 (simulating an Apple Calendar meeting)
    let now = "2026-03-01T00:00:00Z";
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO provider_calendar_events \
                 (provider_kind, provider_scope, provider_event_key, \
                  title, start_date, start_time, end_time, all_day, \
                  event_type, source_time_kind, last_seen_at, last_refreshed_at) \
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    "eventkit",
                    "personal",
                    "apple-evt-001",
                    "Team Standup",
                    &date,
                    "14:00",
                    "15:00",
                    false,
                    "event",
                    "floating",
                    now,
                    now,
                ),
            )
            .map_err(to_error_message)?;
            // Mark the provider scope as enabled with a successful refresh so
            // timeline queries can trust cached provider occupancy.
            conn.execute(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at) \
                 VALUES ('eventkit', 'personal', 1, 'enabled', ?1)",
                [now],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed provider event");

    // 4. Call propose_daily_schedule
    let result = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs {
                date: Some(date.clone()),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect("propose should succeed");

    let schedule: Value = serde_json::from_str(&result).expect("valid json");

    // 5. The schedule must contain an event block covering the provider event
    let blocks = schedule["blocks"].as_array().expect("blocks array");
    let event_blocks: Vec<&Value> = blocks
        .iter()
        .filter(|b| b["block_type"].as_str() == Some("event"))
        .collect();
    assert!(
        !event_blocks.is_empty(),
        "schedule should contain at least one event block for the provider event"
    );
    let provider_block = event_blocks
        .iter()
        .find(|b| b["title"].as_str() == Some("Team Standup"))
        .expect("provider event 'Team Standup' should appear as an event block");
    assert_eq!(provider_block["start_time"].as_str(), Some("14:00"));
    assert_eq!(provider_block["end_time"].as_str(), Some("15:00"));
    assert!(
        provider_block["event_id"].is_null(),
        "provider-backed event block should not expose a canonical event_id sentinel"
    );

    // 6. No task block should overlap with 14:00–15:00 (840–900 minutes)
    let task_blocks: Vec<&Value> = blocks
        .iter()
        .filter(|b| b["block_type"].as_str() == Some("task"))
        .collect();
    for tb in &task_blocks {
        let tb_start = tb["start_time"].as_str().unwrap_or("");
        let tb_end = tb["end_time"].as_str().unwrap_or("");
        // Parse HH:MM to minutes for overlap check
        let parse = |s: &str| -> i64 {
            let parts: Vec<&str> = s.split(':').collect();
            parts[0].parse::<i64>().unwrap_or(0) * 60 + parts[1].parse::<i64>().unwrap_or(0)
        };
        let start_m = parse(tb_start);
        let end_m = parse(tb_end);
        assert!(
            end_m <= 840 || start_m >= 900,
            "task block {tb_start}–{tb_end} overlaps with provider event 14:00–15:00"
        );
    }

    // 7. The calendar_events_count should include the provider event
    assert!(
        schedule["calendar_events_count"].as_i64().unwrap_or(0) >= 1,
        "calendar_events_count should be at least 1 (the provider event)"
    );
}

#[tokio::test]
async fn propose_focus_schedule_surfaces_calendar_ai_access_mode_lookup_failures() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?)",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    r#"{"start":"09:00","end":"17:00"}"#,
                    "2026-03-01T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?, '0000000000000_0000_0000000000000000', ?, ?)",
                (&date, "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"),
            )
            .map_err(to_error_message)?;
            // lift to canonical TaskBuilder.
            lorvex_store::test_support::fixtures::TaskBuilder::new("provider-evt-task-fail")
                .title("Write quarterly report")
                .created_at("2026-03-01T00:00:00Z")
                .insert(conn);
            conn.execute(
                "INSERT INTO current_focus_items (date, task_id, position) VALUES (?, ?, ?)",
                (&date, "provider-evt-task-fail", 0),
            )
            .map_err(to_error_message)?;
            conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
                AuthAction::Read {
                    table_name: "device_state",
                    ..
                } => {
                    Authorization::Deny
                }
                _ => Authorization::Allow,
            }))
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed focus schedule prerequisites");

    let error = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs {
                date: Some(date.clone()),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("device_state lookup failure should surface");
    assert!(
        error.contains("internal error")
            || error.contains("device_state")
            || error.contains("not authorized"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn propose_focus_schedule_rejects_malformed_working_hours_preference() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?)",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    "{not-valid-json",
                    "2026-03-01T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?, '0000000000000_0000_0000000000000000', ?, ?)",
                (&date, "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"),
            )
            .map_err(to_error_message)?;
            // lift to canonical TaskBuilder.
            lorvex_store::test_support::fixtures::TaskBuilder::new(
                "provider-evt-task-working-hours",
            )
            .title("Write quarterly report")
            .created_at("2026-03-01T00:00:00Z")
            .insert(conn);
            conn.execute(
                "INSERT INTO current_focus_items (date, task_id, position) VALUES (?, ?, ?)",
                (&date, "provider-evt-task-working-hours", 0),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed focus schedule prerequisites");

    let error = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs {
                date: Some(date.clone()),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("malformed working_hours should surface");
    assert!(error.contains("working_hours"), "unexpected error: {error}");
}

#[tokio::test]
async fn propose_focus_schedule_rejects_missing_working_hours_fields() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?)",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    r#"{"start":"09:00"}"#,
                    "2026-03-01T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?, '0000000000000_0000_0000000000000000', ?, ?)",
                (&date, "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"),
            )
            .map_err(to_error_message)?;
            // lift to canonical TaskBuilder.
            lorvex_store::test_support::fixtures::TaskBuilder::new(
                "provider-evt-task-working-hours-missing",
            )
            .title("Write quarterly report")
            .created_at("2026-03-01T00:00:00Z")
            .insert(conn);
            conn.execute(
                "INSERT INTO current_focus_items (date, task_id, position) VALUES (?, ?, ?)",
                (&date, "provider-evt-task-working-hours-missing", 0),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed focus schedule prerequisites");

    let error = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs {
                date: Some(date.clone()),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("working_hours without end should surface");
    assert!(error.contains("working_hours"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn get_calendar_events_surfaces_calendar_ai_access_mode_lookup_failures() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    // Install the authorizer on all read-pool connections — get_calendar_events
    // is dispatched via with_read_conn_typed (round-robin read pool), not the
    // writer connection. Authorizers are per-connection, so we must install on
    // every read connection to guarantee the query hits a blocked one.
    server
        .pool
        .try_for_each_read_conn(|conn| {
            conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
                AuthAction::Read {
                    table_name: "device_state",
                    ..
                } => Authorization::Deny,
                _ => Authorization::Allow,
            }))
            .expect("install read-pool authorizer");
        })
        .expect("try_for_each_read_conn must succeed in tests");

    let error = server
        .get_calendar_events(Parameters(GetCalendarEventsArgs {
            from: date.clone(),
            to: date,
            limit: 20,
            offset: 0,
            include_provider: true,
        }))
        .expect_err("device_state lookup failure should surface");
    assert!(
        error.contains("internal error")
            || error.contains("device_state")
            || error.contains("not authorized"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn propose_focus_schedule_rejects_malformed_calendar_ai_access_mode_state() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at) VALUES (?, ?, '0000000000000_0000_0000000000000000', ?)",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    r#"{"start":"09:00","end":"17:00"}"#,
                    "2026-03-01T00:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO current_focus (date, version, created_at, updated_at) VALUES (?, '0000000000000_0000_0000000000000000', ?, ?)",
                (&date, "2026-03-01T00:00:00Z", "2026-03-01T00:00:00Z"),
            )
            .map_err(to_error_message)?;
            // lift to canonical TaskBuilder.
            lorvex_store::test_support::fixtures::TaskBuilder::new(
                "provider-evt-task-malformed-access",
            )
            .title("Write quarterly report")
            .created_at("2026-03-01T00:00:00Z")
            .insert(conn);
            conn.execute(
                "INSERT INTO current_focus_items (date, task_id, position) VALUES (?, ?, ?)",
                (&date, "provider-evt-task-malformed-access", 0),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO device_state (key, value) VALUES (?, ?)",
                (
                    lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                    "\"definitely_not_a_mode\"",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed focus schedule prerequisites");

    let error = server
        .propose_daily_schedule(
            Parameters(ProposeDailyScheduleArgs {
                date: Some(date.clone()),
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect_err("malformed calendar_ai_access_mode should surface");
    assert!(
        error.contains("calendar_ai_access_mode"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_calendar_events_rejects_malformed_calendar_ai_access_mode_state() {
    let server = make_server();
    let date = today_ymd_local_for_test();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO device_state (key, value) VALUES (?, ?)",
                (
                    lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                    "\"definitely_not_a_mode\"",
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed malformed access mode");

    let error = server
        .get_calendar_events(Parameters(GetCalendarEventsArgs {
            from: date.clone(),
            to: date,
            limit: 20,
            offset: 0,
            include_provider: true,
        }))
        .expect_err("malformed calendar_ai_access_mode should surface");
    assert!(
        error.contains("calendar_ai_access_mode"),
        "unexpected error: {error}"
    );
}
