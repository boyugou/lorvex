use super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_ai_changelog_entity_id_filter_matches_exact_json_array_membership() {
    let server = make_server();

    server
        .with_conn(|conn| {
            conn.execute(
                r"
                INSERT INTO ai_changelog (
                  id, timestamp, operation, entity_type, entity_id, summary,
                  initiated_by, mcp_tool
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ",
                (
                    "log-match",
                    "2026-03-03T09:00:00Z",
                    "triage",
                    "task",
                    Option::<String>::None,
                    "exact match entry",
                    "ai",
                    "test",
                ),
            )
            .map_err(to_error_message)?;
            lorvex_store::changelog::replace_changelog_entities(
                conn,
                "log-match",
                &["task-1".to_string(), "task-2".to_string()],
            )
            .map_err(to_error_message)?;
            conn.execute(
                r"
                INSERT INTO ai_changelog (
                  id, timestamp, operation, entity_type, entity_id, summary,
                  initiated_by, mcp_tool
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ",
                (
                    "log-substring",
                    "2026-03-03T08:00:00Z",
                    "triage",
                    "task",
                    Option::<String>::None,
                    "substring false positive",
                    "ai",
                    "test",
                ),
            )
            .map_err(to_error_message)?;
            lorvex_store::changelog::replace_changelog_entities(
                conn,
                "log-substring",
                &["task-10".to_string()],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed ai changelog rows");

    let payload = server
        .get_ai_changelog(Parameters(GetAiChangelogArgs {
            limit: Some(10),
            offset: None,
            entity_type: None,
            operation: None,
            entity_id: Some("task-1".to_string()),
            since: None,
        }))
        .expect("get ai changelog");
    // response is now `{entries, count, limit, offset, ...}`
    // instead of a bare array so callers can paginate.
    let payload_value: Value = serde_json::from_str(&payload).expect("valid changelog json");
    let rows = payload_value["entries"]
        .as_array()
        .expect("changelog rows under `entries`");

    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["id"], "log-match");
}

#[test]
#[serial_test::serial(hlc)]
fn get_ai_changelog_excludes_human_and_manual_rows() {
    let server = make_server();

    server
        .with_conn(|conn| {
            for (id, initiated_by) in [
                ("log-ai", "ai"),
                ("log-human", "human"),
                ("log-manual", "manual"),
                ("log-user", "user"),
            ] {
                conn.execute(
                    r"
                    INSERT INTO ai_changelog (
                      id, timestamp, operation, entity_type, entity_id, summary,
                      initiated_by, mcp_tool
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ",
                    (
                        id,
                        "2026-03-03T09:00:00Z",
                        "update",
                        "task",
                        Some("task-1".to_string()),
                        format!("row for {initiated_by}"),
                        initiated_by,
                        "test",
                    ),
                )
                .map_err(to_error_message)?;
            }
            Ok(())
        })
        .expect("seed ai changelog rows");

    let payload = server
        .get_ai_changelog(Parameters(GetAiChangelogArgs {
            limit: Some(10),
            offset: None,
            entity_type: None,
            operation: None,
            entity_id: None,
            since: None,
        }))
        .expect("get ai changelog");
    let payload_value: Value = serde_json::from_str(&payload).expect("valid changelog json");
    let rows = payload_value["entries"]
        .as_array()
        .expect("changelog rows under `entries`");

    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["id"], "log-ai");
}

#[test]
#[serial_test::serial(hlc)]
fn get_recent_logs_merges_and_redacts_sources_in_descending_timestamp_order() {
    let server = make_server();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO error_logs (id, source, level, message, details, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    "error-1",
                    "sync-engine",
                    "error",
                    "Authorization: Bearer super-secret-token",
                    Some("password=hunter2".to_string()),
                    "2026-03-03T07:00:00Z",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                r"
                INSERT INTO ai_changelog (
                  id, timestamp, operation, entity_type, entity_id, summary,
                  initiated_by, mcp_tool
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ",
                (
                    "log-1",
                    "2026-03-03T08:00:00Z",
                    "update",
                    "task",
                    Some("task-1".to_string()),
                    "token=abc1234",
                    "ai",
                    "update_task",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO sync_outbox (entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    "task",
                    "task-2",
                    "upsert",
                    "v1",
                    1,
                    "{}",
                    "device-a",
                    "2026-03-03T09:00:00Z",
                    Option::<String>::None,
                    2,
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed recent log rows");

    let payload = server
        .get_recent_logs(Parameters(GetRecentLogsArgs {
            limit: Some(10),
            offset: None,
            since: None,
            level: None,
            levels: Some(vec![
                LogLevelFilter::Error,
                LogLevelFilter::Warn,
                LogLevelFilter::Info,
                LogLevelFilter::Debug,
            ]),
            source: None,
            sources: Some(vec![
                LogSourceFilter::ErrorLog,
                LogSourceFilter::AiChangelog,
                LogSourceFilter::SyncOutbox,
            ]),
            include_details: Some(true),
            redact: Some(true),
        }))
        .expect("get recent logs");
    let value: Value = serde_json::from_str(&payload).expect("valid recent logs json");
    let entries = value["entries"].as_array().expect("entries");

    assert_eq!(value["count"], 3);
    assert_eq!(value["source_counts"]["error_log"], 1);
    assert_eq!(value["source_counts"]["ai_changelog"], 1);
    assert_eq!(value["source_counts"]["sync_outbox"], 1);
    assert_eq!(value["malformed_source_counts"]["error_log"], 0);
    assert_eq!(value["malformed_source_counts"]["ai_changelog"], 0);
    assert_eq!(value["malformed_source_counts"]["sync_outbox"], 0);

    assert_eq!(entries[0]["source"], "sync_outbox");
    assert_eq!(entries[0]["level"], "warn");
    assert_eq!(entries[1]["source"], "ai_changelog");
    assert_eq!(entries[1]["level"], "info");
    assert_eq!(entries[2]["source"], "error_log");
    assert_eq!(entries[2]["level"], "error");

    assert_eq!(entries[2]["summary"], "Authorization: Bearer [REDACTED]");
    assert_eq!(entries[2]["details"], "password=[REDACTED]");
    assert_eq!(entries[1]["summary"], "token=[REDACTED]");
}

#[test]
#[serial_test::serial(hlc)]
fn get_recent_logs_skips_malformed_rows_and_reports_counts() {
    let server = make_server();

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO error_logs (id, source, level, message, details, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    "error-bad",
                    "sync-engine",
                    "error",
                    "missing timestamp should be rejected",
                    Option::<String>::None,
                    "",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                r"
                INSERT INTO ai_changelog (
                  id, timestamp, operation, entity_type, entity_id, summary,
                  initiated_by, mcp_tool
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ",
                (
                    "log-valid",
                    "2026-03-03T08:00:00Z",
                    "update",
                    "task",
                    Some("task-1".to_string()),
                    "valid summary",
                    "ai",
                    "update_task",
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO sync_outbox (entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    "task",
                    "task-2",
                    "upsert",
                    "v1",
                    1,
                    "{}",
                    "device-a",
                    "2026-03-03T09:00:00Z",
                    Option::<String>::None,
                    0,
                ),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO sync_outbox (entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    "",
                    "task-bad",
                    "upsert",
                    "v2",
                    1,
                    "{}",
                    "device-b",
                    "2026-03-03T10:00:00Z",
                    Option::<String>::None,
                    0,
                ),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed recent log rows");

    let payload = server
        .get_recent_logs(Parameters(GetRecentLogsArgs {
            limit: Some(10),
            offset: None,
            since: None,
            level: None,
            levels: Some(vec![
                LogLevelFilter::Error,
                LogLevelFilter::Warn,
                LogLevelFilter::Info,
            ]),
            source: None,
            sources: Some(vec![
                LogSourceFilter::ErrorLog,
                LogSourceFilter::AiChangelog,
                LogSourceFilter::SyncOutbox,
            ]),
            include_details: Some(false),
            redact: Some(false),
        }))
        .expect("get recent logs");
    let value: Value = serde_json::from_str(&payload).expect("valid recent logs json");
    let entries = value["entries"].as_array().expect("entries");

    assert_eq!(value["count"], 2);
    assert_eq!(value["source_counts"]["error_log"], 0);
    assert_eq!(value["source_counts"]["ai_changelog"], 1);
    assert_eq!(value["source_counts"]["sync_outbox"], 1);
    assert_eq!(value["malformed_source_counts"]["error_log"], 1);
    assert_eq!(value["malformed_source_counts"]["ai_changelog"], 0);
    assert_eq!(value["malformed_source_counts"]["sync_outbox"], 1);
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0]["source"], "sync_outbox");
    assert_eq!(entries[1]["source"], "ai_changelog");
}
