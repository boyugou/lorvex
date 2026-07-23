use crate::hlc::*;

#[test]
fn parse_roundtrip() {
    let original = Hlc::new(1_711_234_567_890, 42, "deadbeefdeadbeef").unwrap();
    let serialized = original.to_string();
    let parsed = Hlc::parse(&serialized).unwrap();
    assert_eq!(original, parsed);
}

#[test]
fn parse_zero_padded_roundtrip() {
    let original = Hlc::new(100, 1, "aabbccddaabbccdd").unwrap();
    let serialized = original.to_string();
    let parsed = Hlc::parse(&serialized).unwrap();
    assert_eq!(original, parsed);
}

#[test]
fn parse_normalizes_uppercase_device_suffix_to_lowercase() {
    // A peer sending uppercase hex (DB restored from a
    // capitalized backup, provider field case-fold) must parse
    // to a lowercase HLC so equality with a locally-generated
    // HLC works.
    let upper = Hlc::parse("0000000001000_0000_ABCD1234ABCD1234").expect("valid format");
    let lower = Hlc::parse("0000000001000_0000_abcd1234abcd1234").expect("valid format");
    assert_eq!(
        upper, lower,
        "case-different but otherwise-identical HLCs must compare equal"
    );
    assert_eq!(upper.device_suffix(), "abcd1234abcd1234");
}

#[test]
fn parse_invalid_format_no_underscores() {
    assert!(matches!(
        Hlc::parse("invalid"),
        Err(HlcParseError::InvalidFormat(_))
    ));
}

#[test]
fn parse_invalid_format_one_underscore() {
    assert!(matches!(
        Hlc::parse("123_456"),
        Err(HlcParseError::InvalidFormat(_))
    ));
}

#[test]
fn parse_invalid_physical_ms() {
    assert!(matches!(
        Hlc::parse("notanumber_0000_abcd1234abcd1234"),
        Err(HlcParseError::InvalidPhysicalMs(_))
    ));
}

#[test]
fn parse_invalid_counter() {
    assert!(matches!(
        Hlc::parse("1711234567890_bad_abcd1234abcd1234"),
        Err(HlcParseError::InvalidCounter(_))
    ));
}

#[test]
fn parse_rejects_counter_past_canonical_ceiling() {
    assert!(
        Hlc::parse("1711234567890_10000_abcd1234abcd1234").is_err(),
        "HLC counters must remain in the canonical 0000-9999 range",
    );
}

#[test]
fn new_rejects_counter_past_canonical_ceiling() {
    assert!(
        Hlc::new(1_711_234_567_890, 10_000, "abcd1234abcd1234").is_err(),
        "Hlc::new must not construct a value whose Display form widens the counter segment",
    );
}

#[test]
fn parse_empty_device_suffix() {
    assert!(matches!(
        Hlc::parse("1711234567890_0000_"),
        Err(HlcParseError::EmptyDeviceSuffix)
    ));
}
