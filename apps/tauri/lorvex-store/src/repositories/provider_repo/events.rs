use crate::error::StoreError;
use rusqlite::{params, Connection};

// ---------------------------------------------------------------------------
// Provider event cache operations (provider_calendar_events table)
// ---------------------------------------------------------------------------

/// Data for upserting a provider calendar event into the local cache.
///
/// All fields mirror the `provider_calendar_events` table columns. The caller
/// is responsible for extracting these from the native API (EventKit, Linux
/// ICS, iCalendar subscription) — the shared repo only handles the SQL.
pub struct ProviderEventData<'a> {
    pub provider_kind: &'a str,
    pub provider_scope: &'a str,
    pub provider_event_key: &'a str,
    pub title: Option<&'a str>,
    pub description: Option<&'a str>,
    pub start_date: &'a str,
    pub start_time: Option<&'a str>,
    pub end_date: Option<&'a str>,
    pub end_time: Option<&'a str>,
    pub all_day: bool,
    pub location: Option<&'a str>,
    pub organizer_email: Option<&'a str>,
    /// Original time kind: `"floating"`, `"utc"`, or `"tzid"`.
    pub source_time_kind: &'a str,
    /// Original IANA timezone identifier when `source_time_kind == "tzid"`.
    pub source_tzid: Option<&'a str>,
    /// Raw RRULE string from the ICS feed (e.g., "FREQ=WEEKLY;BYDAY=MO").
    /// Stored in the `recurrence` column for timeline expansion.
    pub recurrence: Option<&'a str>,
    /// JSON array of excluded dates: `["2026-04-05","2026-04-12"]`.
    /// Parsed from EXDATE properties in ICS feeds or from native calendar APIs.
    pub recurrence_exceptions: Option<&'a str>,
    /// Display color (hex, e.g. "#4A90D9"). Comes from the parent calendar
    /// (subscription color, EventKit calendar color, etc.).
    pub color: Option<&'a str>,
    /// JSON array of attendees: `[{"email":"...","name":"...","status":"accepted"}]`.
    pub attendees_json: Option<&'a str>,
    /// Video call URL or generic event URL (e.g., Zoom/Meet link or ICS URL property).
    pub video_call_url: Option<&'a str>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderEventUpsertOutcome {
    Inserted,
    Updated,
    Unchanged,
}

