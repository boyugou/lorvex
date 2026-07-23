use super::*;
use crate::test_support::test_conn;
use std::sync::Mutex;

/// serialize every test that exercises the
/// boot-sweep skip cache. The static `LAST_SWEEP_AT_MILLIS` is
/// process-wide, so concurrent tests that both reset it would
/// race — one resets to 0, the other stamps `now`, and the
/// first's subsequent sweep short-circuits unexpectedly. Hold
/// this Mutex from the moment a test resets the static until
/// it has finished asserting on `sweep_expired`.
static SWEEP_TEST_LOCK: Mutex<()> = Mutex::new(());

fn checked_lookup(
    conn: &rusqlite::Connection,
    tool_name: &str,
    key: &str,
    request_repr: &str,
) -> LookupOutcome {
    let checksum = compute_request_checksum(request_repr);
    lookup_checked(conn, tool_name, key, &checksum).expect("lookup should succeed")
}

#[test]
fn lookup_returns_none_when_key_absent() {
    let conn = test_conn();
    assert_eq!(
        checked_lookup(&conn, "create_task", "missing", "{\"missing\":true}"),
        LookupOutcome::Miss
    );
}

#[test]
fn record_then_lookup_returns_payload() {
    let conn = test_conn();
    let checksum = compute_request_checksum("{\"hello\":1}");
    record(&conn, "key-1", "create_task", &checksum, "{\"hello\":1}")
        .expect("record should succeed");
    assert_eq!(
        checked_lookup(&conn, "create_task", "key-1", "{\"hello\":1}"),
        LookupOutcome::Hit("{\"hello\":1}".to_string())
    );
}

#[test]
fn record_rejects_empty_request_checksum() {
    let conn = test_conn();
    let error = record(&conn, "empty-checksum", "create_task", "", "{\"ok\":true}")
        .expect_err("empty request checksums must be rejected");
    assert!(
        error.to_string().contains("request_checksum"),
        "error should identify the invalid request_checksum, got {error}"
    );
    let rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
            ["empty-checksum"],
            |row| row.get(0),
        )
        .expect("count rows");
    assert_eq!(rows, 0, "failed empty checksum write must not persist");
}

#[test]
fn schema_rejects_default_or_empty_request_checksum() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO mcp_idempotency \
         (key, tool_name, response_payload, expires_at) \
         VALUES ('missing-checksum', 'create_task', '{}', '2099-01-01T00:00:00.000Z')",
        [],
    )
    .expect_err("schema must not provide an empty request_checksum default");
    conn.execute(
        "INSERT INTO mcp_idempotency \
         (key, tool_name, request_checksum, response_payload, expires_at) \
         VALUES ('empty-checksum', 'create_task', '', '{}', '2099-01-01T00:00:00.000Z')",
        [],
    )
    .expect_err("schema must reject explicitly empty request_checksum values");
}

#[test]
fn lookup_after_expiry_returns_none_and_sweep_removes_row() {
    // reset the process-local skip cache so a
    // prior test that just stamped it doesn't make the sweep
    // here short-circuit.
    let _guard = SWEEP_TEST_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    LAST_SWEEP_AT_MILLIS.store(0, Ordering::Relaxed);
    let conn = test_conn();
    let created = Utc::now() - Duration::hours(48);
    let checksum = compute_request_checksum("{\"old\":true}");
    record_at(
        &conn,
        "stale",
        "create_task",
        &checksum,
        "{\"old\":true}",
        created,
        DEFAULT_TTL_HOURS,
    )
    .expect("record stale row");

    assert_eq!(
        checked_lookup(&conn, "create_task", "stale", "{\"old\":true}"),
        LookupOutcome::Miss,
        "expired rows must not resurface"
    );

    let deleted = sweep_expired(&conn).expect("sweep should succeed");
    assert_eq!(deleted, 1, "sweep should drop exactly the stale row");

    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
            ["stale"],
            |row| row.get(0),
        )
        .expect("count stale rows");
    assert_eq!(remaining, 0);
}

