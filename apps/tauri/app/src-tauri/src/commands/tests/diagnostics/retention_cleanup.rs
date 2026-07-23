use super::support::*;

/// Regression for the retention cleanup bug that was silently dead: the
/// original SQL used `datetime('now', '-N days')` which returns a
/// SPACE-separated string (`2026-03-12 22:52:24`), but
/// `sync_timestamp_now()` writes RFC 3339 with a `T` separator
/// (`2026-03-12T22:52:36.789012Z`). Lexicographic `col < cutoff`
/// compares `'T' (0x54)` against `' ' (0x20)` at position 10. When row
/// and cutoff share the same date, `T` > ` ` makes the row look
/// "newer" than the cutoff, so the predicate is FALSE and the row is
/// kept despite being older than the retention window. The fix uses
/// `strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)` so the cutoff shares the
/// `T` separator and comparison proceeds through the time portion
/// correctly.
///
/// This test inserts rows at the bug boundary (1 second older than
/// the cutoff, same date as cutoff) to force the T-vs-space failure
/// mode. A naive 30-day-old fixture does NOT catch the bug because
/// the date portion dominates the lexicographic comparison before the
/// T-vs-space mismatch matters.
#[test]
fn run_data_retention_cleanup_deletes_rfc3339_boundary_rows() {
    let conn = setup_sync_test_conn();

    // Seed retention preferences: 7-day window for both tables.
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
            "7",
            TEST_VERSION,
            "2026-03-29T00:00:00.000000Z"
        ],
    )
    .expect("seed changelog retention preference");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![
            lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
            "7",
            TEST_VERSION,
            "2026-03-29T00:00:00.000000Z"
        ],
    )
    .expect("seed error log retention preference");

    let now = Utc::now();
    // Row placed 1 minute older than the 7-day cutoff.
    // a 1-second margin aliases against clock skew between test seed
    // and cleanup-under-test (test reads Utc::now(), cleanup reads
    // its own Utc::now() a moment later). 1 minute is still well
    // inside the retention behavior we're exercising and far beyond
    // any realistic wall-clock drift between the two reads.
    let boundary_ts = (now - Duration::days(7) - Duration::minutes(1))
        .to_rfc3339_opts(SecondsFormat::Micros, true);
    // Belt-and-braces: also include a clearly-old row (30 days back)
    // so the test covers the common path too.
    let far_old_ts = (now - Duration::days(30)).to_rfc3339_opts(SecondsFormat::Micros, true);
    let fresh_ts = lorvex_domain::sync_timestamp_now();

    assert!(
        boundary_ts.contains('T'),
        "boundary timestamp should use T separator like real data"
    );
    assert!(
        far_old_ts.contains('T'),
        "far-old timestamp should use T separator like real data"
    );
    assert!(
        fresh_ts.contains('T'),
        "fresh timestamp should use T separator like real data"
    );

    // ai_changelog: boundary-old and far-old AI rows (both deleted),
    // one fresh AI row (survives), one far-old HUMAN row (survives,
    // because the shared assistant-actor filter excludes human actors from
    // cleanup).
    let insert_changelog = "INSERT INTO ai_changelog
        (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
        VALUES (?1, ?2, 'update', 'task', NULL, ?3, ?4, NULL)";
    conn.execute(
        insert_changelog,
        params!["boundary-ai", boundary_ts, "Boundary AI entry", "codex"],
    )
    .expect("insert boundary ai changelog row");
    conn.execute(
        insert_changelog,
        params!["far-old-ai", far_old_ts, "Far-old AI entry", "codex"],
    )
    .expect("insert far-old ai changelog row");
    conn.execute(
        insert_changelog,
        params!["fresh-ai", fresh_ts, "Fresh AI entry", "codex"],
    )
    .expect("insert fresh ai changelog row");
    conn.execute(
        insert_changelog,
        params!["old-human", far_old_ts, "Old human entry", "human"],
    )
    .expect("insert old human changelog row");

    // error_logs: boundary-old, far-old, and fresh.
    let insert_error = "INSERT INTO error_logs
        (id, source, level, message, details, created_at)
        VALUES (?1, 'frontend.test', 'error', ?2, NULL, ?3)";
    conn.execute(
        insert_error,
        params!["boundary-err", "boom-boundary", boundary_ts],
    )
    .expect("insert boundary error log row");
    conn.execute(
        insert_error,
        params!["far-old-err", "boom-far-old", far_old_ts],
    )
    .expect("insert far-old error log row");
    conn.execute(insert_error, params!["fresh-err", "boom-fresh", fresh_ts])
        .expect("insert fresh error log row");

    let result =
        run_data_retention_cleanup_with_conn(&conn).expect("retention cleanup should succeed");

    assert_eq!(
        result.changelog_deleted, 2,
        "both the boundary and far-old AI changelog rows should have \
         been deleted; the fresh AI entry and the human entry survive. \
         With the pre-fix buggy SQL using datetime('now', ?), the \
         boundary row survives because `T` > ` ` lexicographically."
    );
    assert_eq!(
        result.error_logs_deleted, 2,
        "both the boundary and far-old error_logs rows should have \
         been deleted. With the pre-fix buggy SQL, the boundary row \
         survives due to the T-vs-space lexicographic mismatch."
    );

    let remaining_changelog: Vec<String> = conn
        .prepare("SELECT id FROM ai_changelog ORDER BY id")
        .expect("prepare changelog select")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query changelog ids")
        .collect::<Result<_, _>>()
        .expect("collect changelog ids");
    assert_eq!(
        remaining_changelog,
        vec!["fresh-ai".to_string(), "old-human".to_string()]
    );

    let remaining_error: Vec<String> = conn
        .prepare("SELECT id FROM error_logs ORDER BY id")
        .expect("prepare error_logs select")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query error_log ids")
        .collect::<Result<_, _>>()
        .expect("collect error_log ids");
    assert_eq!(remaining_error, vec!["fresh-err".to_string()]);
}

