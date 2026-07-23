//! Format-shape validators (date, time).
//!
//! `validate_time_format` delegates to [`crate::parsing::parse_hhmm_to_minutes`]
//! so the validator and the parser share one definition of well-formed
//! `HH:MM`: any input the parser accepts is by definition valid for the
//! validator (audit D1).

use super::error::ValidationError;

/// Validate a date string: must be `YYYY-MM-DD` and represent a real calendar date.
///
/// Thin wrapper over [`crate::time::parse_iso_date`] for callers that
/// only care about validity (not the parsed value). Routing through one
/// helper guarantees the validator and every direct date parser
/// (`canonical_occurrence_date`, `start_date`, etc.) share a single
/// definition of well-formed.
pub fn validate_date_format(s: &str) -> Result<(), ValidationError> {
    crate::time::parse_iso_date(s).map(|_| ())
}

/// Validate that an optional calendar `end_date` does not precede
/// `start_date`. Both inputs are expected to be `YYYY-MM-DD`
/// strings; lex order on that canonical shape coincides with calendar
/// order, so a string compare is correct.
///
/// Returns `Ok(None)` if `end_date` is absent, otherwise `Ok(Some(end_date))`
/// borrowing the original slice. Surfaces a typed `ValidationError` so each
/// crate (MCP / CLI / Tauri) can wrap into its own error envelope without
/// duplicating the comparison logic.
pub fn validate_calendar_date_range<'a>(
    start_date: &str,
    end_date: Option<&'a str>,
) -> Result<Option<&'a str>, ValidationError> {
    let Some(end) = end_date else {
        return Ok(None);
    };
    if end < start_date {
        return Err(ValidationError::InvalidFormat {
            field: "end_date",
            expected: "end_date must be on or after start_date",
            actual: format!("end_date={end}, start_date={start_date}"),
        });
    }
    Ok(Some(end))
}

/// Validate a time string: must be `HH:MM` with hours 00-23 and minutes 00-59.
pub fn validate_time_format(s: &str) -> Result<(), ValidationError> {
    if crate::parsing::parse_hhmm_to_minutes(s).is_some() {
        Ok(())
    } else {
        Err(ValidationError::InvalidFormat {
            field: "time",
            expected: "HH:MM (00:00-23:59)",
            actual: s.to_string(),
        })
    }
}

/// Validate a URL accepted from user input. Calendar
/// events expose a clickable URL field that the UI renders as a
/// link; without an allowlist a stored XSS payload via
/// `javascript:` or `data:` would execute on click. We accept only
/// the schemes that make sense for human-clickable links and
/// require the parser to recognise the input as a URL.
///
/// Schemes accepted: `http`, `https`, `mailto`, `tel`. Empty or
/// whitespace-only input is rejected — callers that want optional
/// URL fields should pass `None` rather than `""` (or strip the
/// field at the boundary).
///
/// Runs `sanitize_user_text` BEFORE scheme matching so a URL with
/// leading bidi-override / zero-width / control codepoints can't
/// smuggle a `javascript:` payload past the allowlist. A bare
/// `lowered.starts_with("http://")` plus `is_control()` /
/// `is_whitespace()` checks would still let an attacker craft a
/// prefix like `\u{200B}\u{202E}javascript:alert(1)` that happens to
/// match `http://...` after one ZW character.
///
/// Returns the sanitized + trimmed canonical form so callers
/// persist that — not the raw input — into storage. A `()` return
/// would let every caller bind the raw string to its INSERT: a URL
/// like `\u{200B}https://example.com` would validate cleanly (the
/// leading zero-width is stripped before the scheme matcher) yet
/// still write the original zero-width-prefixed form into
/// `calendar_events.url`. Returning the canonical form makes the
/// validator the single source of truth for what gets stored and
/// removes the gap between what was checked and what is persisted.
/// Per-validator message bundle for [`validate_url_with_scheme_allowlist`].
/// Each field is a `&'static str` literal so `ValidationError` keeps
/// its zero-allocation `expected` shape.
struct UrlMessages {
    empty_expected: &'static str,
    scheme_expected: &'static str,
    control_expected: &'static str,
    whitespace_expected: &'static str,
}

