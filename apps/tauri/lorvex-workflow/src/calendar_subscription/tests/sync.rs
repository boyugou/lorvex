//! Pure orchestration tests for the workflow's subscription sync
//! pipeline. A deterministic in-memory [`FetchBackend`] stands in for
//! the production transport so each refresh branch
//! (rate-limited, truncated, fetch-error, parse-error, success) can
//! be exercised without standing up a real HTTP server.

use std::cell::RefCell;

use rusqlite::params;

use lorvex_store::test_support::test_conn;

use crate::calendar_subscription::sync::{
    record_ics_truncation_rejection, sync_calendar_subscription, sync_subscription_content,
    FetchBackend, FetchedIcs, FetchedIcsError, ICS_TRUNCATION_LOG_SOURCE,
};
use crate::calendar_subscription::truncation::ICS_TRUNCATION_MESSAGE;
use crate::calendar_subscription::tzid::noop_unknown_tzid_sink;
use crate::calendar_subscription::IcsTruncationReason;

/// Programmable in-memory [`FetchBackend`] for the orchestration
/// tests. Each call pops the next queued response, so a test can
/// drive the orchestrator through any sequence of branches by
/// pre-populating the queue.
struct FakeFetchBackend {
    responses: RefCell<Vec<Result<FetchedIcs, FetchedIcsError>>>,
}

impl FakeFetchBackend {
    fn new(responses: Vec<Result<FetchedIcs, FetchedIcsError>>) -> Self {
        Self {
            responses: RefCell::new(responses),
        }
    }
}

impl FetchBackend for FakeFetchBackend {
    fn fetch_ics(&self, _url: &str, _etag: Option<&str>) -> Result<FetchedIcs, FetchedIcsError> {
        self.responses.borrow_mut().pop().unwrap_or_else(|| {
            Err(FetchedIcsError::Other(
                "FakeFetchBackend queue exhausted".to_string(),
            ))
        })
    }
}

fn seed_subscription(conn: &rusqlite::Connection, id: &str) {
    seed_subscription_with_url(conn, id, "https://example.com/feed.ics");
}

/// Variant of [`seed_subscription`] that takes an explicit URL so
/// multiple feeds can coexist in the same connection (the schema
/// has a UNIQUE constraint on `url_normalized`).
fn seed_subscription_with_url(conn: &rusqlite::Connection, id: &str, url: &str) {
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 1, ?4, ?5, ?5)",
        params![
            id,
            "Test Feed",
            url,
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert subscription");
}

#[test]
fn record_ics_truncation_rejection_preserves_cached_events() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-trunc");

    lorvex_store::repositories::provider_repo::upsert_provider_event(
        &conn,
        &lorvex_store::repositories::provider_repo::ProviderEventData {
            provider_kind: "ical_subscription",
            provider_scope: "sub-trunc",
            provider_event_key: "cached-event",
            title: Some("Previously fetched"),
            description: None,
            start_date: "2026-03-29",
            start_time: Some("09:00"),
            end_date: Some("2026-03-29"),
            end_time: Some("10:00"),
            all_day: false,
            location: None,
            organizer_email: None,
            source_time_kind: "floating",
            source_tzid: None,
            recurrence: None,
            recurrence_exceptions: None,
            color: None,
            attendees_json: None,
            video_call_url: None,
        },
        "2026-03-29T00:00:00Z",
    )
    .expect("seed cached provider event");

    let result = record_ics_truncation_rejection(
        &conn,
        "sub-trunc",
        "Test Feed",
        "2026-03-29T00:05:00Z",
        IcsTruncationReason::UnbalancedVeventCount { begins: 2, ends: 1 },
        "https://example.com/feed.ics",
    )
    .expect("truncation rejection must persist without erroring");

    assert_eq!(result.events_imported, 0);
    assert_eq!(result.events_removed, 0);
    let error_msg = result
        .error
        .as_deref()
        .expect("truncation result must carry a user-visible error");
    assert!(error_msg.contains(ICS_TRUNCATION_MESSAGE));

    let remaining_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "ical_subscription",
        Some("sub-trunc"),
        None,
    )
    .expect("load cached provider event keys");
    assert_eq!(remaining_keys, vec!["cached-event".to_string()]);

    let log_row: (String, String) = conn
        .query_row(
            "SELECT source, level FROM error_logs ORDER BY created_at DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load most recent error_logs row");
    assert_eq!(log_row.0, ICS_TRUNCATION_LOG_SOURCE);
    assert_eq!(log_row.1, "warn");
}

