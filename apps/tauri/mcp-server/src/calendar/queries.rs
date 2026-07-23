use crate::contract::{
    GetCalendarEventArgs, GetCalendarEventsArgs, SearchCalendarEventsArgs,
    CALENDAR_EVENTS_LIMIT_CAP, CALENDAR_EVENTS_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{
    bounded_limit, next_offset_for_page, read_calendar_ai_access_mode,
};
use lorvex_store::calendar_timeline::types::TimelineSource;
use lorvex_workflow::timezone::anchored_timezone_name;
use rusqlite::Connection;
use serde_json::json;

use super::mutations::{
    enrich_event_with_attendees, enrich_events_with_attendees, load_calendar_event_json,
};

pub(crate) fn get_calendar_event(
    conn: &Connection,
    args: GetCalendarEventArgs,
) -> Result<String, McpError> {
    let GetCalendarEventArgs { id } = args;
    let event = load_calendar_event_json(conn, &id)?;
    match event {
        Some(mut event) => {
            // #2422: fence user-origin calendar event string fields.
            crate::system::text_hygiene::fence_calendar_event_user_fields(&mut event);
            Ok(serde_json::to_string(&event)?)
        }
        None => Ok("null".to_string()),
    }
}

pub(crate) fn get_calendar_events(
    conn: &Connection,
    args: GetCalendarEventsArgs,
) -> Result<String, McpError> {
    let GetCalendarEventsArgs {
        from,
        to,
        limit,
        offset,
        include_provider,
    } = args;

    if lorvex_domain::time::parse_iso_date(&from).is_err() {
        return Err(McpError::Validation(format!(
            "invalid from date '{from}', expected YYYY-MM-DD"
        )));
    }
    if lorvex_domain::time::parse_iso_date(&to).is_err() {
        return Err(McpError::Validation(format!(
            "invalid to date '{to}', expected YYYY-MM-DD"
        )));
    }
    if to < from {
        return Err(McpError::Validation(format!(
            "to ({to}) cannot be before from ({from})"
        )));
    }

    let limit = bounded_limit(
        limit,
        CALENDAR_EVENTS_LIMIT_DEFAULT,
        CALENDAR_EVENTS_LIMIT_CAP,
    );

    if include_provider {
        let access_mode = read_calendar_ai_access_mode(conn)?;
        let anchor_timezone = anchored_timezone_name(conn)?;
        let mut items = lorvex_store::calendar_timeline::get_calendar_timeline(
            conn,
            &from,
            &to,
            access_mode,
            &anchor_timezone,
        )?;

        // apply offset by slicing the merged timeline
        // before the limit truncation so callers can walk past the
        // first page. The timeline merge has no native pagination
        // affordance because provider events come from EventKit /
        // .ics subscriptions; the slice is the cheapest correct fix.
        let offset_usize = offset as usize;
        if items.len() > offset_usize {
            items.drain(0..offset_usize);
        } else {
            items.clear();
        }
        let limit_usize = usize::try_from(limit).unwrap_or(0);
        let truncated = items.len() > limit_usize;
        items.truncate(limit_usize);

        let mut events: Vec<serde_json::Value> = Vec::with_capacity(items.len());
        for item in &items {
            let source_str = match item.source() {
                TimelineSource::Canonical => "canonical",
                TimelineSource::Provider => "provider",
            };
            let mut obj = json!({
                "source": source_str,
                "editable": item.editable(),
                "id": item.id(),
                "title": item.title(),
                "start_date": item.start_date(),
                "start_time": item.start_time(),
                "end_date": item.end_date(),
                "end_time": item.end_time(),
                "all_day": item.all_day(),
                "location": item.location(),
                "color": item.color(),
                "event_type": item.event_type(),
                "person_name": item.person_name(),
                "timezone": item.timezone(),
                "provider_kind": item.provider_kind(),
                "source_time_kind": item.source_time_kind(),
                "source_tzid": item.source_tzid(),
            });

            if *item.source() == TimelineSource::Canonical {
                enrich_event_with_attendees(conn, &mut obj)?;
            }

            events.push(obj);
        }

        // #2422: fence user-origin string fields on every event,
        // regardless of source (canonical or provider).
        crate::system::text_hygiene::fence_calendar_events_user_fields(&mut events);

        let returned = events.len() as i64;
        let consumed = i64::from(offset).saturating_add(returned);
        let next_offset = next_offset_for_page(truncated, consumed, returned);
        let payload = json!({
            "from": from,
            "to": to,
            "limit": limit,
            "offset": offset,
            "count": events.len(),
            "events": events,
            "truncated": truncated,
            "next_offset": next_offset,
        });
        Ok(serde_json::to_string(&payload)?)
    } else {
        let rows = lorvex_store::calendar_timeline::queries::list_calendar_events(
            conn, &from, &to, limit, offset,
        )?;
        let mut events = rows
            .into_iter()
            .map(serde_json::to_value)
            .collect::<Result<Vec<_>, _>>()?;
        enrich_events_with_attendees(conn, &mut events)?;
        // #2422: fence user-origin event strings on the canonical path.
        crate::system::text_hygiene::fence_calendar_events_user_fields(&mut events);

        // Whether further pages exist is an "is len(events) == limit?"
        // signal — when the current slice fills the page exactly,
        // there's at least one more row beyond it. Cheaper than a
        // separate COUNT round-trip.
        let returned = events.len() as i64;
        let truncated = returned >= i64::from(limit);
        let consumed = i64::from(offset).saturating_add(returned);
        let next_offset = next_offset_for_page(truncated, consumed, returned);
        let payload = json!({
            "from": from,
            "to": to,
            "limit": limit,
            "offset": offset,
            "count": events.len(),
            "events": events,
            "truncated": truncated,
            "next_offset": next_offset,
        });
        Ok(serde_json::to_string(&payload)?)
    }
}

pub(crate) fn search_calendar_events(
    conn: &Connection,
    args: SearchCalendarEventsArgs,
) -> Result<String, McpError> {
    let query = args.query.trim();
    if query.is_empty() {
        return Err(McpError::Validation("query must be non-empty".to_string()));
    }

    if let Some(ref from) = args.from {
        if lorvex_domain::time::parse_iso_date(from).is_err() {
            return Err(McpError::Validation(format!(
                "invalid from date '{from}', expected YYYY-MM-DD"
            )));
        }
    }
    if let Some(ref to) = args.to {
        if lorvex_domain::time::parse_iso_date(to).is_err() {
            return Err(McpError::Validation(format!(
                "invalid to date '{to}', expected YYYY-MM-DD"
            )));
        }
    }

    let limit = bounded_limit(
        args.limit,
        CALENDAR_EVENTS_LIMIT_DEFAULT,
        CALENDAR_EVENTS_LIMIT_CAP,
    );
    let offset = args.offset;

    let pred = lorvex_domain::query::CalendarSearchPredicate {
        query: query.to_string(),
        from: args.from,
        to: args.to,
    };

    // widen-then-slice pagination over the FTS result
    // set. Same pattern as the reminder paths — the store has no
    // native offset, so the MCP wrapper fetches `limit + offset`
    // rows then drops the leading slice locally. The FTS cap stays
    // bounded at `MCP_RESULT_LIMIT_CAP` via `bounded_limit` above
    // (search defaults match calendar caps).
    let widened_limit = limit.saturating_add(offset);
    let rows = lorvex_store::calendar_timeline::search_calendar_events(conn, &pred, widened_limit)?;

    let mut events: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|row| Ok(serde_json::to_value(&row)?))
        .collect::<Result<_, McpError>>()?;
    let offset_usize = offset as usize;
    if events.len() > offset_usize {
        events.drain(0..offset_usize);
    } else {
        events.clear();
    }
    enrich_events_with_attendees(conn, &mut events)?;
    // #2422: fence user-origin event strings.
    crate::system::text_hygiene::fence_calendar_events_user_fields(&mut events);

    let returned = events.len() as i64;
    let truncated = returned >= i64::from(limit);
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(truncated, consumed, returned);
    let payload = json!({
        "limit": limit,
        "offset": offset,
        "count": events.len(),
        "events": events,
        "truncated": truncated,
        "next_offset": next_offset,
    });
    Ok(serde_json::to_string(&payload)?)
}
