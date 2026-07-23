use super::*;
use crate::test_support::test_conn;
use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

fn insert_task(conn: &Connection, task_id: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at) \
         VALUES (?1, 'Test', 'open', 2, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [task_id],
    )
    .expect("insert task");
}

fn insert_provider_event(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) {
    conn.execute(
        "INSERT INTO provider_calendar_events \
             (provider_kind, provider_scope, provider_event_key, title, \
              start_date, all_day, last_seen_at, last_refreshed_at) \
         VALUES (?1, ?2, ?3, 'Event', '2026-06-01', 0, \
                 '2026-03-20T10:00:00Z', '2026-03-20T10:00:00Z')",
        params![provider_kind, provider_scope, provider_event_key],
    )
    .expect("insert provider event");
}

fn insert_calendar_subscription(conn: &Connection, id: &str, enabled: bool) {
    conn.execute(
        "INSERT INTO calendar_subscriptions \
             (id, name, url, enabled, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, '0000000000000_0000_feed000000000000', \
                 '2026-03-20T10:00:00Z', '2026-03-20T10:00:00Z')",
        params![
            id,
            format!("Feed {id}"),
            format!("https://example.com/{id}.ics"),
            i64::from(enabled)
        ],
    )
    .expect("insert calendar subscription");
}

/// Insert a `provider_scope_runtime_state` row.
fn set_scope_runtime_state(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    availability_state: &str,
    last_refresh_success_at: Option<&str>,
) {
    let last_refresh_result = last_refresh_success_at.map(|_| "success");
    conn.execute(
        "INSERT OR REPLACE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at, last_refresh_result) \
         VALUES (?1, ?2, 1, ?3, ?4, ?5)",
        params![
            provider_kind,
            provider_scope,
            availability_state,
            last_refresh_success_at,
            last_refresh_result
        ],
    )
    .expect("set scope runtime state");
}

fn set_scope_runtime_failure(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    last_refresh_success_at: Option<&str>,
) {
    conn.execute(
        "INSERT OR REPLACE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at, last_refresh_result) \
         VALUES (?1, ?2, 1, 'enabled', ?3, 'fetch_error')",
        params![provider_kind, provider_scope, last_refresh_success_at],
    )
    .expect("set failing scope runtime state");
}

#[test]
fn upsert_and_remove_provider_link() {
    let conn = test_conn();
    insert_task(&conn, "t1");

    let link = upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();
    assert_eq!(link.task_id, "t1");
    assert_eq!(link.provider_kind, "eventkit");
    assert_eq!(link.provider_event_key, "ek-123");

    let remaining =
        delete_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();
    assert!(remaining.deleted);
    assert!(remaining.before.is_some());
    assert!(remaining.remaining_links.is_empty());
}

#[test]
fn resolved_links_with_cache_hit() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    insert_provider_event(&conn, "eventkit", "", "ek-123");
    set_scope_runtime_state(
        &conn,
        "eventkit",
        "",
        "enabled",
        Some("2026-03-20T10:00:00Z"),
    );
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "resolved");
    assert_eq!(links[0].event_title.as_deref(), Some("Event"));
}

#[test]
fn resolved_links_missing_when_provider_operational_but_event_gone() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    let fresh_success = lorvex_domain::sync_timestamp_now();
    // Provider scope is enabled and has refreshed, but the linked event is absent
    insert_provider_event(&conn, "eventkit", "", "ek-other");
    set_scope_runtime_state(&conn, "eventkit", "", "enabled", Some(&fresh_success));
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-gone").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "missing");
}

#[test]
fn resolved_links_unavailable_when_provider_disabled() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    // Scope exists but is disabled
    set_scope_runtime_state(
        &conn,
        "eventkit",
        "",
        "disabled",
        Some("2026-03-20T10:00:00Z"),
    );
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "unavailable");
}

#[test]
fn resolved_links_unavailable_when_no_runtime_state_row() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    // No provider_scope_runtime_state row at all → never configured
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "unavailable");
}

#[test]
fn resolved_links_pending_when_scope_enabled_but_never_refreshed() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    // Scope is enabled but has not completed a refresh yet, so absence
    // is not evidence that the upstream event is gone.
    set_scope_runtime_state(&conn, "eventkit", "", "enabled", None);
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "pending");
}

#[test]
fn resolved_links_stale_when_scope_success_is_too_old() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    set_scope_runtime_state(
        &conn,
        "eventkit",
        "",
        "enabled",
        Some("2000-01-01T00:00:00.000Z"),
    );
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "stale");
}

#[test]
fn resolved_links_unavailable_when_enabled_scope_is_currently_failing() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    set_scope_runtime_failure(&conn, "eventkit", "", Some("2000-01-01T00:00:00.000Z"));
    upsert_provider_event_link(&conn, &tid("t1"), "eventkit", "", "ek-123").unwrap();

    let links = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].resolution_state, "unavailable");
}