/// Shared body for [`validate_user_url`] and [`validate_calendar_url`].
/// Walks: sanitize → trim → empty-check → scheme-allowlist → control
/// chars → whitespace → lowercase-scheme. The two public surfaces
/// differ only in the allowed schemes and the per-error-message
/// strings (`"URL …"` vs `"calendar URL …"`).
fn validate_url_with_scheme_allowlist(
    s: &str,
    allowed_prefixes: &[&str],
    msgs: &UrlMessages,
) -> Result<String, ValidationError> {
    // sanitize before scheme matching so a hostile peer
    // can't smuggle a `javascript:` / `webcal:` shadow attack past
    // the allowlist behind leading bidi / zero-width codepoints.
    let cleaned = crate::sanitize_user_text(s);
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        return Err(ValidationError::InvalidFormat {
            field: "url",
            expected: msgs.empty_expected,
            actual: s.to_string(),
        });
    }
    // Cheap scheme check first — `url::Url::parse` would reject the
    // unsafe schemes too, but we want a stable error message and the
    // option to stay decoupled from the `url` crate.
    let lowered = trimmed.to_ascii_lowercase();
    if !allowed_prefixes.iter().any(|p| lowered.starts_with(p)) {
        return Err(ValidationError::InvalidFormat {
            field: "url",
            expected: msgs.scheme_expected,
            actual: s.to_string(),
        });
    }
    // Reject control characters — those usually indicate a paste-mangled
    // value or a deliberate injection attempt.
    if trimmed.chars().any(char::is_control) {
        return Err(ValidationError::InvalidFormat {
            field: "url",
            expected: msgs.control_expected,
            actual: s.to_string(),
        });
    }
    // Disallow any Unicode whitespace — modern URLs encode literal
    // spaces as `%20`. Without this check, `http://foo bar.com` would
    // pass because `is_control()` only catches U+0000..U+001F /
    // U+007F..U+009F, and a typo'd address could slip past as a
    // broken click later.
    if trimmed.chars().any(char::is_whitespace) {
        return Err(ValidationError::InvalidFormat {
            field: "url",
            expected: msgs.whitespace_expected,
            actual: s.to_string(),
        });
    }
    // RFC 3986 §3.1: scheme is case-insensitive, canonically
    // lowercase. Lowercase the scheme on the canonical return so
    // downstream dedup buckets converge across `MAILTO:foo` and
    // `mailto:foo`, `WEBCAL://Example.com` and
    // `webcal://Example.com`.
    Ok(lowercase_url_scheme(trimmed))
}

pub fn validate_user_url(s: &str) -> Result<String, ValidationError> {
    // this validator intentionally accepts plain
    // `http://` URLs. It is the general-purpose link validator used
    // for task `url`, calendar event `url`, notes markdown
    // links, etc. — places where a user pastes a link they want
    // Lorvex to remember. Many internal corporate intranets, lab
    // hosts, and self-hosted services still serve only http; rejecting
    // them would degrade usability without a meaningful security gain
    // (the link is not auto-fetched from this validator). The stricter
    // https-only policy lives in `validate_calendar_url` (audit
    // #2988-M9) because calendar subscription URLs *are* auto-fetched
    // by the background sync, where a plaintext feed leaks
    // bearer-equivalent path tokens. Do not collapse the two
    // validators back into one.
    const ALLOWED_PREFIXES: &[&str] = &["http://", "https://", "mailto:", "tel:"];
    static MSGS: UrlMessages = UrlMessages {
        empty_expected: "non-empty URL with http://, https://, mailto:, or tel: scheme",
        scheme_expected: "scheme must be http, https, mailto, or tel",
        control_expected: "URL must not contain control characters",
        whitespace_expected: "URL must not contain whitespace; encode spaces as %20",
    };
    validate_url_with_scheme_allowlist(s, ALLOWED_PREFIXES, &MSGS)
}