/// default-retention behavior: when neither retention
/// preference is set, the cleanup must still enforce the shipping
/// defaults (30d error_logs, 90d ai_changelog). Fresh rows survive;
/// rows older than the default window get purged.
#[test]
fn run_data_retention_cleanup_applies_defaults_when_no_preferences_set() {
    let conn = setup_sync_test_conn();

    let fresh_ts = lorvex_domain::sync_timestamp_now();
    // Old enough to exceed both defaults (90d + 30d).
    let old_ts = "2020-01-01T00:00:00.000Z".to_string();

    conn.execute(
        "INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
         VALUES ('fresh-ai', ?1, 'update', 'task', NULL, 'Fresh entry', 'codex', NULL)",
        params![fresh_ts],
    )
    .expect("insert fresh ai changelog row");
    conn.execute(
        "INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool)
         VALUES ('old-ai', ?1, 'update', 'task', NULL, 'Old entry', 'codex', NULL)",
        params![old_ts],
    )
    .expect("insert old ai changelog row");
    conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at)
         VALUES ('fresh-err', 'frontend.test', 'error', 'fresh-boom', NULL, ?1)",
        params![fresh_ts],
    )
    .expect("insert fresh error log row");
    conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at)
         VALUES ('old-err', 'frontend.test', 'error', 'old-boom', NULL, ?1)",
        params![old_ts],
    )
    .expect("insert old error log row");

    let result = run_data_retention_cleanup_with_conn(&conn)
        .expect("retention cleanup should succeed without preferences");

    assert_eq!(
        result.changelog_deleted, 1,
        "old ai_changelog row must be purged under the 90-day default"
    );
    assert_eq!(
        result.error_logs_deleted, 1,
        "old error_logs row must be purged under the 30-day default"
    );

    let changelog_ids: Vec<String> = conn
        .prepare("SELECT id FROM ai_changelog ORDER BY id")
        .expect("prepare")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect");
    assert_eq!(changelog_ids, vec!["fresh-ai".to_string()]);

    let error_ids: Vec<String> = conn
        .prepare("SELECT id FROM error_logs ORDER BY id")
        .expect("prepare")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect");
    assert_eq!(error_ids, vec!["fresh-err".to_string()]);
}

#[test]
fn run_data_retention_cleanup_logs_swallowed_outbox_gc_failure() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version,
            payload, device_id, created_at, synced_at, retry_count
         ) VALUES (
            'task', 'task-retention-log', 'upsert',
            '0000000000000_0000_a0a0a0a0a0a0a0a0', 1,
            '{}', 'device-a', '2000-01-01T00:00:00.000Z',
            '2000-01-01T00:00:00.000Z', 0
         )",
        [],
    )
    .expect("seed synced outbox row");
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Delete {
            table_name: "sync_outbox",
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    run_data_retention_cleanup_with_conn(&conn)
        .expect("retention cleanup should swallow auxiliary outbox GC failures");

    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'diagnostics.retention.outbox_gc'
               AND level = 'warn'
               AND message LIKE '%outbox gc_synced failed%'",
            [],
            |row| row.get(0),
        )
        .expect("count retention outbox GC diagnostic rows");
    assert_eq!(
        log_count, 1,
        "swallowed retention maintenance failures must be durable in error_logs"
    );
}

#[test]
fn run_data_retention_cleanup_reaps_stale_pending_queues_via_production_path() {
    let conn = setup_sync_test_conn();
    let fresh_ts = lorvex_domain::sync_timestamp_now();
    let stale_inbox_ts = "2000-01-01T00:00:00.000Z";
    let old_envelope = "{\"entity_type\":\"task\",\"entity_id\":\"task-old\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}";
    let fresh_envelope = "{\"entity_type\":\"task\",\"entity_id\":\"task-fresh\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a1\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}";

    conn.execute(
        "INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
         VALUES
            (?1, 'fk_unresolved', 'list', 'old-list',
             'task', 'task-old', '0000000000000_0000_a0a0a0a0a0a0a0a0',
             ?3, ?3, 1),
            (?2, 'fk_unresolved', 'list', 'fresh-list',
             'task', 'task-fresh', '0000000000000_0000_a0a0a0a0a0a0a0a1',
             ?4, ?4, 1)",
        params![old_envelope, fresh_envelope, stale_inbox_ts, fresh_ts],
    )
    .expect("seed pending inbox rows");

    run_data_retention_cleanup_with_conn(&conn).expect("retention cleanup should succeed");

    let inbox_missing_ids: Vec<String> = conn
        .prepare("SELECT missing_entity_id FROM sync_pending_inbox ORDER BY missing_entity_id")
        .expect("prepare pending inbox query")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query pending inbox ids")
        .collect::<Result<_, _>>()
        .expect("collect pending inbox ids");
    assert_eq!(inbox_missing_ids, vec!["fresh-list".to_string()]);

    let reseed_required: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'",
            [],
            |row| row.get(0),
        )
        .expect("reseed checkpoint should be set before pending inbox GC");
    assert_eq!(reseed_required, "true");
}