#[test]
fn scope_aware_ical_subscription_missing_vs_unavailable() {
    let conn = test_conn();
    insert_task(&conn, "t1");
    insert_task(&conn, "t2");
    insert_task(&conn, "t3");
    let fresh_success = lorvex_domain::sync_timestamp_now();

    // Subscription "sub-A" is enabled and has refreshed
    insert_calendar_subscription(&conn, "sub-A", true);
    insert_provider_event(&conn, "ical_subscription", "sub-A", "uid-1");
    set_scope_runtime_state(
        &conn,
        "ical_subscription",
        "sub-A",
        "enabled",
        Some(&fresh_success),
    );
    // Subscription "sub-B" exists and is enabled but has no runtime row yet:
    // it is waiting for first refresh, not unavailable and not stale.
    insert_calendar_subscription(&conn, "sub-B", true);
    // Subscription "sub-C" does not exist locally, so its link is unavailable.

    // Link t1 to a non-existent event under sub-A (refreshed → missing)
    upsert_provider_event_link(&conn, &tid("t1"), "ical_subscription", "sub-A", "uid-gone")
        .unwrap();
    // Link t2 to an event under sub-B (enabled, never refreshed → pending)
    upsert_provider_event_link(&conn, &tid("t2"), "ical_subscription", "sub-B", "uid-x").unwrap();
    // Link t3 to an event under sub-C (no local subscription → unavailable)
    upsert_provider_event_link(&conn, &tid("t3"), "ical_subscription", "sub-C", "uid-x").unwrap();

    let links_t1 = get_resolved_provider_links_for_task(&conn, &tid("t1")).unwrap();
    assert_eq!(links_t1[0].resolution_state, "missing");

    let links_t2 = get_resolved_provider_links_for_task(&conn, &tid("t2")).unwrap();
    assert_eq!(links_t2[0].resolution_state, "pending");

    let links_t3 = get_resolved_provider_links_for_task(&conn, &tid("t3")).unwrap();
    assert_eq!(links_t3[0].resolution_state, "unavailable");
}

#[test]
fn scope_queryable_when_availability_enabled() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO provider_scope_runtime_state (provider_kind, provider_scope, enabled, availability_state)
         VALUES ('eventkit', '', 1, 'enabled')",
        [],
    ).unwrap();
    assert!(is_provider_scope_queryable(&conn, "eventkit", "").unwrap());
}

#[test]
fn scope_not_queryable_when_permission_denied() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO provider_scope_runtime_state (provider_kind, provider_scope, enabled, availability_state)
         VALUES ('eventkit', '', 1, 'permission_denied')",
        [],
    ).unwrap();
    assert!(!is_provider_scope_queryable(&conn, "eventkit", "").unwrap());
}

#[test]
fn scope_not_queryable_when_no_runtime_state() {
    let conn = test_conn();
    // No row in provider_scope_runtime_state → not queryable
    assert!(!is_provider_scope_queryable(&conn, "eventkit", "").unwrap());
}

/// a stale concurrent provider refresh that lost
/// the BEGIN race must NOT clobber the winner's row. The UPDATE
/// branch is gated on `?20 >= last_seen_at` so an older `now`
/// arriving second is monotonicity-rejected.
#[test]
fn upsert_provider_event_rejects_stale_last_seen_at() {
    let conn = test_conn();
    let event = ProviderEventData {
        provider_kind: "ical_subscription",
        provider_scope: "feed-1",
        provider_event_key: "evt-1",
        title: Some("Initial"),
        description: None,
        start_date: "2026-06-01",
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: true,
        location: None,
        organizer_email: None,
        source_time_kind: "floating",
        source_tzid: None,
        recurrence: None,
        recurrence_exceptions: None,
        color: None,
        attendees_json: None,
        video_call_url: None,
    };
    // First insert lands.
    let outcome = upsert_provider_event(&conn, &event, "2026-04-28T12:00:00.000Z").unwrap();
    assert_eq!(outcome, ProviderEventUpsertOutcome::Inserted);

    // Winning concurrent refresh advances last_seen_at.
    let winner = ProviderEventData {
        title: Some("Winner"),
        ..event
    };
    let outcome = upsert_provider_event(&conn, &winner, "2026-04-28T12:05:00.000Z").unwrap();
    assert_eq!(outcome, ProviderEventUpsertOutcome::Updated);

    // Loser carries an older `now` (clock skew or queued-out-of-order
    // refresh) — the predicate must reject the UPDATE so the
    // winner's `Winner` title and timestamp survive.
    let loser = ProviderEventData {
        title: Some("Loser"),
        ..event
    };
    let outcome = upsert_provider_event(&conn, &loser, "2026-04-28T12:01:00.000Z").unwrap();
    assert_eq!(outcome, ProviderEventUpsertOutcome::Unchanged);

    let (title, last_seen): (String, String) = conn
        .query_row(
            "SELECT title, last_seen_at FROM provider_calendar_events \
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'feed-1' \
               AND provider_event_key = 'evt-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(
        title, "Winner",
        "stale racing refresh must not clobber the winner's title"
    );
    assert_eq!(last_seen, "2026-04-28T12:05:00.000Z");
}