/// Upsert a provider calendar event into the local cache.
///
/// Inserts new provider rows, updates existing rows only when user-visible event
/// content changed, and otherwise refreshes provider timestamps without counting
/// the row as an event update.
pub fn upsert_provider_event(
    conn: &Connection,
    event: &ProviderEventData<'_>,
    now: &str,
) -> Result<ProviderEventUpsertOutcome, StoreError> {
    // Use `INSERT … ON CONFLICT DO NOTHING` so the insert path
    // collapses to a single statement instead of three round-trips
    // (SELECT EXISTS → INSERT-on-conflict-update). `Connection::
    // execute` returns rows-affected, which is 1 when we genuinely
    // inserted and 0 when the conflict suppressed the row — enough
    // to distinguish imported vs updated for the caller's tally.
    // The update path stays at two round-trips but no longer pays
    // a SELECT EXISTS just to compute `was_inserted`.
    if conn.prepare_cached(
        "INSERT INTO provider_calendar_events \
             (provider_kind, provider_scope, provider_event_key, \
              title, description, start_date, start_time, \
              end_date, end_time, all_day, location, organizer_email, \
              source_time_kind, source_tzid, recurrence, recurrence_exceptions, \
              color, attendees_json, video_call_url, \
              last_seen_at, last_refreshed_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?20) \
         ON CONFLICT(provider_kind, provider_scope, provider_event_key) DO NOTHING",
    )?.execute(
        params![
            event.provider_kind,
            event.provider_scope,
            event.provider_event_key,
            event.title,
            event.description,
            event.start_date,
            event.start_time,
            event.end_date,
            event.end_time,
            i64::from(event.all_day),
            event.location,
            event.organizer_email,
            event.source_time_kind,
            event.source_tzid,
            event.recurrence,
            event.recurrence_exceptions,
            event.color,
            event.attendees_json,
            event.video_call_url,
            now,
        ],
    )? == 1
    {
        return Ok(ProviderEventUpsertOutcome::Inserted);
    }

    // Conflict path — update user-visible fields only when they
    // changed. A routine provider refresh that touches only
    // last_seen_at/last_refreshed_at must not inflate the caller's
    // "updated event" count or trigger broad UI invalidation.
    //
    // The fields mirror the previous unconditional `DO UPDATE SET`
    // clause. `IS` gives SQLite's null-safe equality semantics, so a
    // NULL-to-NULL field does not count as changed.
    //
    // gate the UPDATE on
    // `?20 >= last_seen_at` so two concurrent provider refreshes
    // that both miss the INSERT can't clobber each other in
    // arrival order. The first writer's `now` lands; a slower
    // racing writer carrying an OLDER `now` (clock skew across
    // adapter callers, or a queued refresh that lost the BEGIN
    // IMMEDIATE race) is monotonicity-rejected. The `>=` (rather
    // than strict `>`) lets the same `now` arrive idempotently —
    // a single adapter retrying the same row inside one tick
    // still refreshes instead of silently skipping.
    if conn
        .prepare_cached(
            "UPDATE provider_calendar_events SET \
             title = ?4, description = ?5, \
             start_date = ?6, start_time = ?7, \
             end_date = ?8, end_time = ?9, \
             all_day = ?10, location = ?11, \
             organizer_email = ?12, \
             source_time_kind = ?13, source_tzid = ?14, \
             recurrence = ?15, recurrence_exceptions = ?16, \
             color = ?17, attendees_json = ?18, \
             video_call_url = ?19, \
             last_seen_at = ?20, last_refreshed_at = ?20 \
         WHERE provider_kind = ?1 AND provider_scope = ?2 AND provider_event_key = ?3 \
           AND ?20 >= last_seen_at \
           AND NOT ( \
             title IS ?4 AND description IS ?5 \
             AND start_date IS ?6 AND start_time IS ?7 \
             AND end_date IS ?8 AND end_time IS ?9 \
             AND all_day IS ?10 AND location IS ?11 \
             AND organizer_email IS ?12 \
             AND source_time_kind IS ?13 AND source_tzid IS ?14 \
             AND recurrence IS ?15 AND recurrence_exceptions IS ?16 \
             AND color IS ?17 AND attendees_json IS ?18 \
             AND video_call_url IS ?19 \
           )",
        )?
        .execute(params![
            event.provider_kind,
            event.provider_scope,
            event.provider_event_key,
            event.title,
            event.description,
            event.start_date,
            event.start_time,
            event.end_date,
            event.end_time,
            i64::from(event.all_day),
            event.location,
            event.organizer_email,
            event.source_time_kind,
            event.source_tzid,
            event.recurrence,
            event.recurrence_exceptions,
            event.color,
            event.attendees_json,
            event.video_call_url,
            now,
        ])?
        == 1
    {
        return Ok(ProviderEventUpsertOutcome::Updated);
    }

    // Existing row with identical visible content. Refresh provider
    // observation timestamps under the same monotonic guard, but do
    // not report a user-visible update.
    let bumped = conn
        .prepare_cached(
            "UPDATE provider_calendar_events SET \
                 last_seen_at = ?4, last_refreshed_at = ?4 \
             WHERE provider_kind = ?1 AND provider_scope = ?2 AND provider_event_key = ?3 \
               AND ?4 >= last_seen_at",
        )?
        .execute(params![
            event.provider_kind,
            event.provider_scope,
            event.provider_event_key,
            now,
        ])?;
    if bumped == 0 {
        // Monotonic gate rejected the bump — a racing refresh (clock
        // skew across adapter callers) already wrote a strictly-newer
        // `last_seen_at`.
        // by `Ok(Unchanged)`, so a downstream staleness sweep using
        // `last_seen_at` had no way to tell "I observed this row but
        // my clock was older than the racing writer's" apart from "I
        // observed this row and stamped my clock". The breadcrumb
        // surfaces the clock-skew so an operator can investigate
        // without changing the typed outcome (the four call sites
        // treat Unchanged identically: skip, no UI invalidation).
        crate::error::log::append_error_log_best_effort(
            conn,
            "store.provider_repo.upsert_event_stale_clock",
            &format!(
                "provider_calendar_events identical-content refresh rejected by monotonic \
                 gate: {kind}/{scope}/{key} now={now} (a racing refresh stamped a strictly-newer \
                 last_seen_at)",
                kind = event.provider_kind,
                scope = event.provider_scope,
                key = event.provider_event_key,
            ),
            None,
            Some("warn"),
        );
    }

    Ok(ProviderEventUpsertOutcome::Unchanged)
}

