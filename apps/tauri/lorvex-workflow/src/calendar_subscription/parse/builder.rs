use lorvex_domain::validation::{MAX_BODY_LENGTH, MAX_TITLE_LENGTH};

use super::super::tzid::{parse_ics_datetime_with_registry, IcsDateTime, UnknownTzidSink};
use super::super::vtimezone::VTimezoneRegistry;
use super::super::CalendarSubscriptionError;
use super::datetime::{normalize_ics_datetime_to_date, normalize_recurrence_id};
use super::model::{ParsedEvent, MAX_EXDATES_PER_EVENT};
use super::properties::{
    attach_is_inline_binary, extract_ics_param, split_ics_line, strip_mailto_scheme, unescape_ics,
};
use super::{MAX_ATTENDEES_PER_EVENT, MAX_ICS_SHORT_FIELD_LENGTH};

#[derive(Default)]
pub(super) struct EventBuilder {
    uid: Option<String>,
    summary: Option<String>,
    description: Option<String>,
    /// Stored as the full ICS property key (including params like `DTSTART;TZID=...`)
    /// so we can extract TZID in build().
    dtstart_key: Option<String>,
    dtstart_value: Option<String>,
    dtend_key: Option<String>,
    dtend_value: Option<String>,
    location: Option<String>,
    organizer: Option<String>,
    /// RECURRENCE-ID with TZID round-trip.
    /// We store the full key (including any `;TZID=` parameter) plus
    /// the raw value separately so `build()` can resolve the wall-clock
    /// time through the same VTIMEZONE registry as DTSTART. Without
    /// this, two feeds describing the same overridden occurrence — one
    /// using `RECURRENCE-ID;TZID=America/New_York:20260408T090000` and
    /// the other using `RECURRENCE-ID:20260408T130000Z` — would land
    /// under different composite keys and the override would silently
    /// duplicate the master.
    recurrence_id_key: Option<String>,
    recurrence_id_value: Option<String>,
    rrule: Option<String>,
    /// Accumulated EXDATE entries: each entry is `(full_key, raw_value)`
    /// so we can resolve TZID per-line. RFC 5545 §3.8.5.1 lets EXDATE
    /// be tagged with `;TZID=…` (e.g. `EXDATE;TZID=America/New_York:20260408T090000`).
    /// value verbatim, which placed the exception on the wrong UTC date
    /// for any feed where the local zone was offset across midnight.
    exdates_raw: Vec<(String, String)>,
    /// Accumulated ATTENDEE entries: `(email, name, rsvp_status)`.
    attendees: Vec<(String, Option<String>, Option<String>)>,
    /// URL property value.
    url: Option<String>,
    /// URI-form ATTACH used as a URL fallback when
    /// the VEVENT has no explicit URL line. Binary inline ATTACH (i.e.
    /// `ATTACH;VALUE=BINARY;ENCODING=BASE64:…`) is captured here as
    /// `None` — we recognize and skip the property without copying the
    /// payload into memory beyond the fold step, so a feed using inline
    /// binary attachments (a common pattern for embedded meeting
    /// invites) cannot inflate the parsed event past the title cap.
    attach_url: Option<String>,
    /// VEVENT SEQUENCE — see `ParsedEvent::sequence`.
    sequence: Option<i64>,
    /// VEVENT DTSTAMP — see `ParsedEvent::dtstamp`.
    dtstamp: Option<String>,
    /// VEVENT `STATUS` property — `CONFIRMED`,
    /// `TENTATIVE`, or `CANCELLED`. A peer / organizer can flip a
    /// single occurrence to CANCELLED via a detached override
    /// (`RECURRENCE-ID` + `STATUS:CANCELLED`) without sending a
    /// calendar-level `METHOD:CANCEL`. The audit noted that surface
    /// silently kept the override visible. Captured at parse time and
    /// translated into a "drop this event" signal in `build()`.
    status: Option<String>,
}

