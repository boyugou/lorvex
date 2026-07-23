use super::super::*;

#[test]
fn date_valid() {
    assert!(validate_date_format("2026-03-24").is_ok());
}

#[test]
fn date_leap_day_valid() {
    assert!(validate_date_format("2024-02-29").is_ok());
}

#[test]
fn date_leap_day_invalid() {
    assert!(validate_date_format("2023-02-29").is_err());
}

#[test]
fn date_wrong_format_slash() {
    assert!(validate_date_format("2026/03/24").is_err());
}

#[test]
fn date_wrong_format_day_month() {
    assert!(validate_date_format("24-03-2026").is_err());
}

#[test]
fn date_empty() {
    assert!(validate_date_format("").is_err());
}

#[test]
fn date_garbage() {
    assert!(validate_date_format("not-a-date").is_err());
}

#[test]
fn date_month_13() {
    assert!(validate_date_format("2026-13-01").is_err());
}

#[test]
fn date_day_32() {
    assert!(validate_date_format("2026-01-32").is_err());
}

// -- validate_user_url --------------------------------------------
//
// URLs accepted from user input must be restricted to
// schemes that the UI safely renders as clickable links. Pin the
// allowlist + reject unsafe schemes that would otherwise produce
// stored XSS via clickable `javascript:`/`data:` payloads.

#[test]
fn url_allows_https() {
    assert!(validate_user_url("https://example.com/path?x=1").is_ok());
}

#[test]
fn url_allows_http() {
    assert!(validate_user_url("http://example.com").is_ok());
}

#[test]
fn url_allows_mailto() {
    assert!(validate_user_url("mailto:user@example.com").is_ok());
}

#[test]
fn url_allows_tel() {
    assert!(validate_user_url("tel:+15555555555").is_ok());
}

#[test]
fn url_rejects_javascript_scheme() {
    assert!(validate_user_url("javascript:alert(1)").is_err());
}

#[test]
fn url_rejects_javascript_scheme_case_insensitive() {
    assert!(validate_user_url("JaVaScRiPt:alert(1)").is_err());
}

#[test]
fn url_rejects_data_scheme() {
    assert!(validate_user_url("data:text/html;base64,PHNjcmlwdD4=").is_err());
}

#[test]
fn url_rejects_file_scheme() {
    assert!(validate_user_url("file:///etc/passwd").is_err());
}

#[test]
fn url_rejects_empty() {
    assert!(validate_user_url("").is_err());
}

#[test]
fn url_rejects_whitespace_only() {
    assert!(validate_user_url("   ").is_err());
}

#[test]
fn url_rejects_no_scheme() {
    assert!(validate_user_url("example.com/path").is_err());
}

/// pre-fix the validator lowercased the URL for the
/// scheme-allowlist check but stored the trimmed mixed-case input.
/// `MAILTO:foo@example.com` validated and persisted verbatim, so
/// downstream allowlist / dedup comparisons treated the canonical
/// `mailto:` form as a different value. RFC 3986 §3.1 declares the
/// scheme case-insensitive but canonically lowercase; pin the
/// canonical lowercase scheme here.
#[test]
fn url_lowercases_scheme_in_canonical_form() {
    assert_eq!(
        validate_user_url("MAILTO:foo@example.com").unwrap(),
        "mailto:foo@example.com"
    );
    assert_eq!(
        validate_user_url("HTTPS://Example.com/Path").unwrap(),
        "https://Example.com/Path",
        "scheme lowercased but authority/path preserved"
    );
    assert_eq!(
        validate_user_url("Tel:+15555555555").unwrap(),
        "tel:+15555555555"
    );
    // Calendar URL mirrors the same normalization.
    assert_eq!(
        validate_calendar_url("WEBCAL://Example.com/feed.ics").unwrap(),
        "webcal://Example.com/feed.ics"
    );
}

#[test]
fn url_rejects_control_characters() {
    // `sanitize_user_text` runs before scheme
    // matching, which strips most C0 controls (NUL, ESC, …) outright
    // — the URL effectively loses the embedded byte. Whitespace-class
    // control characters (LF/CR/TAB) survive sanitization and the
    // `is_whitespace()` gate rejects them so a paste-mangled URL
    // still surfaces as an error.
    assert!(validate_user_url("https://example.com/\npath").is_err());
    assert!(validate_user_url("https://example.com/\rpath").is_err());
    assert!(validate_user_url("https://example.com/\tpath").is_err());
}

