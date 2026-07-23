use super::*;

#[test]
fn fetch_ics_preserves_cached_events_on_truncation_rejection() {
    // Mirrors `sync_subscription_content_inner_preserves_cached_events_on_parse_error`
    // but for the truncation-rejection path. On a truncated
    // response the caller MUST NOT invoke the apply pipeline:
    // the previously cached events stay in place and the feed's
    // `last_error` gains the dedicated `sync.ics.truncated`
    // label so the scheduler can distinguish a transient
    // truncation from a permanent fetch failure.
    let conn = setup();
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 1, ?4, ?5, ?5)",
        rusqlite::params![
            "sub-trunc",
            "Truncated Feed",
            "https://example.com/feed.ics",
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert subscription");

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
        "Truncated Feed",
        "2026-03-29T00:05:00Z",
        IcsTruncationReason::UnbalancedVeventCount { begins: 2, ends: 1 },
        "https://example.com/feed.ics",
    )
    .expect("truncation rejection must persist without erroring");

    assert_eq!(result.events_imported, 0);
    assert_eq!(result.events_updated, 0);
    assert_eq!(result.events_removed, 0);
    let error_msg = result
        .error
        .as_deref()
        .expect("truncation result must carry a user-visible error");
    assert!(
        error_msg.contains(ICS_TRUNCATION_MESSAGE),
        "error should contain the truncation summary, got: {error_msg}"
    );
    assert!(
        error_msg.contains("https://example.com/feed.ics"),
        "error should include the sanitized URL, got: {error_msg}"
    );

    // The cached event MUST still be present — truncation
    // rejection never runs the diff-delete pass.
    let remaining_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "ical_subscription",
        Some("sub-trunc"),
        None,
    )
    .expect("load cached provider event keys");
    assert_eq!(remaining_keys, vec!["cached-event".to_string()]);

    // The provider-scope runtime state's `last_refresh_result`
    // is a closed CHECK enum — a truncated response classifies
    // as `fetch_error` there, and the dedicated
    // `sync.ics.truncated` signal goes to the `error_logs`
    // table (asserted below) where `source` is free-form.
    let (avail_state, last_result, last_error): (String, String, String) = conn
        .query_row(
            "SELECT availability_state, last_refresh_result, last_error
             FROM provider_scope_runtime_state
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'sub-trunc'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load provider scope runtime state");
    assert_eq!(last_result, "fetch_error");
    assert_eq!(avail_state, "fetch_error");
    assert!(
        last_error.contains(ICS_TRUNCATION_MESSAGE),
        "last_error should preserve the truncation summary, got: {last_error}"
    );

    // The dedicated diagnostic log row carries the
    // `sync.ics.truncated` source so Settings → Diagnostics
    // can filter on it directly.
    let log_row: (String, String, String, Option<String>) = conn
        .query_row(
            "SELECT source, level, message, details FROM error_logs
             ORDER BY created_at DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("load most recent error_logs row");
    assert_eq!(
        log_row.0,
        lorvex_workflow::calendar_subscription::sync::ICS_TRUNCATION_LOG_SOURCE,
    );
    assert_eq!(log_row.1, "warn");
    assert!(
        log_row.2.contains(ICS_TRUNCATION_MESSAGE),
        "error_logs message should contain the truncation summary, got: {}",
        log_row.2
    );
    let details = log_row
        .3
        .as_deref()
        .expect("error_logs details should carry context");
    assert!(
        details.contains("sub-trunc") && details.contains("https://example.com/feed.ics"),
        "error_logs details should include the subscription id and sanitized URL, got: {details}"
    );
}

#[test]
fn detect_ics_truncation_matches_case_insensitively() {
    // Some enterprise calendar exporters normalize property
    // names to lowercase (notably Zimbra). The truncation
    // detector must count those too — otherwise a lowercase
    // `end:vevent` would fail to balance against an uppercase
    // `BEGIN:VEVENT` and produce a spurious rejection.
    let body = "BEGIN:VCALENDAR\n\
                begin:vevent\nUID:x\nSUMMARY:Y\nDTSTART:20260401T090000Z\nend:vevent\n\
                END:VCALENDAR\n";
    detect_ics_truncation(body)
        .expect("lowercase VEVENT markers must be counted the same as uppercase");
}

#[test]
fn sync_subscription_content_inner_preserves_cached_events_on_parse_error() {
    let conn = setup();
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 1, ?4, ?5, ?5)",
        rusqlite::params![
            "sub-1",
            "Test Feed",
            "https://example.com/feed.ics",
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert subscription");

    lorvex_store::repositories::provider_repo::upsert_provider_event(
        &conn,
        &lorvex_store::repositories::provider_repo::ProviderEventData {
            provider_kind: "ical_subscription",
            provider_scope: "sub-1",
            provider_event_key: "existing-event",
            title: Some("Existing"),
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

    let result = sync_subscription_content_inner(
        &conn,
        "sub-1",
        "Test Feed",
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:test-1\nSUMMARY:Broken\nDTSTART:not-a-date\nEND:VEVENT\nEND:VCALENDAR\n",
        None,
    )
    .expect("parse failures should return subscription error result");

    assert_eq!(result.subscription_id, "sub-1");
    // With resilient parsing, the malformed VEVENT is skipped (not fatal).
    // The parse returns 0 valid events. The cached event is removed because
    // it is no longer present in the feed results.
    assert_eq!(result.events_imported, 0);
    assert_eq!(result.events_updated, 0);
    // The previously cached event is removed since the parse returned no
    // matching events for this subscription scope.
    assert!(
        result.error.is_none(),
        "resilient parsing should not produce an error: {:?}",
        result.error
    );

    let remaining_keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "ical_subscription",
        Some("sub-1"),
        None,
    )
    .expect("load cached provider event keys");
    assert_eq!(remaining_keys, vec!["existing-event".to_string()]);

    let refresh_state: (String, String) = conn
        .query_row(
            "SELECT availability_state, last_refresh_result
             FROM provider_scope_runtime_state
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'sub-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load provider scope runtime state");
    // With resilient parsing, the sync succeeds (no parse error).
    // The runtime state reflects a successful refresh, not an error.
    assert_eq!(refresh_state.0, "enabled");
    assert_eq!(refresh_state.1, "success");
}

#[test]
fn sync_subscription_content_inner_persists_recoverable_parser_warnings() {
    let conn = setup();
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 1, ?4, ?5, ?5)",
        rusqlite::params![
            "sub-warn",
            "Warning Feed",
            "https://example.com/feed.ics",
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert subscription");

    let result = sync_subscription_content_inner(
        &conn,
        "sub-warn",
        "Warning Feed",
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:warn-1\n\
         SUMMARY:Valid with unsupported recurrence\n\
         DTSTART:20260329T090000Z\n\
         DTEND:20260329T100000Z\n\
         RRULE:FREQ=WEEKLY;BYHOUR=9\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
        None,
    )
    .expect("recoverable parser warnings should not fail sync");

    assert_eq!(result.events_imported, 1);
    assert!(result.error.is_none());

    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.ics.parser_warning'
               AND level = 'warn'
               AND message LIKE '%unsupported RRULE%'",
            [],
            |row| row.get(0),
        )
        .expect("count persisted parser warning");
    assert_eq!(
        log_count, 1,
        "recoverable ICS parser diagnostics must persist to error_logs"
    );
}

#[test]
fn sync_subscription_content_inner_persists_parser_report_warnings() {
    let conn = setup();
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 1, ?4, ?5, ?5)",
        rusqlite::params![
            "sub-parse-warn",
            "Parser Warning Feed",
            "https://example.com/feed.ics",
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert subscription");

    let result = sync_subscription_content_inner(
        &conn,
        "sub-parse-warn",
        "Parser Warning Feed",
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:good\n\
         SUMMARY:Valid event\n\
         DTSTART:20260329T090000Z\n\
         DTEND:20260329T100000Z\n\
         END:VEVENT\n\
         BEGIN:VEVENT\n\
         UID:bad\n\
         SUMMARY:Broken event\n\
         DTSTART:not-a-date\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
        None,
    )
    .expect("recoverable parser report warnings should not fail sync");

    assert_eq!(result.events_imported, 1);
    assert!(result.error.is_none());

    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.ics.parser_warning'
               AND level = 'warn'
               AND message LIKE '%malformed VEVENT%'
               AND details LIKE '%subscription_id=sub-parse-warn%'",
            [],
            |row| row.get(0),
        )
        .expect("count persisted parser report warning");
    assert_eq!(
        log_count, 1,
        "parser-returned ICS diagnostics must persist to error_logs"
    );
}

#[test]
fn sync_subscription_content_inner_skips_writes_when_subscription_disabled_mid_apply() {
    // if the user disables/deletes the subscription
    // between the HTTP fetch (outside the writer lock) and the
    // apply (inside a transaction), the apply must not write
    // orphan events into the just-removed scope.
    let conn = setup();
    conn.execute(
        "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, NULL, 0, ?4, ?5, ?5)",
        rusqlite::params![
            "sub-disabled",
            "Disabled",
            "https://example.com/feed.ics",
            "v1",
            "2026-03-29T00:00:00Z"
        ],
    )
    .expect("insert disabled subscription");

    let result = sync_subscription_content_inner(
        &conn,
        "sub-disabled",
        "Disabled",
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:e1\nSUMMARY:Should not land\nDTSTART:20260329T090000Z\nDTEND:20260329T100000Z\nEND:VEVENT\nEND:VCALENDAR\n",
        None,
    )
    .expect("disabled subscription should return Ok result");

    assert_eq!(result.events_imported, 0);
    assert_eq!(result.events_updated, 0);
    assert!(
        result.error.is_some(),
        "expected disabled-subscription error"
    );

    let keys = lorvex_store::repositories::provider_repo::get_provider_event_keys(
        &conn,
        "ical_subscription",
        Some("sub-disabled"),
        None,
    )
    .expect("load keys");
    assert!(
        keys.is_empty(),
        "no events should land into a disabled subscription's scope"
    );
}