#[test]
fn sync_subscription_content_imports_a_valid_event() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-1");
    let result = sync_subscription_content(
        &conn,
        "sub-1",
        "Test Feed",
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:e1\n\
         SUMMARY:Lunch\n\
         DTSTART:20260329T090000Z\n\
         DTEND:20260329T100000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
        None,
        &noop_unknown_tzid_sink,
    )
    .expect("apply should succeed");
    assert_eq!(result.events_imported, 1);
    assert!(result.error.is_none());
}

#[test]
fn sync_calendar_subscription_routes_fetch_error_to_last_error() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-err");
    let backend = FakeFetchBackend::new(vec![Err(FetchedIcsError::Other(
        "transport reset".to_string(),
    ))]);

    let result = sync_calendar_subscription(&conn, &backend, &noop_unknown_tzid_sink, "sub-err")
        .expect("orchestrator should not propagate the fetch error");
    assert_eq!(result.events_imported, 0);
    assert_eq!(result.error.as_deref(), Some("transport reset"));

    let last_result: String = conn
        .query_row(
            "SELECT last_refresh_result FROM provider_scope_runtime_state
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'sub-err'",
            [],
            |row| row.get(0),
        )
        .expect("load runtime state");
    assert_eq!(last_result, "fetch_error");
}

#[test]
fn sync_calendar_subscription_persists_rate_limit_cooldown() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-429");
    let backend = FakeFetchBackend::new(vec![Err(FetchedIcsError::RateLimited {
        retry_after_secs: Some(3_600),
        safe_url: "https://example.com/feed.ics".to_string(),
    })]);

    let result = sync_calendar_subscription(&conn, &backend, &noop_unknown_tzid_sink, "sub-429")
        .expect("orchestrator should not propagate the 429");
    assert!(
        result.error.is_some(),
        "rate-limit result must carry error message"
    );

    let next_attempt: Option<String> =
        lorvex_store::repositories::provider_repo::get_provider_scope_next_attempt_at(
            &conn,
            "ical_subscription",
            "sub-429",
        )
        .expect("load cooldown");
    assert!(
        next_attempt.is_some(),
        "rate-limit must persist next_attempt_at"
    );
}

#[test]
fn sync_calendar_subscription_drives_full_apply_on_success() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-ok");
    let body = "BEGIN:VCALENDAR\n\
                BEGIN:VEVENT\n\
                UID:eok\n\
                SUMMARY:Coffee\n\
                DTSTART:20260329T140000Z\n\
                DTEND:20260329T150000Z\n\
                END:VEVENT\n\
                END:VCALENDAR\n";
    let backend = FakeFetchBackend::new(vec![Ok(FetchedIcs {
        body: body.to_string(),
        etag: None,
        status: 200,
    })]);

    let result = sync_calendar_subscription(&conn, &backend, &noop_unknown_tzid_sink, "sub-ok")
        .expect("orchestrator should apply diff on success");
    assert_eq!(result.events_imported, 1);
    assert!(result.error.is_none());

    let last_result: String = conn
        .query_row(
            "SELECT last_refresh_result FROM provider_scope_runtime_state
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'sub-ok'",
            [],
            |row| row.get(0),
        )
        .expect("load runtime state");
    assert_eq!(last_result, "success");
}

/// #4482: a per-feed failure in the middle of a multi-feed batch
/// must NOT abort the remaining feeds. The CLI / UI expects every
/// feed to surface a `SubscriptionSyncResult` row — successful
/// feeds carry counters, failed feeds carry `error: Some(...)`.
/// Happy-path sanity check that both feeds appear in the result
/// vector; the partial-failure variants below cover the real fix.
#[test]
fn sync_all_returns_one_row_per_enabled_feed_on_happy_path() {
    use crate::calendar_subscription::sync::sync_all_calendar_subscriptions;

    let conn = test_conn();
    seed_subscription_with_url(&conn, "sub-a", "https://example.com/a.ics");
    seed_subscription_with_url(&conn, "sub-b", "https://example.com/b.ics");

    let body = "BEGIN:VCALENDAR\n\
                BEGIN:VEVENT\n\
                UID:e2\n\
                SUMMARY:Standup\n\
                DTSTART:20260329T140000Z\n\
                DTEND:20260329T150000Z\n\
                END:VEVENT\n\
                END:VCALENDAR\n";
    let backend = FakeFetchBackend::new(vec![
        Ok(FetchedIcs {
            body: body.to_string(),
            etag: None,
            status: 200,
        }),
        Ok(FetchedIcs {
            body: body.to_string(),
            etag: None,
            status: 200,
        }),
    ]);
    let results = sync_all_calendar_subscriptions(&conn, &backend, &noop_unknown_tzid_sink)
        .expect("batch should not propagate per-feed errors");
    assert_eq!(results.len(), 2, "every enabled feed gets a row");
}

