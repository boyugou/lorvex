use crate::hlc::Hlc;
use crate::hlc_state::*;

#[test]
fn hlc_new_rejects_physical_ms_past_ceiling() {
    // the apply boundary used to clamp a
    // hypothetical `Hlc::new(u64::MAX, ...)`. The type itself now
    // refuses to construct that value, so the clamp is gone and
    // this test pins the gate at the constructor instead.
    assert!(matches!(
        Hlc::new(u64::MAX, 0, "de0070e100000001"),
        Err(crate::hlc::HlcParseError::PhysicalMsOutOfRange(_)),
    ));
}

#[test]
fn device_suffix_propagated() {
    let mut state = HlcState::new("cafe1234cafe1234").unwrap();
    let hlc = state.generate_with_physical(1000);
    assert_eq!(hlc.device_suffix(), "cafe1234cafe1234");
}

/// `HlcState::new` rejects a non-canonical
/// suffix at construction time so the lazy `Hlc::new` inside
/// `generate_with_physical` can stay infallible.
#[test]
fn new_rejects_invalid_device_suffix() {
    assert!(HlcState::new("short").is_err());
    assert!(HlcState::new("ghijklmnopqrstuv").is_err());
    // Canonical shape constructs cleanly.
    HlcState::new("0123456789abcdef").unwrap();
}
