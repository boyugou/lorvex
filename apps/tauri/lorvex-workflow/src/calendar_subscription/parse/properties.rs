/// does an ATTACH key carry inline binary data?
/// RFC 5545 §3.8.1.1 specifies `ENCODING=BASE64` together with
/// `VALUE=BINARY` for the inline form. Either parameter alone is a
/// strong indicator (some emitters drop the redundant pair); match
/// case-insensitively.
pub(super) fn attach_is_inline_binary(key: &str) -> bool {
    for part in key.split(';').skip(1) {
        let upper = part.to_ascii_uppercase();
        if upper == "VALUE=BINARY" || upper == "ENCODING=BASE64" {
            return true;
        }
    }
    false
}

/// canonical `mailto:` scheme stripper for
/// ORGANIZER and ATTENDEE values. RFC 5545 §3.3.3 declares URI
/// schemes case-insensitive; many enterprise calendar servers emit
/// `MAILTO:` (uppercase) and a small handful pad the value with
/// surrounding whitespace. Returns the bare email portion, trimmed.
pub(super) fn strip_mailto_scheme(raw: &str) -> String {
    let trimmed = raw.trim();
    // ASCII case-insensitive prefix match without allocating.
    if trimmed.len() >= 7 {
        let (head, rest) = trimmed.split_at(7);
        if head.eq_ignore_ascii_case("mailto:") {
            return rest.trim().to_string();
        }
    }
    trimmed.to_string()
}

pub(super) fn split_ics_line(line: &str) -> Option<(&str, &str)> {
    let colon_pos = line.find(':')?;
    Some((&line[..colon_pos], &line[colon_pos + 1..]))
}

/// Extract a named parameter from an ICS property key.
///
/// Given a key like `ATTENDEE;CN=John Doe;PARTSTAT=ACCEPTED` and param `"CN"`,
/// returns `Some("John Doe")`. Handles quoted values (`CN="John Doe"`).
pub(crate) fn extract_ics_param(key: &str, param_name: &str) -> Option<String> {
    let prefix = format!("{param_name}=");
    for part in key.split(';').skip(1) {
        if let Some(rest) = part.strip_prefix(&prefix) {
            let value = rest.trim_matches('"');
            return Some(value.to_string());
        }
    }
    None
}

/// Reverse the four ICS escape sequences (`\n`/`\N`, `\,`, `\;`, `\\`) and
/// then scrub the result of characters that have no business appearing in a
/// human-readable SUMMARY/DESCRIPTION/LOCATION/etc.
///
/// an upstream ICS feed can legitimately (or maliciously) embed
/// raw C0/C1 control bytes, ANSI CSI escape sequences, and bidi/zero-width
/// overrides directly in property values. None of these are meaningful in a
/// calendar entry, but they will flow straight through to the UI, terminals
/// that happen to render notification text, and cloud/provider transports. The scrub pass
/// runs AFTER escape-sequence resolution so that a `\\u{001B}`-style
/// unescape trick cannot smuggle an ANSI CSI through.
///
/// Newline (U+000A) and tab (U+0009) are preserved because they're
/// legitimately emitted by `\n`/`\N` unescape and by multi-paragraph feeds.
/// CR (U+000D) is dropped outright: RFC 5545 line folding uses CRLF, which
/// the caller already unfolds before we see the value, so any bare CR
/// reaching us is either a Windows-line-ending artifact or a spoofing
/// attempt, and we canonicalize to LF either way.
///
/// Unicode normalization is intentionally NOT performed here — it is
/// tracked separately as future work.
pub(crate) fn unescape_ics(value: &str) -> String {
    let unescaped = value
        .replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\");
    // Shared helper in lorvex-domain.
    lorvex_domain::text_sanitize::strip_dangerous_codepoints(&unescaped)
}