/// Get all cached event keys for a `(provider_kind, provider_scope)` pair,
/// optionally filtered by `start_date >= min_start_date`.
///
/// Used by adapters to compute stale-key sets for cleanup.
pub fn get_provider_event_keys(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: Option<&str>,
    min_start_date: Option<&str>,
) -> Result<Vec<String>, StoreError> {
    fn collect_keys(
        stmt: &mut rusqlite::Statement<'_>,
        p: &[&dyn rusqlite::types::ToSql],
    ) -> Result<Vec<String>, StoreError> {
        let rows = stmt.query_map(p, |row| row.get(0))?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    // Route every branch through `prepare_cached`.
    // `get_provider_event_keys` is called once per provider sync
    // cycle to compute the stale-key set for cleanup, so re-preparing
    // the statement each call would pay the SQL parse + plan cost on
    // every cycle. The four shape variants are stable, so each lands
    // in the same connection-scoped statement cache slot after first
    // use.
    match (provider_scope, min_start_date) {
        (Some(scope), Some(date)) => {
            let mut stmt = conn.prepare_cached(
                "SELECT provider_event_key FROM provider_calendar_events \
                 WHERE provider_kind = ?1 AND provider_scope = ?2 AND start_date >= ?3",
            )?;
            collect_keys(&mut stmt, &[&provider_kind, &scope, &date])
        }
        (Some(scope), None) => {
            let mut stmt = conn.prepare_cached(
                "SELECT provider_event_key FROM provider_calendar_events \
                 WHERE provider_kind = ?1 AND provider_scope = ?2",
            )?;
            collect_keys(&mut stmt, &[&provider_kind, &scope])
        }
        (None, Some(date)) => {
            let mut stmt = conn.prepare_cached(
                "SELECT provider_event_key FROM provider_calendar_events \
                 WHERE provider_kind = ?1 AND start_date >= ?2",
            )?;
            collect_keys(&mut stmt, &[&provider_kind, &date])
        }
        (None, None) => {
            let mut stmt = conn.prepare_cached(
                "SELECT provider_event_key FROM provider_calendar_events \
                 WHERE provider_kind = ?1",
            )?;
            collect_keys(&mut stmt, &[&provider_kind as &dyn rusqlite::types::ToSql])
        }
    }
}

/// Delete a single provider event by its composite key. Returns the
/// affected-row count (0 when no matching row existed; otherwise 1).
pub fn delete_provider_event(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<usize, StoreError> {
    Ok(conn
        .prepare_cached(
            "DELETE FROM provider_calendar_events \
             WHERE provider_kind = ?1 AND provider_scope = ?2 AND provider_event_key = ?3",
        )?
        .execute(params![provider_kind, provider_scope, provider_event_key])?)
}

/// Delete all cached events for a provider kind (e.g. when toggling off EventKit).
pub fn clear_provider_events_by_kind(
    conn: &Connection,
    provider_kind: &str,
) -> Result<usize, StoreError> {
    Ok(conn
        .prepare_cached("DELETE FROM provider_calendar_events WHERE provider_kind = ?1")?
        .execute(params![provider_kind])?)
}

/// Delete all cached events for a specific scope (e.g. removing a subscription).
pub fn clear_provider_events_by_scope(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
) -> Result<usize, StoreError> {
    Ok(conn
        .prepare_cached(
            "DELETE FROM provider_calendar_events \
             WHERE provider_kind = ?1 AND provider_scope = ?2",
        )?
        .execute(params![provider_kind, provider_scope])?)
}