/// a URL with a leading bidi-override / zero-width /
/// control codepoint must NOT smuggle a `javascript:` scheme past
/// the allowlist. Pre-fix the scheme matcher ran on the raw input,
/// so an attacker could prefix `\u{200B}\u{202E}javascript:` and
/// hope the prefix-match logic looked at the right substring after
/// the host browser stripped the leading codepoints. Sanitizing
/// before matching closes the gap.
#[test]
fn url_rejects_javascript_scheme_with_leading_zero_width() {
    assert!(validate_user_url("\u{200B}javascript:alert(1)").is_err());
    assert!(validate_user_url("\u{FEFF}javascript:alert(1)").is_err());
    assert!(validate_user_url("\u{202E}javascript:alert(1)").is_err());
}

/// leading invisible codepoints in
/// front of a legitimate scheme should be sanitized away so the URL
/// validates cleanly — the cleanup is not gating on visual purity,
/// it's gating on what reaches the scheme matcher.
#[test]
fn url_strips_leading_zero_width_for_legitimate_scheme() {
    assert!(validate_user_url("\u{200B}https://example.com/path").is_ok());
    assert!(validate_user_url("\u{FEFF}https://example.com/path").is_ok());
}

/// same hazard for the calendar-URL allowlist.
#[test]
fn calendar_url_rejects_javascript_with_leading_zero_width() {
    assert!(validate_calendar_url("\u{200B}javascript:alert(1)").is_err());
    assert!(validate_calendar_url("\u{202E}javascript:alert(1)").is_err());
}

/// the URL validators now return the sanitized +
/// trimmed canonical form so callers persist that — not the raw
/// input — into storage. Pre-fix the validator returned `()` and
/// every caller bound the raw string to the INSERT, so a URL like
/// `\u{202E}\u{200B}https://example.com` would validate cleanly (the
/// leading bidi-override + zero-width were stripped before scheme
/// matching) yet still write the original bidi/zero-width-prefixed
/// form into `calendar_events.url` / `calendar_subscriptions.url`,
/// leaking the spoof bytes downstream. Round-trip both validators
/// through a representative cocktail of bidi / zero-width / BOM /
/// surrounding-whitespace codepoints and assert the canonical form
/// is the bare URL.
#[test]
fn url_validators_return_sanitized_canonical_form_for_bidi_zero_width() {
    let dirty_user = "  \u{202E}\u{200B}\u{FEFF}https://example.com/path?x=1  ";
    let canonical_user = validate_user_url(dirty_user).expect("should validate");
    assert_eq!(canonical_user, "https://example.com/path?x=1");

    let dirty_calendar = "\u{202E}\u{200B}webcal://example.com/feed.ics\u{FEFF}";
    let canonical_calendar = validate_calendar_url(dirty_calendar).expect("should validate");
    assert_eq!(canonical_calendar, "webcal://example.com/feed.ics");
}

// -- validate_time_format ------------------------------------------

#[test]
fn time_valid() {
    assert!(validate_time_format("09:30").is_ok());
}

#[test]
fn time_midnight() {
    assert!(validate_time_format("00:00").is_ok());
}

#[test]
fn time_end_of_day() {
    assert!(validate_time_format("23:59").is_ok());
}

#[test]
fn time_hour_24() {
    assert!(validate_time_format("24:00").is_err());
}

#[test]
fn time_minute_60() {
    assert!(validate_time_format("12:60").is_err());
}

#[test]
fn time_wrong_format_no_colon() {
    assert!(validate_time_format("0930").is_err());
}

#[test]
fn time_wrong_format_seconds() {
    assert!(validate_time_format("09:30:00").is_err());
}

#[test]
fn time_empty() {
    assert!(validate_time_format("").is_err());
}

#[test]
fn time_single_digit_hour() {
    assert!(validate_time_format("9:30").is_err());
}

#[test]
fn time_letters() {
    assert!(validate_time_format("ab:cd").is_err());
}
