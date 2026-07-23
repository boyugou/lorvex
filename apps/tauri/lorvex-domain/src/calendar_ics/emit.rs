//! RFC 5545 ICS emission: VCALENDAR / VEVENT assembly, timestamp formatting,
//! TEXT-property escaping + truncation, and 75-octet line folding.
//!
//! [`export_calendar_ics`] is the byte-stable public entry. Internal helpers
//! ([`local_to_utc_ics_timestamp`], [`format_ics_timestamp`],
//! [`escape_ics_text`], [`fold_line`], [`is_date_value_event`]) are exposed
//! to sibling modules ([`super::recurrence`]) at `pub(super)` visibility so
//! EXDATE emission shares the same UTC-conversion + escaping rules as
//! DTSTART.

use chrono::{Duration, NaiveDateTime};
use chrono_tz::Tz;

use super::model::{CalendarIcsError, CalendarIcsEvent, CalendarIcsWarning};
use super::recurrence::{recurrence_exdates, recurrence_to_rrule};
use super::validation::{date_to_ics, next_date};
use crate::time::{Date, TimeOfDay};

pub fn export_calendar_ics(events: &[CalendarIcsEvent<'_>]) -> Result<String, CalendarIcsError> {
    export_calendar_ics_with_warnings(events).map(|(ics, _)| ics)
}

/// Variant of [`export_calendar_ics`] that also surfaces non-fatal
/// observations: recurrence rules whose expansion silently skips
/// months ([`CalendarIcsWarning::Recurrence`]), and naive timestamps
/// that the legacy fallback parsers labeled as UTC
/// ([`CalendarIcsWarning::LegacyNaiveTimestamp`]).
pub fn export_calendar_ics_with_warnings(
    events: &[CalendarIcsEvent<'_>],
) -> Result<(String, Vec<CalendarIcsWarning>), CalendarIcsError> {
    // The PRODID identifier reflects the shipping crate version so a
    // downstream client (or a support request reading an exported
    // `.ics` blob) can pinpoint which build of Lorvex emitted the
    // file. A bare `//Lorvex//Calendar//EN` would leave a bug-report
    // with an attached `.ics` no way to identify the build short of
    // asking the user to dig through Settings → About. Use
    // `CARGO_PKG_VERSION` of the domain crate (which always tracks
    // the workspace version per the build invariants). The trailing
    // language tag (`//EN`) per RFC 5545 §3.7.3 anchors the formal
    // grammar.
    let mut lines: Vec<String> = vec![
        "BEGIN:VCALENDAR".to_string(),
        "VERSION:2.0".to_string(),
        format!(
            "PRODID:-//Lorvex//Calendar {}//EN",
            env!("CARGO_PKG_VERSION")
        ),
        "CALSCALE:GREGORIAN".to_string(),
        "METHOD:PUBLISH".to_string(),
    ];

    let mut warnings: Vec<CalendarIcsWarning> = Vec::new();
    for event in events {
        append_vevent(&mut lines, event, &mut warnings)?;
    }

    lines.push("END:VCALENDAR".to_string());

    // Stream the folded lines directly into the output buffer instead
    // of materializing a `Vec<String>` of folded lines and joining
    // afterward. Saves N intermediate allocations + the Vec backing
    // store on every export.
    let mut ics =
        String::with_capacity(lines.iter().map(String::len).sum::<usize>() + lines.len() * 2);
    for (i, line) in lines.iter().enumerate() {
        if i > 0 {
            ics.push_str("\r\n");
        }
        append_folded_line(&mut ics, line);
    }
    Ok((ics, warnings))
}

fn append_vevent(
    lines: &mut Vec<String>,
    event: &CalendarIcsEvent<'_>,
    warnings: &mut Vec<CalendarIcsWarning>,
) -> Result<(), CalendarIcsError> {
    let start_date_ics = date_to_ics(event.start_date());
    let created_stamp = format_ics_timestamp("created_at", event.created_at, warnings)?;
    let updated_stamp = format_ics_timestamp("updated_at", event.updated_at, warnings)?;

    lines.push("BEGIN:VEVENT".to_string());
    lines.push(format!("UID:{}@lorvex", event.id));
    lines.push(format!("DTSTAMP:{updated_stamp}"));
    lines.push(format!("CREATED:{created_stamp}"));
    // emit SEQUENCE so downstream calendar clients
    // can distinguish an edit-republish from the original publication.
    // RFC 5545 §3.8.7.4: must be non-decreasing per (UID, RECURRENCE-
    // ID); the store-side derivation (seconds between created_at and
    // updated_at) preserves this for sequential edits to the same row.
    lines.push(format!("SEQUENCE:{}", event.sequence));

    // Single source of truth for "is DTSTART a date or a date-time?"
    // — `append_vevent` and `recurrence_exdates` must agree, even
    // for the awkward `start_time = None, all_day = false`
    // combination. RFC 5545 §3.8.5.1 forbids an EXDATE shape
    // mismatch with DTSTART, so a divergence would produce
    // `DTSTART;VALUE=DATE` paired with timed `EXDATE` lines and
    // Apple Calendar / Google would silently drop the EXDATEs.
    let is_date_value = is_date_value_event(event);

    if is_date_value {
        lines.push(format!("DTSTART;VALUE=DATE:{start_date_ics}"));
        let end_date = event.end_date().unwrap_or_else(|| event.start_date());
        let next_day = next_date("end_date", end_date)?;
        lines.push(format!("DTEND;VALUE=DATE:{}", date_to_ics(next_day)));
    } else {
        // Timed branch is reachable iff `is_date_value_event` is
        // false, which means `all_day == false` AND `start_time`
        // is present. The fallback below routes a contract breach
        // (a future refactor that breaks the
        // `is_date_value_event` <-> `start_time.is_some()`
        // pairing) through the typed-error path instead of
        // panicking inside the export pipeline.
        let start_time = event.start_time().ok_or(
            CalendarIcsError::InternalContractViolation {
                field: "start_time",
                detail: "is_date_value_event=false requires start_time to be Some on the timed VEVENT branch",
            },
        )?;
        // Convert the local (start_date, start_time) pair to UTC using
        // the event's stored timezone when available. External calendar
        // apps that ingest the ICS render UTC `Z` values correctly in
        // the user's local timezone. Rows without a stored timezone
        // (e.g. ICS imports that did not declare one) fall back to
        // treating the clock-time as already-UTC.
        let start_utc =
            local_to_utc_ics_timestamp(event.start_date(), start_time, event.timezone, "start");
        lines.push(format!("DTSTART:{start_utc}"));

        if let Some(end_time) = event.end_time() {
            let end_date = event.end_date().unwrap_or_else(|| event.start_date());
            let end_utc = local_to_utc_ics_timestamp(end_date, end_time, event.timezone, "end");
            lines.push(format!("DTEND:{end_utc}"));
        } else {
            lines.push(format!(
                "DTEND:{}",
                add_one_hour_ics(event.start_date(), start_time, event.timezone)
            ));
        }
    }

    lines.push(format!(
        "SUMMARY:{}",
        escape_and_cap_ics_text("SUMMARY", event.title, warnings)
    ));

    if let Some(description) = event.description.filter(|value| !value.is_empty()) {
        lines.push(format!(
            "DESCRIPTION:{}",
            escape_and_cap_ics_text("DESCRIPTION", description, warnings)
        ));
    }

    if let Some(location) = event.location.filter(|value| !value.is_empty()) {
        lines.push(format!(
            "LOCATION:{}",
            escape_and_cap_ics_text("LOCATION", location, warnings)
        ));
    }

    if let Some(rrule) = recurrence_to_rrule(event.recurrence, warnings)? {
        lines.push(rrule);
    }

    for exdate in recurrence_exdates(event)? {
        lines.push(exdate);
    }

    lines.push("END:VEVENT".to_string());
    Ok(())
}

fn add_one_hour_ics(date: Date, time: TimeOfDay, timezone: Option<&str>) -> String {
    let local = NaiveDateTime::new(date.as_naive_date(), time.as_naive_time()) + Duration::hours(1);
    local_naive_to_utc_ics_string(&local, timezone)
}

/// Convert a stored (local date, local time, timezone) tuple to a UTC
/// ICS timestamp string (YYYYMMDDTHHMMSSZ). When `timezone` is `None`
/// or unparseable, the local time is treated as already-UTC.
///
/// `date` and `time` are typed [`Date`] / [`TimeOfDay`] so the
/// `YYYY-MM-DD` / `HH:MM` validity invariant is enforced at the
/// boundary of the export pipeline rather than re-parsed at every
/// call site. The previous `&str` shape made the InvalidDate /
/// InvalidTime error variants reachable from this function; that is
/// no longer possible because every caller routes the value through
/// the typed wrapper at construction.
pub(super) fn local_to_utc_ics_timestamp(
    date: Date,
    time: TimeOfDay,
    timezone: Option<&str>,
    _field_prefix: &'static str,
) -> String {
    let local = NaiveDateTime::new(date.as_naive_date(), time.as_naive_time());
    local_naive_to_utc_ics_string(&local, timezone)
}

/// Render a local `NaiveDateTime` as a `YYYYMMDDTHHMMSSZ` string,
/// converting through the IANA `timezone` when present and parseable.
/// Missing / unparseable timezone falls back to treating the clock-
/// time as already-UTC, matching the contract `local_to_utc_ics_timestamp`
/// and `add_one_hour_ics` inlined verbatim.
fn local_naive_to_utc_ics_string(local: &NaiveDateTime, timezone: Option<&str>) -> String {
    if let Some(tz_name) = timezone.filter(|name| !name.is_empty()) {
        if let Ok(tz) = tz_name.parse::<Tz>() {
            let utc = resolve_local_to_utc_ics(local, tz);
            return format!("{}Z", utc.format("%Y%m%dT%H%M%S"));
        }
    }
    format!("{}Z", local.format("%Y%m%dT%H%M%S"))
}

/// resolve a local NaiveDateTime against an
/// IANA zone and return a UTC DateTime for ICS emission. Routes through
/// the canonical [`crate::dst::resolve_local_datetime`] helper so every
/// call site shares the same spring-forward / fall-back policy:
///
/// - Unambiguous wall clock → convert directly.
/// - Fall-back ambiguity → use the earlier occurrence (matches the
///   existing convention in `lorvex-store::calendar_timeline::temporal`
///   and the Tauri-side calendar event validator).
/// - Spring-forward gap → use the snapped post-gap instant the domain
///   helper provides.
///
/// Treating the `None` arm as UTC (`{}Z` format) would silently
/// re-label the wall-clock — e.g. a 2:30 AM PST event on DST day
/// would produce `20260309T023000Z`, which reads back in PST as
/// the previous evening at 18:30, off by 8+ hours and a day.
fn resolve_local_to_utc_ics(local: &NaiveDateTime, tz: Tz) -> chrono::DateTime<chrono::Utc> {
    match crate::dst::resolve_local_datetime(tz, *local) {
        crate::dst::DstResolution::Valid(dt) => dt.with_timezone(&chrono::Utc),
        crate::dst::DstResolution::Ambiguous { earlier, .. } => earlier.with_timezone(&chrono::Utc),
        crate::dst::DstResolution::Skipped { snapped_to, .. } => {
            snapped_to.with_timezone(&chrono::Utc)
        }
    }
}

pub(super) fn format_ics_timestamp(
    field: &'static str,
    raw: &str,
    warnings: &mut Vec<CalendarIcsWarning>,
) -> Result<String, CalendarIcsError> {
    // The two legacy fallback shapes (`%Y-%m-%dT%H:%M:%S%.f` and
    // `%Y-%m-%d %H:%M:%S%.f`) are naive wall-clock strings with no
    // timezone marker. They still parse (so old data continues to
    // flow) but they emit a `LegacyNaiveTimestamp` warning so the
    // diagnostic / sync log surfaces the drift — silently labeling
    // them as UTC would shift the timestamp by the sender's local
    // UTC offset on every round trip when a peer device reads the
    // exported `.ics`.
    if let Ok(ts) = chrono::DateTime::parse_from_rfc3339(raw) {
        return Ok(ts
            .with_timezone(&chrono::Utc)
            .format("%Y%m%dT%H%M%SZ")
            .to_string());
    }
    // both legacy fallback parsers accept any year
    // chrono can represent (down to year 0). RFC 5545 §3.3.5 requires
    // 4-digit Gregorian years, and many calendar clients silently
    // drop VEVENTs whose CREATED/DTSTAMP carries a pre-1900 year. A
    // peer-authored row (`created_at = "0099-01-01T00:00:00"`) used
    // to round-trip into `00990101T000000Z` and disappear into the
    // void downstream. 1900 is the conservative cutoff: the
    // Gregorian calendar took until then to be adopted globally and
    // every modern calendar client we test against parses 1900-and-
    // up correctly.
    if let Ok(ts) = NaiveDateTime::parse_from_str(raw, "%Y-%m-%dT%H:%M:%S%.f") {
        let year = chrono::Datelike::year(&ts);
        if year < 1900 {
            return Err(CalendarIcsError::PreGregorianTimestampYear { field, year });
        }
        warnings.push(CalendarIcsWarning::LegacyNaiveTimestamp {
            field,
            value: raw.to_string(),
        });
        return Ok(format!("{}Z", ts.format("%Y%m%dT%H%M%S")));
    }
    if let Ok(ts) = NaiveDateTime::parse_from_str(raw, "%Y-%m-%d %H:%M:%S%.f") {
        let year = chrono::Datelike::year(&ts);
        if year < 1900 {
            return Err(CalendarIcsError::PreGregorianTimestampYear { field, year });
        }
        warnings.push(CalendarIcsWarning::LegacyNaiveTimestamp {
            field,
            value: raw.to_string(),
        });
        return Ok(format!("{}Z", ts.format("%Y%m%dT%H%M%S")));
    }
    Err(CalendarIcsError::InvalidTimestamp {
        field,
        value: raw.to_string(),
    })
}

/// single source of truth for "is the VEVENT a
/// date-only value (`DTSTART;VALUE=DATE`) or a timed datetime
/// (`DTSTART:`)?". `append_vevent` and `recurrence_exdates` both
/// route through here so a non-`all_day` event with `start_time =
/// None` can never produce a date-only DTSTART paired with timed
/// EXDATEs (RFC 5545 §3.8.5.1 forbids that shape mismatch; external
/// clients silently drop EXDATEs that disagree with DTSTART).
pub(super) const fn is_date_value_event(event: &CalendarIcsEvent<'_>) -> bool {
    event.all_day() || event.start_time().is_none()
}

/// Escape an ICS TEXT value (per RFC 5545 § 3.3.11) AND strip the
/// bidi/zero-width/line-separator codepoints the rest of Lorvex
/// scrubs at write boundaries.
///
/// the previous shape escaped `\\`, `;`, `,`, `\n` and
/// dropped `\r`, but did NOT strip the bidi/zero-width codepoints
/// that `unicode_hygiene::sanitize_user_text` strips elsewhere.
/// Untrusted text passing through `export_calendar_ics` could
/// embed bidi overrides into `SUMMARY:` / `DESCRIPTION:` fields,
/// surviving into shared `.ics` files consumed by Apple Calendar /
/// Google. The redaction story Lorvex applies elsewhere bypassed
/// this surface; the sanitizer call here closes that gap.
/// cap on the post-cap codepoint length of a single
/// VEVENT text property (SUMMARY, DESCRIPTION, LOCATION). Matches the
/// canonical `MAX_TITLE_LENGTH = 1000` so a row that bypassed the
/// write-time validator (sync import, legacy schema, raw repository
/// write) cannot ship an unbounded line through the export boundary.
/// RFC 5545 leaves the property length unspecified but real-world
/// clients (Apple Calendar, Outlook) silently truncate or reject
/// over-long values, so the explicit cap + warning is both defensive
/// and observable.
pub(super) const MAX_VEVENT_TEXT_LENGTH: usize = crate::validation::MAX_TITLE_LENGTH;

/// Truncate `text` to [`MAX_VEVENT_TEXT_LENGTH`] codepoints, append a
/// truncation marker, and emit a [`CalendarIcsWarning::TextTruncated`]
/// when the input exceeds the cap. Returns the escaped, capped value.
/// The truncation marker (`…`) is one codepoint, so the final escaped
/// value still respects the cap.
fn escape_and_cap_ics_text(
    field: &'static str,
    text: &str,
    warnings: &mut Vec<CalendarIcsWarning>,
) -> String {
    let original_chars = text.chars().count();
    if original_chars > MAX_VEVENT_TEXT_LENGTH {
        // Reserve one codepoint for the ellipsis truncation marker so
        // the final string is at most MAX_VEVENT_TEXT_LENGTH chars.
        let head: String = text.chars().take(MAX_VEVENT_TEXT_LENGTH - 1).collect();
        let truncated = format!("{head}\u{2026}");
        warnings.push(CalendarIcsWarning::TextTruncated {
            field,
            original_chars,
            truncated_to: MAX_VEVENT_TEXT_LENGTH,
        });
        return escape_ics_text(&truncated);
    }
    escape_ics_text(text)
}

fn escape_ics_text(text: &str) -> String {
    // Single-pass escape: the previous shape called `String::replace`
    // five times in sequence, each allocating a fresh `String` for the
    // entire scrubbed text. Walking the input once and writing into
    // one pre-sized buffer collapses to a single allocation.
    let scrubbed = crate::sanitize_user_text(text);
    let mut out = String::with_capacity(scrubbed.len());
    for ch in scrubbed.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            ';' => out.push_str("\\;"),
            ',' => out.push_str("\\,"),
            '\n' => out.push_str("\\n"),
            '\r' => {}
            _ => out.push(ch),
        }
    }
    out
}

#[cfg(test)]
pub(super) fn fold_line(line: &str) -> String {
    let mut out = String::with_capacity(line.len() + (line.len() / 74) * 3);
    append_folded_line(&mut out, line);
    out
}

/// Streaming variant of [`fold_line`] that writes the folded output
/// into an existing `String`. The exporter routes the every-line loop
/// through this function so no intermediate per-line `String` is
/// materialized — `fold_line` itself is preserved for tests that
/// exercise the folder in isolation.
pub(super) fn append_folded_line(out: &mut String, line: &str) {
    if line.len() <= 75 {
        out.push_str(line);
        return;
    }
    let mut pos = 0;
    let mut first = true;
    while pos < line.len() {
        let max_chunk = if first { 75 } else { 74 };
        let mut end = (pos + max_chunk).min(line.len());
        while end > pos && !line.is_char_boundary(end) {
            end -= 1;
        }
        if end == pos {
            end = pos + line[pos..].chars().next().map_or(1, char::len_utf8);
        }
        if !first {
            out.push_str("\r\n ");
        }
        out.push_str(&line[pos..end]);
        pos = end;
        first = false;
    }
}
