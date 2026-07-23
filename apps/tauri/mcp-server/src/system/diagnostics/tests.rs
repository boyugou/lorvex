use super::{
    redact_diagnostic_text, sanitize_diagnostic_text, truncate_compact_text,
    truncate_diagnostic_text,
};

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_truncates_ascii_with_ellipsis() {
    let value = "alpha   beta   gamma";
    assert_eq!(truncate_diagnostic_text(value, 10), "alpha beta...");
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_handles_multibyte_without_panicking() {
    let value = "你好世界朋友";
    assert_eq!(truncate_diagnostic_text(value, 3), "你好世...");
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_zero_length_returns_empty() {
    assert_eq!(truncate_diagnostic_text("hello", 0), "");
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_compact_text_collapses_whitespace_before_truncation() {
    let value = "alpha   beta   gamma";
    assert_eq!(truncate_compact_text(value, 10), "alpha beta...");
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_strips_ansi_escape_sequences() {
    // OSC 8 hyperlink + CSI cursor moves must not
    // survive into terminal-based MCP client output.
    let osc8 = "Meeting\x1b]8;;file:///etc/passwd\x1b\\click\x1b]8;;\x1b\\";
    let out = truncate_diagnostic_text(osc8, 200);
    assert!(!out.contains('\x1b'), "ESC must be stripped: {out:?}");
    assert!(out.contains("Meeting"), "visible text kept: {out:?}");
    assert!(out.contains("click"), "visible text kept: {out:?}");
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_strips_c0_and_c1_control_chars() {
    // C0 (0x00..0x1F) and DEL (0x7F) and C1 (0x80..0x9F) all
    // stripped — TAB/LF/CR allowed through so split_whitespace
    // still collapses them.
    let input = "alpha\x1b[31mred\x1b[0m\x7f\u{0080}beta";
    let out = truncate_diagnostic_text(input, 200);
    assert!(!out.contains('\x1b'));
    assert!(!out.contains('\x7f'));
    assert!(!out.contains('\u{0080}'));
    assert!(out.contains("alpha"));
    assert!(out.contains("red"));
    assert!(out.contains("beta"));
}

#[test]
#[serial_test::serial(hlc)]
fn truncate_diagnostic_text_keeps_tab_lf_cr_as_whitespace() {
    // TAB/LF/CR must be treated as whitespace (collapsed), not
    // stripped — a user-pasted multi-line error message should
    // render as a single space-separated line.
    let out = truncate_diagnostic_text("line1\nline2\tline3\r\nline4", 200);
    assert_eq!(out, "line1 line2 line3 line4");
}

#[test]
#[serial_test::serial(hlc)]
fn redact_diagnostic_text_redacts_bearer_tokens_split_by_whitespace() {
    let input = "Authorization: Bearer super-secret-token";
    let output = redact_diagnostic_text(input);
    assert_eq!(output, "Authorization: Bearer [REDACTED]");
    assert!(!output.contains("super-secret-token"));
}

#[test]
#[serial_test::serial(hlc)]
fn sanitize_diagnostic_text_redacts_inline_bearer_tokens() {
    let input = Some("authorization:bearer sk_live_12345");
    let output = sanitize_diagnostic_text(input, 280, true).expect("sanitized");
    assert_eq!(output, "Authorization: Bearer [REDACTED]");
    assert!(!output.contains("sk_live_12345"));
}

#[test]
#[serial_test::serial(hlc)]
fn redact_diagnostic_text_redacts_json_style_secret_fields() {
    let input = "{\"api_key\":\"sk_live_abc123\"}";
    let output = redact_diagnostic_text(input);
    assert_eq!(output, "[REDACTED_JSON_SECRET]");
    assert!(!output.contains("sk_live_abc123"));
}
