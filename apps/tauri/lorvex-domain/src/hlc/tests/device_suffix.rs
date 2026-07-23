use crate::hlc::*;

#[test]
fn new_normalizes_device_suffix_to_lowercase() {
    // mixed-case hex suffix must be canonicalized at
    // construction time so the type invariant "always lowercase"
    // holds regardless of caller.
    let hlc = Hlc::new(1000, 0, "DEADBEEFDEADBEEF").unwrap();
    assert_eq!(hlc.device_suffix(), "deadbeefdeadbeef");
    assert_eq!(hlc.to_string(), "0000000001000_0000_deadbeefdeadbeef");
}

/// `Hlc::new` rejects a suffix shorter than
/// [`HLC_DEVICE_SUFFIX_HEX_LEN`] with a typed
/// `InvalidDeviceSuffixLength` error. Pre-fix the constructor
/// silently accepted any non-empty suffix.
#[test]
fn new_rejects_short_device_suffix() {
    match Hlc::new(1000, 0, "deadbeef") {
        Err(HlcParseError::InvalidDeviceSuffixLength {
            expected, actual, ..
        }) => {
            assert_eq!(expected, HLC_DEVICE_SUFFIX_HEX_LEN);
            assert_eq!(actual, 8);
        }
        other => panic!("expected InvalidDeviceSuffixLength, got {other:?}"),
    }
}

/// `Hlc::new` rejects a suffix that contains
/// non-hex characters even at the correct length.
#[test]
fn new_rejects_non_hex_device_suffix() {
    match Hlc::new(1000, 0, "ghijklmnopqrstuv") {
        Err(HlcParseError::InvalidDeviceSuffixCharset(s)) => {
            assert_eq!(s, "ghijklmnopqrstuv");
        }
        other => panic!("expected InvalidDeviceSuffixCharset, got {other:?}"),
    }
}

/// `Hlc::parse` rejects an oversize suffix even
/// when every other segment parses cleanly.
#[test]
fn parse_rejects_overlong_device_suffix() {
    let too_long = "1711234567890_0000_abcdef0123456789ff";
    match Hlc::parse(too_long) {
        Err(HlcParseError::InvalidDeviceSuffixLength {
            expected, actual, ..
        }) => {
            assert_eq!(expected, HLC_DEVICE_SUFFIX_HEX_LEN);
            assert_eq!(actual, 18);
        }
        other => panic!("expected InvalidDeviceSuffixLength, got {other:?}"),
    }
}

/// `Hlc::parse` rejects a non-hex suffix at the
/// canonical length.
#[test]
fn parse_rejects_non_hex_device_suffix() {
    let bad_alphabet = "1711234567890_0000_zzzzzzzzzzzzzzzz";
    match Hlc::parse(bad_alphabet) {
        Err(HlcParseError::InvalidDeviceSuffixCharset(s)) => {
            assert_eq!(s, "zzzzzzzzzzzzzzzz");
        }
        other => panic!("expected InvalidDeviceSuffixCharset, got {other:?}"),
    }
}

/// pre-fix this test asserted that an underscore-
/// bearing suffix round-tripped through `splitn(3, '_')`. The
/// stronger validator now refuses such inputs at the type
/// boundary because the canonical suffix is exactly 16 lowercase
/// hex chars — anything else is corruption that must surface as a
/// typed parse error rather than silently riding through LWW.
#[test]
fn device_suffix_with_underscores_is_rejected() {
    // Construction refuses a length-mismatched, non-hex suffix.
    let new_err =
        Hlc::new(1000, 0, "ab_cd").expect_err("underscore-bearing suffix must be rejected");
    match new_err {
        HlcParseError::InvalidDeviceSuffixLength { actual, .. } => {
            assert_eq!(actual, 5);
        }
        other => panic!("expected InvalidDeviceSuffixLength, got {other:?}"),
    }

    // Parse refuses the same shape even when handed a literal
    // string that the previous splitn(3, '_') tolerance would
    // have happily accepted.
    let parse_err = Hlc::parse("0000000001000_0000_ab_cd")
        .expect_err("underscore-bearing suffix must be rejected by parse");
    // The third segment after splitn(3, '_') is "ab_cd" — five
    // chars, fails the length check before alphabet.
    match parse_err {
        HlcParseError::InvalidDeviceSuffixLength { actual, .. } => {
            assert_eq!(actual, 5);
        }
        other => panic!("expected InvalidDeviceSuffixLength, got {other:?}"),
    }
}
