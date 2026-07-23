//! Parsed-body apply: walk the parsed VEVENTs, upsert each row, and
//! diff-delete cached events that the publisher dropped from the
//! feed, all inside a single immediate transaction so a crash never
//! leaves the cache in a half-applied state.
//!
//! The transaction also re-checks `enabled = 1` so a concurrent
//! `remove_calendar_subscription` cannot land orphan events into a
//! just-deleted scope.

use rusqlite::params;

use lorvex_domain::sync_timestamp_now;
use lorvex_store::repositories::provider_repo::{self, ProviderScopeTransition};
use lorvex_store::with_immediate_transaction;

use super::super::error::CalendarSubscriptionError;
use super::super::parse::{
    parse_ics_events_with_diagnostics, rrule_to_json_with_warnings, IcsParseWarning,
};
use super::super::scheduling::{record_subscription_failure, record_subscription_success};
use super::super::tzid::UnknownTzidSink;
use super::types::SubscriptionSyncResult;

/// Apply a parsed ICS body to the cached provider events for one
/// subscription scope, gated on the subscription still being enabled
/// inside the transaction so a concurrent disable / remove cannot
/// land orphan events.
pub fn sync_subscription_content(
    conn: &rusqlite::Connection,
    id: &str,
    name: &str,
    ics_content: &str,
    sub_color: Option<&str>,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> Result<SubscriptionSyncResult, CalendarSubscriptionError> {
    let parse_report = match parse_ics_events_with_diagnostics(ics_content, unknown_tzid_sink) {
        Ok(report) => report,
        Err(err) => {
            let now = sync_timestamp_now();
            let err_str = err.to_string();
            // Wrap the parse-error short-circuit's two writes in a
            // single immediate transaction so a crash between
            // `update_provider_scope_state` and
            // `record_subscription_failure` cannot leave the feed
            // flagged parse_error without the backoff bumped — which
            // would let the scheduler retry every 60m indefinitely
            return with_immediate_transaction::<_, CalendarSubscriptionError>(conn, |conn| {
                provider_repo::update_provider_scope_state(
                    conn,
                    "ical_subscription",
                    id,
                    ProviderScopeTransition::RefreshError {
                        now: &now,
                        error: &err_str,
                        result_label: "parse_error",
                    },
                )?;
                // a parse failure advances the backoff — otherwise a
                // feed that ships a corrupted body every time would get
                // retried every 60m indefinitely. No Retry-After hint
                // applies here (parse failure is client-side, not a 429
                // response).
                record_subscription_failure(conn, id, &now, None)?;
                Ok(SubscriptionSyncResult {
                    subscription_id: id.to_string(),
                    subscription_name: name.to_string(),
                    events_imported: 0,
                    events_updated: 0,
                    events_removed: 0,
                    error: Some(err_str.clone()),
                })
            });
        }
    };
    let events = parse_report.events;
    let mut parser_warnings = parse_report.warnings;
    // Per-VEVENT skip warnings are emitted during the initial parse;
    // any non-empty set means some VEVENTs in the feed could not be
    // interpreted on this pass. Capture that signal before the RRULE
    // post-pass appends its own warnings so the diff-delete guard
    // below can distinguish a clean feed from a partial-parse feed.
    //
    // Tracked separately from `events.is_empty()` so the diff-delete
    // guard can route a clean-but-empty feed (publisher removed every
    // VEVENT in a single edit) to `clear_provider_events_by_scope`
    // instead of falling through to the preserve-arm. Without the
    // split, the guard would short-circuit on `current_keys.is_empty()
    // && imported == 0 && updated == 0` and silently leak orphan
    // cached events forever.
    let parse_had_skip_warnings = !parser_warnings.is_empty();
    let parsed_event_count = events.len();

    // wrap the entire apply (upserts + diff-deletes + success mark)
    // in a single transaction. Without this:
    //   - SIGKILL / power loss mid-loop left half the feed upserted
    //     and stale events not-yet-deleted, so the user sees
    //     duplicate or orphan calendar entries until they notice
    //     and refresh.
    //   - SQLITE_FULL on upsert N of M auto-committed rows 1..N-1,
    //     never hit `record_refresh_success`, and on the next
    //     refresh existing rows were re-reported as
    //     imported/updated (counts diverged from reality).
    //   - Readers could see half-applied state.
    //   - A concurrent `remove_calendar_subscription` could delete
    //     the subscription row mid-apply and we'd happily upsert
    //     orphan events into the just-deleted scope.
    //
    // Re-checking `enabled = 1` inside the transaction closes the
    // last race: if the user disabled the subscription during HTTP,
    // the transaction short-circuits with zero writes.
    let now = sync_timestamp_now();
    with_immediate_transaction::<_, CalendarSubscriptionError>(conn, |conn| {
        // Match the Result so a transient rusqlite failure
        // (SQLITE_BUSY, IO, schema drift) propagates as
        // `CalendarSubscriptionError::Store` rather than masquerading
        // as "subscription disabled or removed". The previous
        // `.unwrap_or(false)` swallowed lock contention as the
        // short-circuit path, so a 429-busy database left the user
        // with the misleading "subscription removed" error and no
        // events applied.
        let still_enabled: bool = match conn.query_row(
            "SELECT 1 FROM calendar_subscriptions WHERE id = ?1 AND enabled = 1",
            params![id],
            |_row| Ok(true),
        ) {
            Ok(_) => true,
            Err(rusqlite::Error::QueryReturnedNoRows) => false,
            Err(err) => return Err(CalendarSubscriptionError::from(err)),
        };
        if !still_enabled {
            return Ok(SubscriptionSyncResult {
                subscription_id: id.to_string(),
                subscription_name: name.to_string(),
                events_imported: 0,
                events_updated: 0,
                events_removed: 0,
                error: Some("subscription disabled or removed during fetch".to_string()),
            });
        }

        let mut imported = 0i64;
        let mut updated = 0i64;

        for event in &events {
            // provider_event_key: bare UID for master events,
            // UID+RECURRENCE-ID for detached overrides (spec doc 19).
            let provider_event_key = match &event.recurrence_id {
                Some(rid) => format!("{}+{}", event.uid, rid),
                None => event.uid.clone(),
            };

            let recurrence_json = event
                .rrule
                .as_deref()
                .and_then(|raw| rrule_to_json_with_warnings(raw, &mut parser_warnings));
            let outcome = provider_repo::upsert_provider_event(
                conn,
                &provider_repo::ProviderEventData {
                    provider_kind: "ical_subscription",
                    provider_scope: id,
                    provider_event_key: &provider_event_key,
                    title: Some(event.summary.as_str()),
                    description: event.description.as_deref(),
                    start_date: &event.start_date,
                    start_time: event.start_time.as_deref(),
                    end_date: event.end_date.as_deref(),
                    end_time: event.end_time.as_deref(),
                    all_day: event.all_day,
                    location: event.location.as_deref(),
                    organizer_email: event.organizer.as_deref(),
                    source_time_kind: &event.source_time_kind,
                    source_tzid: event.source_tzid.as_deref(),
                    recurrence: recurrence_json.as_deref(),
                    recurrence_exceptions: event.exdates_json.as_deref(),
                    color: sub_color,
                    attendees_json: event.attendees_json.as_deref(),
                    video_call_url: event.url.as_deref(),
                },
                &now,
            )?;
            match outcome {
                provider_repo::ProviderEventUpsertOutcome::Inserted => {
                    imported += 1;
                }
                provider_repo::ProviderEventUpsertOutcome::Updated => {
                    updated += 1;
                }
                provider_repo::ProviderEventUpsertOutcome::Unchanged => {}
            }
        }

        let current_keys: std::collections::HashSet<String> = events
            .iter()
            .map(|e| match &e.recurrence_id {
                Some(rid) => format!("{}+{}", e.uid, rid),
                None => e.uid.clone(),
            })
            .collect();

        let removed: i64 = if parsed_event_count == 0 && parse_had_skip_warnings {
            // Parser emitted zero events but flagged skip warnings —
            // every VEVENT in this poll was malformed. Preserving the
            // cached entries prevents silent data loss when a feed
            // publisher temporarily ships a corrupted body.
            0
        } else if parsed_event_count == 0 {
            // Parser succeeded cleanly and emitted zero events: the
            // publisher has genuinely emptied the feed. Route to the
            // clear path so cached events do not linger as orphans
            // . The preserve-arm above stays reserved for
            // partial-parse / parse-failed cases.
            provider_repo::clear_provider_events_by_scope(conn, "ical_subscription", id)? as i64
        } else if parse_had_skip_warnings {
            // Feed parsed only partially — some VEVENTs were skipped
            // with warnings. Absent UIDs in `current_keys` may simply
            // be the skipped events, not removals upstream. Preserving
            // the cached entries prevents silent data loss when a feed
            // publisher temporarily ships a malformed VEVENT
            0
        } else {
            // Remove events whose provider_event_key is not in the current feed.
            let mut count = 0i64;
            let cached_keys =
                provider_repo::get_provider_event_keys(conn, "ical_subscription", Some(id), None)?;

            for existing_key in &cached_keys {
                if !current_keys.contains(existing_key) {
                    provider_repo::delete_provider_event(
                        conn,
                        "ical_subscription",
                        id,
                        existing_key,
                    )?;
                    count += 1;
                }
            }
            count
        };

        persist_ics_parse_warnings(conn, id, name, &parser_warnings);

        // Update fetch state (device-local runtime state, not synced).
        provider_repo::update_provider_scope_state(
            conn,
            "ical_subscription",
            id,
            ProviderScopeTransition::RefreshSuccess { now: &now },
        )?;

        // a successful refresh resets the per-subscription backoff
        // so the next tick follows the normal 60m cadence again.
        record_subscription_success(conn, id)?;

        Ok(SubscriptionSyncResult {
            subscription_id: id.to_string(),
            subscription_name: name.to_string(),
            events_imported: imported,
            events_updated: updated,
            events_removed: removed,
            error: None,
        })
    })
}

fn persist_ics_parse_warnings(
    conn: &rusqlite::Connection,
    subscription_id: &str,
    subscription_name: &str,
    warnings: &[IcsParseWarning],
) {
    for warning in warnings {
        let mut details =
            format!("subscription_id={subscription_id}; subscription_name={subscription_name}");
        if let Some(warning_details) = warning.details.as_deref() {
            details.push_str("; ");
            details.push_str(warning_details);
        }
        let _ = lorvex_store::error_log::append_error_log(
            conn,
            warning.source,
            &warning.message,
            Some(&details),
            Some("warn"),
        );
    }
}