#[test]
fn upsert_provider_event_reports_unchanged_for_refresh_without_visible_changes() {
    let conn = test_conn();
    let event = ProviderEventData {
        provider_kind: "ical_subscription",
        provider_scope: "feed-1",
        provider_event_key: "evt-1",
        title: Some("Stable"),
        description: Some("unchanged"),
        start_date: "2026-06-01",
        start_time: Some("09:00"),
        end_date: Some("2026-06-01"),
        end_time: Some("10:00"),
        all_day: false,
        location: Some("Room"),
        organizer_email: Some("owner@example.com"),
        source_time_kind: "tzid",
        source_tzid: Some("America/New_York"),
        recurrence: None,
        recurrence_exceptions: None,
        color: Some("#123456"),
        attendees_json: Some("[]"),
        video_call_url: Some("https://example.com/meet"),
    };

    let outcome = upsert_provider_event(&conn, &event, "2026-04-28T12:00:00.000Z").unwrap();
    assert_eq!(outcome, ProviderEventUpsertOutcome::Inserted);

    let outcome = upsert_provider_event(&conn, &event, "2026-04-28T12:10:00.000Z").unwrap();
    assert_eq!(outcome, ProviderEventUpsertOutcome::Unchanged);

    let last_seen: String = conn
        .query_row(
            "SELECT last_seen_at FROM provider_calendar_events \
             WHERE provider_kind = 'ical_subscription' AND provider_scope = 'feed-1' \
               AND provider_event_key = 'evt-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(last_seen, "2026-04-28T12:10:00.000Z");
}

#[cfg(test)]
mod wire_format_3286 {
    use super::super::{ProviderEventLinkWithResolution, TaskProviderEventLink};
    use lorvex_domain::time::{Date, SyncTimestamp, TimeOfDay};

    /// Wire-format byte-stability check (#3286): the typed
    /// `SyncTimestamp` / `Date` / `TimeOfDay` newtypes serialize as the
    /// exact same canonical strings the columns were always written
    /// with, so JSON envelopes / sync payload-shadow blobs / MCP
    /// responses keep byte-identical bytes across the migration.
    #[test]
    fn task_provider_event_link_serde_byte_identical_to_pre_3286_shape() {
        let link = TaskProviderEventLink {
            task_id: "task-1".to_string(),
            provider_kind: "eventkit".to_string(),
            provider_scope: "default".to_string(),
            provider_event_key: "ek-123".to_string(),
            created_at: SyncTimestamp::parse("2026-04-19T08:30:00.000Z").unwrap(),
            updated_at: SyncTimestamp::parse("2026-04-19T09:00:00.000Z").unwrap(),
        };
        let json = serde_json::to_string(&link).unwrap();
        // Exact byte match against the pre-#3286 shape (every field a
        // bare JSON string for `SyncTimestamp`).
        assert_eq!(
            json,
            r#"{"task_id":"task-1","provider_kind":"eventkit","provider_scope":"default","provider_event_key":"ek-123","created_at":"2026-04-19T08:30:00.000Z","updated_at":"2026-04-19T09:00:00.000Z"}"#
        );
    }

    #[test]
    fn provider_event_link_with_resolution_serde_byte_identical_to_pre_3286_shape() {
        let link = ProviderEventLinkWithResolution {
            task_id: "task-1".to_string(),
            provider_kind: "eventkit".to_string(),
            provider_scope: "default".to_string(),
            provider_event_key: "ek-123".to_string(),
            created_at: SyncTimestamp::parse("2026-04-19T08:30:00.000Z").unwrap(),
            updated_at: SyncTimestamp::parse("2026-04-19T09:00:00.000Z").unwrap(),
            event_title: Some("Standup".to_string()),
            event_start_date: Some(Date::parse("2026-04-19").unwrap()),
            event_start_time: Some(TimeOfDay::parse("09:30").unwrap()),
            resolution_state: "resolved".to_string(),
        };
        let json = serde_json::to_string(&link).unwrap();
        assert_eq!(
            json,
            r#"{"task_id":"task-1","provider_kind":"eventkit","provider_scope":"default","provider_event_key":"ek-123","created_at":"2026-04-19T08:30:00.000Z","updated_at":"2026-04-19T09:00:00.000Z","event_title":"Standup","event_start_date":"2026-04-19","event_start_time":"09:30","resolution_state":"resolved"}"#
        );
    }
}
