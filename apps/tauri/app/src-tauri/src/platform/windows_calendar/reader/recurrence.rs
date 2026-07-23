#![cfg_attr(not(target_os = "windows"), allow(dead_code))]

use lorvex_domain::validation::{normalize_calendar_recurrence, ValidationError};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WindowsRecurrenceShape {
    Daily,
    Weekly,
    MonthlyDate,
    MonthlyWeekday,
    YearlyDate,
    YearlyWeekday,
}

impl WindowsRecurrenceShape {
    fn freq(self) -> &'static str {
        match self {
            Self::Daily => "DAILY",
            Self::Weekly => "WEEKLY",
            Self::MonthlyDate | Self::MonthlyWeekday => "MONTHLY",
            Self::YearlyDate | Self::YearlyWeekday => "YEARLY",
        }
    }

    fn uses_day_of_month(self) -> bool {
        matches!(self, Self::MonthlyDate | Self::YearlyDate)
    }

    fn uses_weekday_ordinal(self) -> bool {
        matches!(self, Self::MonthlyWeekday | Self::YearlyWeekday)
    }

    fn uses_year_month(self) -> bool {
        matches!(self, Self::YearlyDate | Self::YearlyWeekday)
    }
}

fn normalize_windows_recurrence_map(
    map: serde_json::Map<String, serde_json::Value>,
) -> Result<Option<String>, ValidationError> {
    let raw = serde_json::Value::Object(map).to_string();
    normalize_calendar_recurrence(Some(&raw))
}