/// #4482: verify the partial-failure contract directly by driving
/// the batch through a backend that yields one fetch-error and one
/// success. Both feeds must appear in the results vector; the
/// fetch-error feed carries `error: Some(...)` and the success
/// feed carries `error: None`. This already worked pre-fix for
/// fetch-error variants (which take the graceful match arms in
/// `sync_calendar_subscription`); the regression target is that a
/// per-feed failure mode must keep returning ALL feeds, which the
/// post-fix `match` enforces uniformly.
#[test]
fn sync_all_returns_one_row_per_feed_even_when_one_fetch_errors() {
    use crate::calendar_subscription::sync::sync_all_calendar_subscriptions;

    let conn = test_conn();
    seed_subscription_with_url(&conn, "sub-fetch-err", "https://example.com/err.ics");
    seed_subscription_with_url(&conn, "sub-fetch-ok", "https://example.com/ok.ics");

    // Two responses, popped in LIFO order by FakeFetchBackend (it
    // calls `pop()`). The first per-feed iteration consumes the
    // last-pushed entry, so order the success on top.
    let body = "BEGIN:VCALENDAR\n\
                BEGIN:VEVENT\n\
                UID:eok\n\
                SUMMARY:Coffee\n\
                DTSTART:20260329T140000Z\n\
                DTEND:20260329T150000Z\n\
                END:VEVENT\n\
                END:VCALENDAR\n";
    let backend = FakeFetchBackend::new(vec![
        Err(FetchedIcsError::Other("network down".to_string())),
        Ok(FetchedIcs {
            body: body.to_string(),
            etag: None,
            status: 200,
        }),
    ]);

    let results = sync_all_calendar_subscriptions(&conn, &backend, &noop_unknown_tzid_sink)
        .expect("batch must aggregate per-feed results");
    assert_eq!(results.len(), 2, "every enabled feed must appear");
    let errored = results.iter().filter(|r| r.error.is_some()).count();
    let ok = results.iter().filter(|r| r.error.is_none()).count();
    assert_eq!(errored, 1, "one feed reports an error");
    assert_eq!(ok, 1, "the other feed completes successfully");
}

/// #4482: a hard DB-layer error inside `sync_calendar_subscription`
/// is the case the bug filed against — pre-fix this aborted the
/// batch. Simulate it by dropping the `calendar_subscriptions`
/// table after the id-list has been collected. The first per-feed
/// SELECT then fails with `SQLITE_ERROR: no such table`, which
/// the post-fix `match` catches as a `Db` / `Validation` variant
/// and writes a per-feed error row instead of aborting.
#[test]
fn sync_all_batch_recovers_from_hard_db_error_mid_loop() {
    use crate::calendar_subscription::sync::sync_all_calendar_subscriptions;

    let conn = test_conn();
    seed_subscription_with_url(&conn, "sub-a", "https://example.com/hard-a.ics");
    seed_subscription_with_url(&conn, "sub-b", "https://example.com/hard-b.ics");

    // FetchBackend interposes a destructive side-effect on its
    // first call: after the orchestrator's per-feed SELECT for the
    // first feed has succeeded (it ran before fetch_ics), drop the
    // table so the next feed's per-feed SELECT fails hard.
    struct TableDroppingBackend<'c> {
        conn: &'c rusqlite::Connection,
        dropped: std::cell::Cell<bool>,
        body: String,
    }
    impl FetchBackend for TableDroppingBackend<'_> {
        fn fetch_ics(
            &self,
            _url: &str,
            _etag: Option<&str>,
        ) -> Result<FetchedIcs, FetchedIcsError> {
            if !self.dropped.get() {
                self.dropped.set(true);
                // Drop the calendar_subscriptions row for the
                // SECOND feed mid-batch so its per-feed SELECT
                // returns NotFound on the next iteration. We avoid
                // dropping the table itself (which would corrupt
                // global test state) by deleting one row.
                self.conn
                    .execute("DELETE FROM calendar_subscriptions WHERE id = 'sub-b'", [])
                    .expect("delete sub-b row mid-batch");
            }
            Ok(FetchedIcs {
                body: self.body.clone(),
                etag: None,
                status: 200,
            })
        }
    }

    let body = "BEGIN:VCALENDAR\n\
                BEGIN:VEVENT\n\
                UID:ea\n\
                SUMMARY:Talk\n\
                DTSTART:20260329T140000Z\n\
                DTEND:20260329T150000Z\n\
                END:VEVENT\n\
                END:VCALENDAR\n";
    let backend = TableDroppingBackend {
        conn: &conn,
        dropped: std::cell::Cell::new(false),
        body: body.to_string(),
    };

    let results = sync_all_calendar_subscriptions(&conn, &backend, &noop_unknown_tzid_sink)
        .expect("batch must not propagate per-feed errors");
    // sub-a succeeds; sub-b's row was deleted between the id-list
    // and the per-feed SELECT, so it errors out. Both must appear.
    assert_eq!(results.len(), 2, "every listed feed produces a row");
    assert!(
        results
            .iter()
            .any(|r| r.subscription_id == "sub-a" && r.error.is_none()),
        "sub-a succeeds: {results:?}",
    );
    assert!(
        results
            .iter()
            .any(|r| r.subscription_id == "sub-b" && r.error.is_some()),
        "sub-b reports an error: {results:?}",
    );
}

