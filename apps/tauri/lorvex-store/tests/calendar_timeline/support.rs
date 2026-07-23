pub(super) use lorvex_domain::CalendarAiAccessMode;
pub(super) use lorvex_store::calendar_timeline::queries::{
    get_calendar_timeline, get_day_blocking_ranges, search_calendar_events,
};
pub(super) use lorvex_store::calendar_timeline::types::TimelineSource;
pub(super) use lorvex_store::open_db_in_memory;
use rusqlite::Connection;

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
pub(super) fn insert_canonical_event(
    conn: &Connection,
    id: &str,
    title: &str,
    start_date: &str,
    start_time: Option<&str>,
    end_date: Option<&str>,
    end_time: Option<&str>,
    all_day: bool,
    recurrence: Option<&str>,
    recurrence_exceptions: Option<&str>,
) {
    conn.execute(
        "INSERT INTO calendar_events \
             (id, title, start_date, start_time, end_date, end_time, all_day, \
              recurrence, event_type, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'event', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        rusqlite::params![
            id,
            title,
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
            recurrence,
        ],
    )
    .expect("insert canonical event");
    lorvex_store::recurrence_exceptions::replace_event_exceptions_from_json(
        conn,
        id,
        recurrence_exceptions,
    )
    .expect("seed canonical event exceptions");
}

#[allow(clippy::too_many_arguments)]
pub(super) fn insert_provider_event(
    conn: &Connection,
    kind: &str,
    scope: &str,
    key: &str,
    title: &str,
    start_date: &str,
    start_time: Option<&str>,
    end_date: Option<&str>,
    end_time: Option<&str>,
    all_day: bool,
    recurrence: Option<&str>,
    recurrence_exceptions: Option<&str>,
) {
    conn.execute(
        "INSERT INTO provider_calendar_events \
             (provider_kind, provider_scope, provider_event_key, \
              title, start_date, start_time, end_date, end_time, all_day, \
              recurrence, recurrence_exceptions, event_type, \
              last_seen_at, last_refreshed_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'event', \
                 '2026-03-25T00:00:00Z', '2026-03-25T00:00:00Z')",
        rusqlite::params![
            kind,
            scope,
            key,
            title,
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
            recurrence,
            recurrence_exceptions,
        ],
    )
    .expect("insert provider event");
    // Ensure the scope is marked as enabled so queries include it.
    conn.execute(
        "INSERT OR IGNORE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at) \
         VALUES (?1, ?2, 1, 'enabled', '2026-03-25T00:00:00.000Z')",
        rusqlite::params![kind, scope],
    )
    .expect("insert provider runtime state");
}