impl EventBuilder {
    pub(super) fn parse_line(&mut self, line: &str) {
        if let Some((key, value)) = split_ics_line(line) {
            match key.split(';').next().unwrap_or("") {
                "UID" => self.uid = Some(value.to_string()),
                "SUMMARY" => self.summary = Some(unescape_ics(value)),
                "DESCRIPTION" => self.description = Some(unescape_ics(value)),
                "DTSTART" => {
                    self.dtstart_key = Some(key.to_string());
                    self.dtstart_value = Some(value.to_string());
                }
                "DTEND" => {
                    self.dtend_key = Some(key.to_string());
                    self.dtend_value = Some(value.to_string());
                }
                "RECURRENCE-ID" => {
                    self.recurrence_id_key = Some(key.to_string());
                    self.recurrence_id_value = Some(value.to_string());
                }
                "RRULE" => self.rrule = Some(value.to_string()),
                "SEQUENCE" => {
                    // SEQUENCE is the primary
                    // tie-breaker for duplicate VEVENT entries with the
                    // same UID (or UID+RECURRENCE-ID). RFC 5545 §3.8.7.4
                    // defines it as a non-negative integer; treat any
                    // unparseable value as "unknown" (i.e. leave the
                    // builder field None) so the dedup pass falls
                    // through to the DTSTAMP / position fallback.
                    if let Ok(n) = value.trim().parse::<i64>() {
                        if n >= 0 {
                            self.sequence = Some(n);
                        }
                    }
                }
                "DTSTAMP" => {
                    let trimmed = value.trim();
                    if !trimmed.is_empty() {
                        self.dtstamp = Some(trimmed.to_string());
                    }
                }
                "LOCATION" => self.location = Some(unescape_ics(value)),
                "ORGANIZER" => {
                    // ORGANIZER;CN=Name:mailto:email@example.com
                    //
                    // RFC 5545 §3.3.3 declares
                    // `MAILTO` (uppercase) as the canonical scheme name
                    // and many enterprise calendar servers (Exchange,
                    // Lotus) round-trip it that way. The previous
                    // strict `mailto:` lowercase prefix-match was
                    // dropping the scheme into the stored value, which
                    // surfaced as `MAILTO:user@example.com` in the
                    // organizer column instead of the bare email
                    // string the rest of the app expects. Match
                    // case-insensitively and trim whitespace so a
                    // `ORGANIZER: mailto:user@example.com` payload
                    // round-trips cleanly.
                    //
                    // route through `strip_dangerous_codepoints` so a
                    // hostile feed can't smuggle C0/C1 control bytes,
                    // ANSI CSI sequences, or bidi/zero-width overrides
                    // through the organizer column. Matches the
                    // discipline already applied to SUMMARY/
                    // DESCRIPTION/LOCATION via `unescape_ics`.
                    let cleaned = lorvex_domain::text_sanitize::strip_dangerous_codepoints(
                        &strip_mailto_scheme(value),
                    );
                    self.organizer = Some(cleaned);
                }
                "EXDATE" => {
                    // capture the full key (with
                    // any `;TZID=…`) and let `build()` resolve each
                    // wall-clock value through the per-feed VTIMEZONE
                    // registry. The previous implementation byte-sliced
                    // `value[..8]` directly, which silently dropped the
                    // local-zone offset and placed the exception on the
                    // wrong UTC date whenever the local time crossed
                    // midnight in UTC.
                    //
                    // Each EXDATE line can carry comma-separated values,
                    // and each value may be DATE (YYYYMMDD), DATE-TIME
                    // (YYYYMMDDTHHMMSS[Z]), or DATE-TIME with TZID per
                    // the parameter on the key.
                    if self.exdates_raw.len() < MAX_EXDATES_PER_EVENT {
                        for raw in value.split(',') {
                            let raw = raw.trim();
                            if raw.is_empty() {
                                continue;
                            }
                            self.exdates_raw.push((key.to_string(), raw.to_string()));
                            if self.exdates_raw.len() >= MAX_EXDATES_PER_EVENT {
                                break;
                            }
                        }
                    }
                }
                "ATTACH" => {
                    // RFC 5545 §3.8.1.1 allows
                    // two ATTACH forms — an external URI or an inline
                    // base64 binary blob (`VALUE=BINARY;ENCODING=BASE64`).
                    // The inline form can carry megabytes; we recognize
                    // and discard it without copying the payload past
                    // the unfolded line buffer (the `_ => {}` catch-all
                    // still saw the value but never stored it, so
                    // memory growth was bounded; this branch makes the
                    // intent explicit and surfaces URI ATTACH as a URL
                    // fallback when the VEVENT lacks an explicit URL).
                    if attach_is_inline_binary(key) {
                        // intentional drop
                    } else if self.attach_url.is_none() {
                        let trimmed = value.trim();
                        if !trimmed.is_empty() {
                            self.attach_url = Some(trimmed.to_string());
                        }
                    }
                }
                "ATTENDEE" => {
                    // ATTENDEE;CN=John Doe;PARTSTAT=ACCEPTED:mailto:john@example.com
                    // Extract email from the value (after the colon), CN and PARTSTAT from params.
                    //
                    // same case-insensitive
                    // `mailto:` handling as ORGANIZER above.
                    //
                    // Route the email, the `CN` display name, and the
                    // `PARTSTAT` reply state through
                    // `strip_dangerous_codepoints` before storage so a
                    // hostile feed cannot smuggle control bytes, ANSI
                    // CSI sequences, or bidi/zero-width overrides into
                    // the attendees JSON column. Matches the discipline
                    // already applied to SUMMARY/DESCRIPTION/LOCATION
                    // via `unescape_ics`.
                    let email = lorvex_domain::text_sanitize::strip_dangerous_codepoints(
                        &strip_mailto_scheme(value),
                    );
                    let cn = extract_ics_param(key, "CN")
                        .map(|s| lorvex_domain::text_sanitize::strip_dangerous_codepoints(&s));
                    let partstat = extract_ics_param(key, "PARTSTAT")
                        .map(|s| lorvex_domain::text_sanitize::strip_dangerous_codepoints(&s));
                    if !email.is_empty() {
                        self.attendees.push((email, cn, partstat));
                    }
                }
                "STATUS" => {
                    // VEVENT-level STATUS — see
                    // the `status` field comment on `EventBuilder`.
                    let trimmed = value.trim();
                    if !trimmed.is_empty() {
                        self.status = Some(trimmed.to_ascii_uppercase());
                    }
                }
                "URL" => {
                    let trimmed = value.trim();
                    if !trimmed.is_empty() {
                        self.url = Some(trimmed.to_string());
                    }
                }
                _ => {}
            }
        }
    }

