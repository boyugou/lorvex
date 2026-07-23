use super::*;

#[test]
fn truncate_utf8_respects_char_boundaries() {
    // 8190 ASCII bytes followed by a 3-byte CJK char would exceed
    // the 8192 byte cap if naively sliced; the truncator must
    // back off to the previous char boundary.
    let value = format!("{}界", "a".repeat(8_190));
    let out = truncate_utf8_to_max_bytes(&value, 8192);
    assert_eq!(out.len(), 8_190);
    assert!(!out.ends_with('界'));
    assert!(std::str::from_utf8(out.as_bytes()).is_ok());
}

#[test]
fn truncate_short_value_unchanged() {
    let out = truncate_utf8_to_max_bytes("hello", 100);
    assert_eq!(out, "hello");
}

#[test]
fn normalize_error_level_canonicalizes() {
    assert_eq!(normalize_error_level(None), "error");
    assert_eq!(normalize_error_level(Some("DEBUG")), "debug");
    assert_eq!(normalize_error_level(Some("Warning")), "warn");
    assert_eq!(normalize_error_level(Some("warn")), "warn");
    assert_eq!(normalize_error_level(Some("nonsense")), "error");
    assert_eq!(normalize_error_level(Some("  info  ")), "info");
}