/// #4582 B1: a feed that parses cleanly but emits zero events
/// (publisher removed every VEVENT in a single edit) must route
/// through `clear_provider_events_by_scope` so cached events stop
/// lingering as orphans. Pre-fix the diff-delete guard's
/// preserve-arm short-circuited on
/// `current_keys.is_empty() && imported == 0 && updated == 0` and
/// the clean-empty branch was unreachable.
#[test]
fn sync_subscription_content_clears_cached_events_on_clean_empty_feed() {
    let conn = test_conn();
    seed_subscription(&conn, "sub-empty");

    // Seed a cached event from a prior successful poll so the
    // clear-vs-preserve decision is observable.
    lorvex_store::repositories::provider_repo::upsert_provider_event(
        &conn,
        &lorvex_store::repositories::provider_repo::ProviderEventData {
            provider_kind: "ical_subscription",
            provider_scope: "sub-empty",
            provider_event_key: "stale-event",
            title: Some("Removed upstream"),
            description: None,
            start_date: "2026-03-29",
            start_time: Some("09:00"),
            end_date: Some("2026-03-29"),
            end_time: Some("10:00"),
            all_day: false,
            location: None,
            organizer_email: None,
            source_time_kind: "floating",
            source_tzid: None,
            recurrence: None,
            recurrence_exceptions: None,
            color: None,
            attendees_json: None,
            video_call_url: None,
        },
        "2026-03-29T00:00:00Z",
    )
    .expect("seed cached provider event");

    // VCALENDAR with zero VEVENTs — parses cleanly, no skip warnings.
    let result = sync_subscription_content(
        &conn,
        "sub-empty",
        "Test Feed",
        "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n",
        None,
        &noop_unknown_tzid_sink,
    )
    .expect("clean-empty feed must apply without error");

    assert_eq!(result.events_imported, 0);
    assert_eq!(result.events_updated, 0);
    assert_eq!(
        result.events_removed, 1,
        "clean-empty feed must report the cached event as removed: {result:?}",
    );
    assert!(result.error.is_none());

    let remaining_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "ical_subscription",
        Some("sub-empty"),
        None,
    )
    .expect("load cached provider event keys");
    assert!(
        remaining_keys.is_empty(),
        "clean-empty feed must clear cached events; left: {remaining_keys:?}",
    );
}