    pub(super) fn build(
        self,
        registry: &VTimezoneRegistry,
        x_wr_timezone: Option<&str>,
        unknown_tzid_sink: UnknownTzidSink<'_>,
    ) -> Result<Option<ParsedEvent>, CalendarSubscriptionError> {
        let uid = self.uid.ok_or_else(|| {
            CalendarSubscriptionError::Validation("Malformed VEVENT: missing UID".to_string())
        })?;

        // VEVENT `STATUS:CANCELLED` means the
        // event (or this occurrence override) is no longer real. Drop
        // it from the import set. Combined with the diff-delete pass
        // in `sync_subscription_content_inner`, a stale cached row
        // for the same provider_event_key gets removed on the next
        // refresh. CONFIRMED / TENTATIVE flow through unchanged — we
        // don't model a "tentative" UI state today, so they render as
        // ordinary events.
        if matches!(self.status.as_deref(), Some("CANCELLED")) {
            return Ok(None);
        }

        let summary = self.summary.unwrap_or_else(|| "(untitled)".to_string());

        // reject over-length VEVENT fields before they
        // reach the DB. `parse_ics_events` treats a Validation error
        // as a per-event skip (see its `continue`-on-error match), so
        // a single malicious event doesn't poison the whole feed.
        if summary.chars().count() > MAX_TITLE_LENGTH {
            return Err(CalendarSubscriptionError::Validation(format!(
                "VEVENT {uid}: SUMMARY exceeds {MAX_TITLE_LENGTH} chars"
            )));
        }
        if let Some(ref d) = self.description {
            if d.chars().count() > MAX_BODY_LENGTH {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "VEVENT {uid}: DESCRIPTION exceeds {MAX_BODY_LENGTH} chars"
                )));
            }
        }
        if let Some(ref l) = self.location {
            if l.chars().count() > MAX_ICS_SHORT_FIELD_LENGTH {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "VEVENT {uid}: LOCATION exceeds {MAX_ICS_SHORT_FIELD_LENGTH} chars"
                )));
            }
        }
        if let Some(ref o) = self.organizer {
            if o.chars().count() > MAX_ICS_SHORT_FIELD_LENGTH {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "VEVENT {uid}: ORGANIZER exceeds {MAX_ICS_SHORT_FIELD_LENGTH} chars"
                )));
            }
        }
        if let Some(ref u) = self.url {
            if u.chars().count() > MAX_ICS_SHORT_FIELD_LENGTH {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "VEVENT {uid}: URL exceeds {MAX_ICS_SHORT_FIELD_LENGTH} chars"
                )));
            }
        }
        if self.attendees.len() > MAX_ATTENDEES_PER_EVENT {
            return Err(CalendarSubscriptionError::Validation(format!(
                "VEVENT {uid}: ATTENDEE count {} exceeds cap {MAX_ATTENDEES_PER_EVENT}",
                self.attendees.len()
            )));
        }
        let dtstart_key = self.dtstart_key.as_deref().ok_or_else(|| {
            CalendarSubscriptionError::Validation(format!(
                "Malformed VEVENT {uid}: missing DTSTART"
            ))
        })?;
        let dtstart_value = self.dtstart_value.as_deref().ok_or_else(|| {
            CalendarSubscriptionError::Validation(format!(
                "Malformed VEVENT {uid}: missing DTSTART value"
            ))
        })?;

        let registry_arg = if registry.is_empty() {
            None
        } else {
            Some(registry)
        };
        let start = parse_ics_datetime_with_registry(
            dtstart_key,
            dtstart_value,
            registry_arg,
            unknown_tzid_sink,
        )
        .map_err(|err| {
            CalendarSubscriptionError::Validation(format!("Malformed VEVENT {uid}: {err}"))
        })?;
        let end = match (self.dtend_key.as_deref(), self.dtend_value.as_deref()) {
            (Some(k), Some(v)) => {
                parse_ics_datetime_with_registry(k, v, registry_arg, unknown_tzid_sink).map_err(
                    |err| {
                        CalendarSubscriptionError::Validation(format!(
                            "Malformed VEVENT {uid}: {err}"
                        ))
                    },
                )?
            }
            _ => IcsDateTime {
                date: None,
                time: None,
                all_day: false,
                source_time_kind: "floating".to_string(),
                source_tzid: None,
            },
        };

        let start_date = start.date.ok_or_else(|| {
            CalendarSubscriptionError::Validation(format!(
                "Malformed VEVENT {uid}: missing parsed DTSTART date"
            ))
        })?;

        // resolve EXDATE values through the
        // per-feed VTIMEZONE registry (and the IANA / Windows-shim
        // fallback) so wall-clock times in non-UTC zones land on the
        // correct UTC date. `normalize_ics_datetime_to_date` returns
        // None for malformed values — we silently skip them, mirroring
        // the surrounding "ignore one bad EXDATE rather than fail the
        // whole feed" policy.
        let mut exdates: Vec<String> = self
            .exdates_raw
            .iter()
            .filter_map(|(k, v)| {
                normalize_ics_datetime_to_date(k, v, registry_arg, unknown_tzid_sink)
            })
            .collect();
        let exdates_json = if exdates.is_empty() {
            None
        } else {
            exdates.sort();
            exdates.dedup();
            Some(serde_json::to_string(&exdates).unwrap_or_default())
        };

        // Serialize attendees to JSON array if any were collected
        let attendees_json = if self.attendees.is_empty() {
            None
        } else {
            let arr: Vec<serde_json::Value> = self
                .attendees
                .into_iter()
                .map(|(email, name, status)| {
                    let mut obj = serde_json::Map::new();
                    obj.insert("email".to_string(), serde_json::Value::String(email));
                    if let Some(n) = name {
                        obj.insert("name".to_string(), serde_json::Value::String(n));
                    }
                    if let Some(s) = status {
                        obj.insert(
                            "status".to_string(),
                            serde_json::Value::String(s.to_lowercase()),
                        );
                    }
                    serde_json::Value::Object(obj)
                })
                .collect();
            Some(serde_json::to_string(&arr).unwrap_or_default())
        };

        // apply the calendar-level
        // `X-WR-TIMEZONE` as a default for DTSTART that came back
        // tagged `floating` (no DTSTART;TZID, no `Z` suffix). RFC 5545
        // doesn't standardize X-WR-TIMEZONE, but Google Calendar
        // exports rely on it: a feed with `X-WR-TIMEZONE:America/Los_Angeles`
        // and `DTSTART:20260318T090000` (note: no `Z`) means
        // 9:00 AM Los Angeles, not 9:00 AM floating. Without this
        // fallback the projection layer rendered every Google
        // Calendar event in the viewer's local zone, off by the
        // author's UTC offset.
        let (final_time_kind, final_tzid) =
            if start.source_time_kind == "floating" && !start.all_day && start.time.is_some() {
                if let Some(zone) = x_wr_timezone {
                    ("tzid".to_string(), Some(zone.to_string()))
                } else {
                    (start.source_time_kind, start.source_tzid)
                }
            } else {
                (start.source_time_kind, start.source_tzid)
            };

        // RECURRENCE-ID with TZID round-trip.
        // The composite-key contract (uid + "+" + recurrence_id) needs
        // a canonical recurrence_id so two feeds describing the same
        // overridden occurrence — one with `;TZID=America/New_York:20260408T090000`
        // and the other with `:20260408T130000Z` — collapse onto the
        // same key. Normalize through the same registry/IANA path as
        // DTSTART; if normalization fails for any reason, fall back to
        // the raw value (the recurrence_id remains addressable in the
        // override).
        let recurrence_id = match (
            self.recurrence_id_key.as_deref(),
            self.recurrence_id_value.as_deref(),
        ) {
            (Some(k), Some(v)) => Some(normalize_recurrence_id(
                k,
                v,
                registry_arg,
                unknown_tzid_sink,
            )),
            _ => None,
        };

        // Fall back to URI ATTACH when the VEVENT did not carry an
        // explicit URL line. This keeps Zoom/Teams meeting invites
        // (which often emit `ATTACH;FMTTYPE=text/html:https://…`)
        // routable without forcing the feed to also set URL.
        let url = self.url.or(self.attach_url);

        Ok(Some(ParsedEvent {
            uid,
            summary,
            description: self.description,
            start_date,
            start_time: start.time,
            end_date: end.date,
            end_time: end.time,
            all_day: start.all_day,
            location: self.location,
            organizer: self.organizer,
            recurrence_id,
            source_time_kind: final_time_kind,
            source_tzid: final_tzid,
            rrule: self.rrule,
            exdates_json,
            attendees_json,
            url,
            sequence: self.sequence.unwrap_or(0),
            dtstamp: self.dtstamp,
        }))
    }
}
