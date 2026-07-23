/// extract the top-level `METHOD:` property,
/// uppercased, if present anywhere outside a VEVENT/VTIMEZONE/VALARM
/// nest. RFC 5545 §3.7.2 requires METHOD at the calendar object level
/// when an iTIP message is being transmitted; values include
/// `PUBLISH`, `REQUEST`, `REPLY`, `CANCEL`, `REFRESH`, `COUNTER`,
/// `DECLINECOUNTER`, `ADD`. We only special-case `CANCEL` today —
/// other values flow through as ordinary publishes.
pub(super) fn extract_calendar_method(unfolded_lines: &[String]) -> Option<String> {
    let mut depth = 0i32;
    for line in unfolded_lines {
        let line = line.trim();
        if line.eq_ignore_ascii_case("BEGIN:VCALENDAR") {
            // Top-level container; depth stays at 0 for its body.
            continue;
        }
        if line.eq_ignore_ascii_case("END:VCALENDAR") {
            continue;
        }
        if let Some(rest) = line.strip_prefix("BEGIN:") {
            if !rest.eq_ignore_ascii_case("VCALENDAR") {
                depth += 1;
            }
            continue;
        }
        if let Some(rest) = line.strip_prefix("END:") {
            if !rest.eq_ignore_ascii_case("VCALENDAR") {
                depth -= 1;
            }
            continue;
        }
        if depth == 0 {
            if let Some(value) = line.strip_prefix("METHOD:") {
                return Some(value.trim().to_ascii_uppercase());
            }
        }
    }
    None
}

/// Google-style calendar-level fallback zone.
/// Google Calendar exports a single `X-WR-TIMEZONE:` line at the
/// VCALENDAR root and omits per-event TZID parameters. Without
/// applying it, every event lands in "floating" mode and the
/// projection layer renders them at the viewer's wall clock instead
/// of the author's intended local time. The value is treated as a
/// default — it never overrides an explicit DTSTART;TZID= or a `Z`
/// suffix, both of which carry their own zone semantics.
pub(super) fn extract_x_wr_timezone(unfolded_lines: &[String]) -> Option<String> {
    let mut depth = 0i32;
    for line in unfolded_lines {
        let line = line.trim();
        if line.eq_ignore_ascii_case("BEGIN:VCALENDAR")
            || line.eq_ignore_ascii_case("END:VCALENDAR")
        {
            continue;
        }
        if let Some(rest) = line.strip_prefix("BEGIN:") {
            if !rest.eq_ignore_ascii_case("VCALENDAR") {
                depth += 1;
            }
            continue;
        }
        if let Some(rest) = line.strip_prefix("END:") {
            if !rest.eq_ignore_ascii_case("VCALENDAR") {
                depth -= 1;
            }
            continue;
        }
        if depth == 0 {
            if let Some(value) = line.strip_prefix("X-WR-TIMEZONE:") {
                let trimmed = value.trim().trim_matches('"');
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
        }
    }
    None
}

/// Unfold RFC 5545 continuation lines (CRLF + space/tab = continuation).
///
/// RFC 5545 §3.1 mandates CRLF line endings, but real-world feeds
/// emit LF or mixed endings — particularly hand-edited `.ics` files
/// and feeds that round-tripped through tools normalizing to Unix
/// endings. `str::lines()` strips a trailing `\n` and the preceding
/// `\r` if present, so it canonicalizes CRLF → LF for free
/// regardless of how the source feed terminated each line. The mixed-
/// ending fixture covered in the test suite confirms a single feed
/// containing both `\r\n` and `\n` line terminators parses identically.
pub(super) fn unfold_lines(content: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();

    for line in content.lines() {
        if line.starts_with(' ') || line.starts_with('\t') {
            // Continuation line — append without the leading whitespace
            current.push_str(line.trim_start());
        } else {
            if !current.is_empty() {
                result.push(std::mem::take(&mut current));
            }
            current = line.to_string();
        }
    }
    if !current.is_empty() {
        result.push(current);
    }
    result
}