/// #4582 B3: a transient rusqlite failure on the in-transaction
/// `still_enabled?` re-check must propagate as
/// `CalendarSubscriptionError::Store`, not silently masquerade as
/// "subscription disabled or removed during fetch". Drive the
/// failure by dropping the `calendar_subscriptions` table after the
/// outer transaction has opened — the re-check then hits
/// `SQLITE_ERROR: no such table` which is neither
/// `QueryReturnedNoRows` nor "disabled".
#[test]
fn sync_subscription_content_propagates_transient_errors_on_recheck() {
    use crate::calendar_subscription::error::CalendarSubscriptionError;

    let conn = test_conn();
    seed_subscription(&conn, "sub-busy");
    // Drop the table so the in-transaction `still_enabled?` SELECT
    // fails hard with a non-QueryReturnedNoRows error.
    conn.execute("DROP TABLE calendar_subscriptions", [])
        .expect("drop calendar_subscriptions table");

    let err = sync_subscription_content(
        &conn,
        "sub-busy",
        "Test Feed",
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:e1\n\
         SUMMARY:Lunch\n\
         DTSTART:20260329T090000Z\n\
         DTEND:20260329T100000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
        None,
        &noop_unknown_tzid_sink,
    )
    .expect_err("transient re-check error must propagate, not collapse to 'disabled'");

    match err {
        CalendarSubscriptionError::Store(_)
        | CalendarSubscriptionError::Db(_)
        | CalendarSubscriptionError::Internal(_) => {}
        other => panic!("expected typed Store/Db error, got {other:?}"),
    }
}

/// #4513: `is_terminal_batch_error` classifies a typed disk-full
/// failure as process-wide; recoverable per-feed errors do not
/// trip the short-circuit so the batch keeps draining the queue.
#[test]
fn is_terminal_batch_error_distinguishes_disk_full_from_recoverable() {
    use crate::calendar_subscription::error::CalendarSubscriptionError;
    use crate::calendar_subscription::sync::is_terminal_batch_error;
    use lorvex_store::StoreError;

    let disk_full = CalendarSubscriptionError::Store(StoreError::DiskFull {
        details: "SQLITE_FULL".to_string(),
    });
    assert!(is_terminal_batch_error(&disk_full));

    let stale = CalendarSubscriptionError::Store(StoreError::StaleVersion {
        entity: "calendar_subscription",
        id: "sub-x".to_string(),
    });
    assert!(!is_terminal_batch_error(&stale));

    let validation = CalendarSubscriptionError::Validation("bad URL".to_string());
    assert!(!is_terminal_batch_error(&validation));

    let internal = CalendarSubscriptionError::Internal("rollback".to_string());
    assert!(!is_terminal_batch_error(&internal));
}

/// #4513: a 5-feed batch where feed #2 returns `DiskFull` must
/// abort immediately with the typed error — not collect five
/// duplicate "out of disk space" rows. Feeds #3..#5 must never be
/// invoked. Verified through the test-only `run_batch_loop` helper
/// because the real `FetchBackend` cannot synthesize a typed
/// `StoreError::DiskFull` (the real DB rejects writes only when the
/// filesystem actually runs out).
#[test]
fn sync_all_short_circuits_on_disk_full_mid_batch() {
    use crate::calendar_subscription::error::CalendarSubscriptionError;
    use crate::calendar_subscription::sync::{run_batch_loop, SubscriptionSyncResult};
    use lorvex_store::StoreError;
    use std::cell::Cell;

    let conn = test_conn();
    for (idx, id) in ["sub-1", "sub-2", "sub-3", "sub-4", "sub-5"]
        .iter()
        .enumerate()
    {
        seed_subscription_with_url(&conn, id, &format!("https://example.com/feed-{idx}.ics"));
    }
    let ids = vec![
        "sub-1".to_string(),
        "sub-2".to_string(),
        "sub-3".to_string(),
        "sub-4".to_string(),
        "sub-5".to_string(),
    ];

    let calls = Cell::new(0_u32);
    let result = run_batch_loop(&conn, ids, |id| {
        calls.set(calls.get() + 1);
        if id == "sub-2" {
            return Err(CalendarSubscriptionError::Store(StoreError::DiskFull {
                details: "SQLITE_FULL: out of disk space".to_string(),
            }));
        }
        Ok(SubscriptionSyncResult {
            subscription_id: id.to_string(),
            subscription_name: id.to_string(),
            events_imported: 0,
            events_updated: 0,
            events_removed: 0,
            error: None,
        })
    });

    match result {
        Err(CalendarSubscriptionError::Store(StoreError::DiskFull { .. })) => {}
        other => panic!("expected typed DiskFull error, got {other:?}"),
    }
    assert_eq!(
        calls.get(),
        2,
        "loop must invoke feeds 1 and 2 then stop; later feeds must not be touched",
    );
}