#[test]
fn record_or_replace_overwrites_prior_payload() {
    let conn = test_conn();
    let cs1 = compute_request_checksum("{\"v\":1}");
    record(&conn, "dup", "create_task", &cs1, "{\"v\":1}").expect("first record should succeed");
    let cs2 = compute_request_checksum("{\"v\":2}");
    record(&conn, "dup", "create_task", &cs2, "{\"v\":2}")
        .expect("second record should overwrite rather than fail");
    assert_eq!(
        checked_lookup(&conn, "create_task", "dup", "{\"v\":2}"),
        LookupOutcome::Hit("{\"v\":2}".to_string())
    );
}

#[test]
fn same_key_can_be_cached_independently_per_tool() {
    let conn = test_conn();
    let request = "{\"id\":\"same-shaped-id\"}";
    let checksum = compute_request_checksum(request);
    record(
        &conn,
        "shared-destructive-key",
        "delete_list",
        &checksum,
        "{\"deleted_list_id\":\"same-shaped-id\"}",
    )
    .expect("record list delete");
    record(
        &conn,
        "shared-destructive-key",
        "delete_calendar_event",
        &checksum,
        "{\"deleted_event_id\":\"same-shaped-id\"}",
    )
    .expect("record event delete");

    let rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
            ["shared-destructive-key"],
            |row| row.get(0),
        )
        .expect("count shared-key rows");
    assert_eq!(
        rows, 2,
        "same idempotency key must not collapse cache rows across tools"
    );
    assert_eq!(
        checked_lookup(&conn, "delete_list", "shared-destructive-key", request),
        LookupOutcome::Hit("{\"deleted_list_id\":\"same-shaped-id\"}".to_string())
    );
    assert_eq!(
        checked_lookup(
            &conn,
            "delete_calendar_event",
            "shared-destructive-key",
            request
        ),
        LookupOutcome::Hit("{\"deleted_event_id\":\"same-shaped-id\"}".to_string())
    );
    assert_eq!(
        checked_lookup(
            &conn,
            "delete_habit_reminder_policy",
            "shared-destructive-key",
            request
        ),
        LookupOutcome::Miss,
        "a same-shaped request for another tool must not replay either cached payload"
    );
}

#[test]
fn sweep_preserves_unexpired_rows() {
    // reset the process-local skip cache so a
    // prior test that just stamped it doesn't make the sweep
    // here short-circuit.
    let _guard = SWEEP_TEST_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    LAST_SWEEP_AT_MILLIS.store(0, Ordering::Relaxed);
    let conn = test_conn();
    let fresh_cs = compute_request_checksum("{\"keep\":true}");
    record(&conn, "fresh", "create_task", &fresh_cs, "{\"keep\":true}")
        .expect("fresh record should succeed");
    let drop_cs = compute_request_checksum("{\"drop\":true}");
    record_at(
        &conn,
        "old",
        "create_task",
        &drop_cs,
        "{\"drop\":true}",
        Utc::now() - Duration::hours(48),
        DEFAULT_TTL_HOURS,
    )
    .expect("stale record should succeed");

    let deleted = sweep_expired(&conn).expect("sweep should succeed");
    assert_eq!(deleted, 1);
    assert!(
        matches!(
            checked_lookup(&conn, "create_task", "fresh", "{\"keep\":true}"),
            LookupOutcome::Hit(_)
        ),
        "sweep must not remove unexpired rows"
    );
}

#[test]
fn unchecked_lookup_entry_points_are_not_exposed() {
    let source = include_str!("mod.rs");
    assert!(
        !source.contains("pub fn lookup("),
        "mcp_idempotency must not expose a no-checksum lookup API"
    );
    assert!(
        !source.contains("fn lookup_at("),
        "mcp_idempotency must not keep a private no-checksum lookup path"
    );
    assert!(
        !source.contains("stored_checksum.is_empty()"),
        "mcp_idempotency must not keep legacy empty-checksum lookup bypasses"
    );
}

