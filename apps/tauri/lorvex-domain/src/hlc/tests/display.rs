use crate::hlc::*;

#[test]
fn display_format() {
    let hlc = Hlc::new(1_711_234_567_890, 3, "a1b2c3d4a1b2c3d4").unwrap();
    assert_eq!(hlc.to_string(), "1711234567890_0003_a1b2c3d4a1b2c3d4");
}

#[test]
fn display_zero_pads_physical_ms() {
    let hlc = Hlc::new(123, 0, "abcd1234abcd1234").unwrap();
    assert_eq!(hlc.to_string(), "0000000000123_0000_abcd1234abcd1234");
}

#[test]
fn display_zero_pads_counter() {
    let hlc = Hlc::new(1_711_234_567_890, 0, "abcd1234abcd1234").unwrap();
    assert_eq!(hlc.to_string(), "1711234567890_0000_abcd1234abcd1234");
}

/// the ceiling must be exactly 13 digits so the
/// canonical `{:013}` Display format renders it without zero-padding
/// inflating it to 14+ characters — otherwise any HLC at the cap
/// would lex above every legitimate 13-digit HLC and silently break
/// LWW's `(physical_ms, counter, device_suffix)` ordering.
#[test]
fn display_at_max_renders_exactly_thirteen_digit_physical_ms() {
    let hlc = Hlc::new(MAX_HLC_PHYSICAL_MS, 0, "abcd1234abcd1234").unwrap();
    let s = hlc.to_string();
    let physical_segment = s.split('_').next().expect("at least one segment");
    assert_eq!(
        physical_segment.len(),
        13,
        "physical_ms segment at the cap must be exactly 13 chars, got {physical_segment:?}",
    );
    assert_eq!(s, "9999999999999_0000_abcd1234abcd1234");
}