#[cfg(target_os = "windows")]
pub(super) fn extract_windows_recurrence(
    appt: &windows::ApplicationModel::Appointments::Appointment,
) -> Option<String> {
    use windows::ApplicationModel::Appointments::*;
    let recurrence = appt.Recurrence().ok()??;
    let unit = recurrence.Unit().ok()?;
    // Log the unknown recurrence-unit variant to `error_logs` so
    // Settings → Diagnostics surfaces it for triage, then return
    // `None` so the caller upserts the appointment as a one-shot.
    // A bare `_ => return None` would silently lose the recurrence
    // pattern when the WinRT enum carries a value this SDK build
    // doesn't know about (a future SDK adding e.g. "Hourly", or an
    // aggregator-supplied appointment with a historical enum value
    // the broker forwards verbatim) and users would see an Outlook
    // recurring meeting appear only once. The
    // log message includes the raw enum so the next time we add
    // an SDK rev we know which variants need first-class
    // mapping.
    let shape = match unit {
        AppointmentRecurrenceUnit::Daily => WindowsRecurrenceShape::Daily,
        AppointmentRecurrenceUnit::Weekly => WindowsRecurrenceShape::Weekly,
        AppointmentRecurrenceUnit::Monthly => WindowsRecurrenceShape::MonthlyDate,
        AppointmentRecurrenceUnit::MonthlyOnDay => WindowsRecurrenceShape::MonthlyWeekday,
        AppointmentRecurrenceUnit::Yearly => WindowsRecurrenceShape::YearlyDate,
        AppointmentRecurrenceUnit::YearlyOnDay => WindowsRecurrenceShape::YearlyWeekday,
        other => {
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    "platform.windows_calendar",
                    &format!(
                        "Windows recurrence carried unknown AppointmentRecurrenceUnit \
                         variant ({other:?}); emitting appointment as non-recurring \
                         so the caller still sees the title/start/duration."
                    ),
                    None,
                    Some("warn".to_string()),
                );
            }
            return None;
        }
    };
    let mut map = serde_json::Map::new();
    map.insert(
        "FREQ".to_string(),
        serde_json::Value::String(shape.freq().to_string()),
    );
    if let Ok(interval) = recurrence.Interval() {
        if interval > 1 {
            map.insert("INTERVAL".to_string(), serde_json::json!(interval));
        }
    }
    if let Ok(occurrences) = recurrence.Occurrences() {
        if let Some(count) = occurrences {
            if count > 0 {
                map.insert("COUNT".to_string(), serde_json::json!(count));
            }
        }
    }

    // Read `AppointmentRecurrence::Until()` and surface it as an
    // RFC 5545 `UNTIL=` token. Without this, only `COUNT` (via
    // `Occurrences`) would be honored, and a 6-week repeating
    // meeting whose pattern is bounded with an "ends on" date — the
    // common Outlook case — would be emitted as an unbounded RRULE
    // and the renderer would project synthetic occurrences forever.
    // `Until()` returns `IReference<DateTime>` (nullable); `Some`
    // means the pattern has an end-date, `None` means open-ended.
    //
    // Format follows RFC 5545 §3.3.10: `UNTIL=` is a UTC
    // DATE-TIME in basic-format `YYYYMMDDTHHMMSSZ`. Even when the
    // appointment is wall-clock-anchored on the device, the
    // `DateTime` we receive is already in UTC ticks per the
    // WinRT contract, so converting to `chrono::DateTime<Utc>`
    // and formatting in basic form is correct.
    if let Ok(until_ref) = recurrence.Until() {
        if let Ok(until_dt) = until_ref.Value() {
            let unix_secs = (until_dt.UniversalTime
                - crate::platform::provider_time::UNIX_TO_FILETIME_OFFSET)
                / crate::platform::provider_time::WINDOWS_TICKS_PER_SECOND;
            if let Some(utc) = chrono::DateTime::<chrono::Utc>::from_timestamp(unix_secs, 0) {
                let until_str = utc.format("%Y%m%dT%H%M%SZ").to_string();
                map.insert("UNTIL".to_string(), serde_json::Value::String(until_str));
            }
        }
    }

    // Extract DaysOfWeek for weekly recurrences.
    // AppointmentDaysOfWeek is a flags enum: Sunday=0x1, Monday=0x2, Tuesday=0x4,
    // Wednesday=0x8, Thursday=0x10, Friday=0x20, Saturday=0x40.
    if matches!(shape, WindowsRecurrenceShape::Weekly) {
        if let Ok(days) = recurrence.DaysOfWeek() {
            let bits = days.0;
            if bits != 0 {
                const DAY_FLAGS: [(u32, &str); 7] = [
                    (0x1, "SU"),
                    (0x2, "MO"),
                    (0x4, "TU"),
                    (0x8, "WE"),
                    (0x10, "TH"),
                    (0x20, "FR"),
                    (0x40, "SA"),
                ];
                let byday: Vec<&str> = DAY_FLAGS
                    .iter()
                    .filter(|(flag, _)| bits & flag != 0)
                    .map(|(_, code)| *code)
                    .collect();
                if !byday.is_empty() {
                    map.insert(
                        "BYDAY".to_string(),
                        serde_json::Value::Array(
                            byday
                                .into_iter()
                                .map(|d| serde_json::Value::String(d.to_string()))
                                .collect(),
                        ),
                    );
                }
            }
        }
    }

    // Extract Day (day-of-month) for monthly and yearly recurrences.
    if shape.uses_day_of_month() {
        if let Ok(day) = recurrence.Day() {
            if day > 0 {
                // BYMONTHDAY is canonically an array of ints.
                map.insert("BYMONTHDAY".to_string(), serde_json::json!([day]));
            }
        }
    }

    // Surface `BYSETPOS` and `BYDAY` for MonthlyOnDay /
    // YearlyOnDay recurrences. Emitting only `BYMONTHDAY` would
    // round-trip an Outlook recurrence like "second Tuesday of
    // every month" through Lorvex as "every 14th of the month" —
    // a different rule that drifts on months where the second
    // Tuesday falls on any day other than the 14th. The Windows
    // API exposes the ordinal via `WeekOfMonth` (1..5 for
    // first..fifth, with the documented sentinel of 5 meaning
    // "last") and the matching weekday via `DaysOfWeek` (single-bit
    // flags for MonthlyOnDay rules; the same bitfield as the
    // weekly pattern). Translate to Lorvex's canonical RRULE JSON:
    // `BYSETPOS` carries the ordinal array (`[-1]` for "last"),
    // and `BYDAY` carries the two-letter weekday code(s).
    if shape.uses_weekday_ordinal() {
        if let Ok(week_of_month) = recurrence.WeekOfMonth() {
            if (1..=5).contains(&week_of_month) {
                // Convention: 5 means "last" per the WinRT docs;
                // RFC 5545 uses -1 for "last". 1..4 map directly.
                let bysetpos = if week_of_month == 5 {
                    -1
                } else {
                    week_of_month
                };
                map.insert("BYSETPOS".to_string(), serde_json::json!([bysetpos]));
            }
        }
        if let Ok(days) = recurrence.DaysOfWeek() {
            let bits = days.0;
            if bits != 0 {
                const DAY_FLAGS: [(u32, &str); 7] = [
                    (0x1, "SU"),
                    (0x2, "MO"),
                    (0x4, "TU"),
                    (0x8, "WE"),
                    (0x10, "TH"),
                    (0x20, "FR"),
                    (0x40, "SA"),
                ];
                let byday: Vec<&str> = DAY_FLAGS
                    .iter()
                    .filter(|(flag, _)| bits & flag != 0)
                    .map(|(_, code)| *code)
                    .collect();
                if !byday.is_empty() {
                    map.insert(
                        "BYDAY".to_string(),
                        serde_json::Value::Array(
                            byday
                                .into_iter()
                                .map(|d| serde_json::Value::String(d.to_string()))
                                .collect(),
                        ),
                    );
                }
            }
        }
    }

    // emit `BYMONTH` for YEARLY rules as the canonical month array
    // (both Yearly and YearlyOnDay). The `Month` property is
    // 1..12 for the target month; without this an Outlook
    // recurrence like "every July" round-tripped as "every
    // year on day-of-month X" without specifying the month.
    if shape.uses_year_month() {
        if let Ok(month) = recurrence.Month() {
            if (1..=12).contains(&month) {
                map.insert("BYMONTH".to_string(), serde_json::json!([month]));
            }
        }
    }

    // `RecurrenceTimeZone()` is deliberately not written into the
    // recurrence JSON. The shared calendar recurrence contract only
    // accepts RRULE fields; timezone anchoring belongs in provider
    // time semantics, not as an ad-hoc `TZID` key that downstream
    // canonicalizers reject.
    if let Ok(rec_tz) = recurrence.RecurrenceTimeZone() {
        // #3051 M10: WinRT `HSTRING.to_string()` can carry trailing
        // whitespace, BOMs, or NUL terminators on legacy Outlook
        // providers (per the windows-rs upstream issue thread on
        // HSTRING boundary). Trim before passing to
        // `normalize_timezone_name` so a valid IANA name with
        // accidental decoration is not rejected as "not IANA".
        let tz_text = rec_tz.to_string();
        let tz_trimmed = tz_text.trim();
        if lorvex_domain::normalize_timezone_name(Some(tz_trimmed)).is_none()
            && !tz_trimmed.is_empty()
        {
            // #3051 M9: legacy WinRT providers return Windows TZID
            // display names ("Pacific Standard Time"). Until the
            // CLDR `windowsZones.xml` lookup table is shipped, drop
            // the value (RFC 5545 + cross-platform sync require
            // IANA) but emit an `error_log` entry so the regression
            // is observable in Settings → Diagnostics. Without this
            // signal a Windows user with a legacy provider gets NO
            // tzid persisted on every recurrence and there is no
            // surface — just silently broken cross-platform
            // recurrence rendering.
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    "platform.windows_calendar.non_iana_tzid",
                    &format!(
                        "Windows calendar provider returned non-IANA timezone \
                         {tz_trimmed:?} for a recurring event; TZID dropped from \
                         the recurrence payload (RFC 5545 + cross-platform sync \
                         require IANA). Ship windowsZones.xml lookup table to \
                         map this verbatim form."
                    ),
                    None,
                    Some("warn".to_string()),
                );
            }
        }
    }

    match normalize_windows_recurrence_map(map) {
        Ok(normalized) => normalized,
        Err(err) => {
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    "platform.windows_calendar.invalid_recurrence",
                    &format!(
                        "Windows calendar recurrence failed domain normalization; \
                         emitting appointment as non-recurring. Error: {err}"
                    ),
                    None,
                    Some("warn".to_string()),
                );
            }
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(
        entries: impl IntoIterator<Item = (&'static str, serde_json::Value)>,
    ) -> serde_json::Map<String, serde_json::Value> {
        entries
            .into_iter()
            .map(|(key, value)| (key.to_string(), value))
            .collect()
    }

    #[test]
    fn windows_recurrence_normalization_canonicalizes_interval_and_until() {
        let normalized = normalize_windows_recurrence_map(map([
            ("FREQ", serde_json::json!("WEEKLY")),
            ("UNTIL", serde_json::json!("20261231T235959Z")),
        ]))
        .expect("weekly recurrence should normalize")
        .expect("weekly recurrence should be present");

        assert_eq!(
            normalized,
            r#"{"FREQ":"WEEKLY","INTERVAL":1,"UNTIL":"2026-12-31"}"#
        );
    }

    #[test]
    fn windows_recurrence_normalization_rejects_tzid_key() {
        let err = normalize_windows_recurrence_map(map([
            ("FREQ", serde_json::json!("DAILY")),
            ("TZID", serde_json::json!("America/Los_Angeles")),
        ]))
        .expect_err("TZID must stay outside recurrence JSON");

        assert!(
            err.to_string().contains("unknown key 'TZID'"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn windows_recurrence_normalization_rejects_calendar_count_above_cap() {
        let err = normalize_windows_recurrence_map(map([
            ("FREQ", serde_json::json!("DAILY")),
            ("COUNT", serde_json::json!(366)),
        ]))
        .expect_err("calendar recurrence COUNT should be capped");

        assert!(
            err.to_string().contains("recurrence.COUNT is out of range"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn weekday_ordinal_shapes_do_not_emit_day_of_month_filters() {
        assert!(WindowsRecurrenceShape::MonthlyDate.uses_day_of_month());
        assert!(WindowsRecurrenceShape::YearlyDate.uses_day_of_month());
        assert!(!WindowsRecurrenceShape::MonthlyWeekday.uses_day_of_month());
        assert!(!WindowsRecurrenceShape::YearlyWeekday.uses_day_of_month());
        assert!(WindowsRecurrenceShape::MonthlyWeekday.uses_weekday_ordinal());
        assert!(WindowsRecurrenceShape::YearlyWeekday.uses_weekday_ordinal());
    }

    #[test]
    fn monthly_weekday_ordinal_recurrence_normalizes_without_bymonthday() {
        let normalized = normalize_windows_recurrence_map(map([
            ("FREQ", serde_json::json!("MONTHLY")),
            ("BYDAY", serde_json::json!(["TU"])),
            ("BYSETPOS", serde_json::json!([2])),
        ]))
        .expect("monthly ordinal recurrence should normalize")
        .expect("monthly ordinal recurrence should be present");

        assert_eq!(
            normalized,
            r#"{"BYDAY":["TU"],"BYSETPOS":[2],"FREQ":"MONTHLY","INTERVAL":1}"#
        );
        assert!(!normalized.contains("BYMONTHDAY"));
    }
}