#[test]
fn sweep_expired_skips_when_recent_sweep_ran() {
    // the second back-to-back sweep should
    // short-circuit without touching the writer lock. Use the
    // direct atomic API rather than the public `sweep_expired`
    // helper so this test is robust to parallel test execution
    // (other tests may have stamped the static counter just
    // before this one runs).
    let _guard = SWEEP_TEST_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let conn = test_conn();
    let cs = compute_request_checksum("{\"v\":1}");
    record_at(
        &conn,
        "stale-1",
        "create_task",
        &cs,
        "{\"v\":1}",
        Utc::now() - Duration::hours(48),
        DEFAULT_TTL_HOURS,
    )
    .expect("record stale row");

    // Force the skip cache to "just swept" — the next call
    // should short-circuit and return 0 even though there is a
    // stale row in the table.
    LAST_SWEEP_AT_MILLIS.store(Utc::now().timestamp_millis(), Ordering::Relaxed);
    let skipped = sweep_expired(&conn).expect("sweep should succeed");
    assert_eq!(skipped, 0, "sweep within skip window must short-circuit");

    // The stale row must still be present.
    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
            ["stale-1"],
            |row| row.get(0),
        )
        .expect("count stale-1 rows");
    assert_eq!(remaining, 1, "skipped sweep must not delete rows");

    // Force the skip cache far enough in the past, then sweep
    // should run and reap the stale row.
    LAST_SWEEP_AT_MILLIS.store(0, Ordering::Relaxed);
    let deleted = sweep_expired(&conn).expect("sweep should succeed");
    assert_eq!(deleted, 1, "post-window sweep must run and delete");
}

/// a checksum-aware lookup must reject a cache
/// hit whose stored fingerprint disagrees with the supplied
/// fingerprint, even when the key matches. Replaying the prior
/// response under that condition silently lies to the caller, so
/// the lookup returns `ChecksumMismatch` and the caller surfaces
/// it as a Validation error.
#[test]
fn lookup_checked_rejects_payload_collision() {
    let conn = test_conn();
    let original = "{\"task\":\"draft\"}";
    let original_checksum = compute_request_checksum(original);
    record(
        &conn,
        "shared-key",
        "create_task",
        &original_checksum,
        "{\"id\":\"t-1\"}",
    )
    .expect("record original");

    // Same key, different request payload — the cache must NOT
    // replay the prior response.
    let outcome = lookup_checked(
        &conn,
        "create_task",
        "shared-key",
        &compute_request_checksum("{\"task\":\"different\"}"),
    )
    .expect("lookup should succeed");
    match outcome {
        LookupOutcome::ChecksumMismatch {
            stored_tool,
            stored_checksum,
            supplied_checksum,
        } => {
            assert_eq!(stored_tool, "create_task");
            assert_eq!(stored_checksum, original_checksum);
            assert_ne!(stored_checksum, supplied_checksum);
        }
        other => panic!("expected ChecksumMismatch, got {other:?}"),
    }
}

#[test]
fn lookup_checked_returns_hit_on_matching_checksum() {
    let conn = test_conn();
    let original = "{\"task\":\"draft\"}";
    let checksum = compute_request_checksum(original);
    record(
        &conn,
        "match-key",
        "create_task",
        &checksum,
        "{\"id\":\"t-1\"}",
    )
    .expect("record original");

    let outcome = lookup_checked(&conn, "create_task", "match-key", &checksum)
        .expect("lookup should succeed");
    assert_eq!(outcome, LookupOutcome::Hit("{\"id\":\"t-1\"}".to_string()));
}

#[test]
fn compute_request_checksum_is_stable_and_distinguishes_payloads() {
    let a = compute_request_checksum("{\"x\":1}");
    let b = compute_request_checksum("{\"x\":1}");
    let c = compute_request_checksum("{\"x\":2}");
    assert_eq!(a, b, "same input must produce same digest");
    assert_ne!(a, c, "different input must produce different digest");
    assert_eq!(a.len(), 64, "SHA-256 hex digest is 64 chars");
    assert!(
        a.chars()
            .all(|ch| ch.is_ascii_hexdigit() && !ch.is_ascii_uppercase()),
        "digest must be lowercase hex"
    );
}

#[test]
fn timestamps_match_canonical_sync_format() {
    let now = Utc::now();
    let canonical = lorvex_domain::format_sync_timestamp(now);
    // Sanity: shape is `YYYY-MM-DDTHH:MM:SS.sssZ` (24 chars including 'Z').
    assert_eq!(canonical.len(), 24);
    assert!(canonical.ends_with('Z'));
    // expires_at_from must produce a strictly-greater canonical
    // timestamp with the same shape.
    let later = expires_at_from(now, 1);
    assert!(later > canonical);
    assert_eq!(later.len(), 24);
    assert!(later.ends_with('Z'));
}