/// Lowercase only the scheme portion of a URL (everything before the
/// first `:`). Leaves the authority/path/query untouched — those
/// segments are case-sensitive under RFC 3986. If the input has no
/// colon (a pre-validation error path the caller should have caught
/// earlier) the value is returned verbatim.
fn lowercase_url_scheme(s: &str) -> String {
    let Some(colon_idx) = s.find(':') else {
        return s.to_string();
    };
    let scheme = &s[..colon_idx];
    // Skip the `format!` allocation when the scheme is already
    // lowercase — overwhelmingly the common case for paste-from-clipboard
    // URLs and for anything emitted by `validate_user_url` /
    // `validate_calendar_url` after the first save round-trips.
    if scheme.bytes().all(|b| !b.is_ascii_uppercase()) {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len());
    for byte in scheme.bytes() {
        out.push(byte.to_ascii_lowercase() as char);
    }
    out.push_str(&s[colon_idx..]);
    out
}

/// Validate a calendar-subscription / calendar-event URL.
///
/// Accepts only the schemes legitimately produced by calendar
/// integrations: `http`, `https`, and `webcal` (the iCalendar
/// subscription URL scheme produced by macOS Calendar.app, Google
/// Calendar's "Public address in iCal format", and most other
/// calendar feed sources).
///
/// Rejects `javascript:`, `data:`, `file:`, and every other scheme.
/// peer envelopes can otherwise write
/// `url = "javascript:alert(1)"` straight into `calendar_events.url`
/// / `calendar_subscriptions.url` via the sync apply pipeline; while
/// the downstream iCalendar fetcher restricts to http/https, a user
/// who copies the URL out of Settings → Calendar Sources, or any
/// future surface that converts the column to an `<a href>`, is
/// exploitable. This helper is the apply-layer trust-boundary
/// validator.
///
/// returns the sanitized + trimmed canonical form so
/// the apply pipeline and any future caller persists that — not the
/// raw envelope value — into `calendar_subscriptions.url` /
/// `calendar_events.url`. Mirrors the `validate_user_url` change.
pub fn validate_calendar_url(s: &str) -> Result<String, ValidationError> {
    const ALLOWED_PREFIXES: &[&str] = &["http://", "https://", "webcal://"];
    static MSGS: UrlMessages = UrlMessages {
        empty_expected: "non-empty calendar URL with http://, https://, or webcal:// scheme",
        scheme_expected: "calendar URL scheme must be http, https, or webcal",
        control_expected: "calendar URL must not contain control characters",
        whitespace_expected: "calendar URL must not contain whitespace; encode spaces as %20",
    };
    validate_url_with_scheme_allowlist(s, ALLOWED_PREFIXES, &MSGS)
}

/// Validate a CSS-style hex color: `#RGB` (3 hex digits) or `#RRGGBB`
/// (6 hex digits). Both call sites in `lorvex-cli` (the argument
/// parser in `parsers.rs` and the calendar writer in
/// `db_ops/calendar/mod.rs`) delegate here so the 3-or-6-digit rule
/// lives in one place; without this anchor, the CLI argument parser
/// could reject a 3-digit short-form color that the calendar's own
/// writer accepts (or vice versa) and a user-imported feed would
/// pass one boundary while failing the other.
pub fn validate_hex_color(s: &str) -> Result<(), ValidationError> {
    validate_hex_color_field(s, "hex_color")
}

pub fn validate_hex_color_field(s: &str, field: &'static str) -> Result<(), ValidationError> {
    let valid = (s.len() == 4 || s.len() == 7)
        && s.starts_with('#')
        && s[1..].chars().all(|c| c.is_ascii_hexdigit());
    if valid {
        Ok(())
    } else {
        Err(ValidationError::InvalidFormat {
            field,
            expected: "#RGB or #RRGGBB",
            actual: s.to_string(),
        })
    }
}
