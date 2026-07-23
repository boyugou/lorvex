use crate::hlc::*;

/// a peer sending `physical_ms = u64::MAX` (or any
/// value past the 14-digit ceiling) must be rejected at parse time.
/// Accepting it would produce a 20-digit version that lex-sorts
/// above every legitimate HLC forever, and LWW would promote the
/// poisoned value cluster-wide.
#[test]
fn parse_rejects_physical_ms_past_ceiling() {
    let poison = format!("{}_0000_abcd1234abcd1234", u64::MAX);
    assert!(matches!(
        Hlc::parse(&poison),
        Err(HlcParseError::PhysicalMsOutOfRange(_)),
    ));
}

/// `Hlc::new` itself must reject any
/// `physical_ms > MAX_HLC_PHYSICAL_MS`. Pre-fix only `Hlc::parse`
/// enforced the ceiling, so a crafted in-memory value built via
/// `Hlc::new(u64::MAX, ...)` poisoned LWW for the lifetime of the
/// cluster — every legitimate 13-digit HLC forever lex-sorted
/// below it.
#[test]
fn new_rejects_physical_ms_past_ceiling() {
    match Hlc::new(u64::MAX, 0, "abcd1234abcd1234") {
        Err(HlcParseError::PhysicalMsOutOfRange(ms)) => assert_eq!(ms, u64::MAX),
        other => panic!("expected PhysicalMsOutOfRange, got {other:?}"),
    }
}

#[test]
fn new_rejects_physical_ms_one_past_max() {
    match Hlc::new(MAX_HLC_PHYSICAL_MS + 1, 0, "abcd1234abcd1234") {
        Err(HlcParseError::PhysicalMsOutOfRange(ms)) => {
            assert_eq!(ms, MAX_HLC_PHYSICAL_MS + 1);
        }
        other => panic!("expected PhysicalMsOutOfRange, got {other:?}"),
    }
}

#[test]
fn new_accepts_physical_ms_at_max() {
    Hlc::new(MAX_HLC_PHYSICAL_MS, 0, "abcd1234abcd1234").expect("max physical_ms must construct");
}

#[test]
fn parse_rejects_physical_ms_one_past_max() {
    let poison = format!("{}_0000_abcd1234abcd1234", MAX_HLC_PHYSICAL_MS + 1);
    assert!(matches!(
        Hlc::parse(&poison),
        Err(HlcParseError::PhysicalMsOutOfRange(_)),
    ));
}

#[test]
fn parse_accepts_physical_ms_at_max() {
    let at_max = format!("{MAX_HLC_PHYSICAL_MS}_0000_abcd1234abcd1234");
    Hlc::parse(&at_max).expect("max value must parse");
}
