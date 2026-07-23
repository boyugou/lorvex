use crate::hlc::{Hlc, MAX_HLC_PHYSICAL_MS};
use crate::hlc_state::*;

#[test]
fn counter_overflow_recovers_by_advancing_physical() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    state.last_physical_ms = 1000;
    state.counter = MAX_COUNTER;

    // Counter would exceed MAX_COUNTER — should recover by advancing physical_ms.
    let hlc = state.generate_with_physical(1000);
    assert_eq!(
        hlc.physical_ms(),
        1001,
        "physical_ms should advance by 1ms on overflow"
    );
    assert_eq!(
        hlc.counter(),
        0,
        "counter should reset to 0 after overflow recovery"
    );
    assert_eq!(state.last_physical_ms, 1001);
    assert_eq!(state.counter, 0);
}

#[test]
fn counter_overflow_on_receive_recovers() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    state.last_physical_ms = 1000;
    state.counter = MAX_COUNTER;

    let remote = Hlc::new(1000, MAX_COUNTER, "de0070e100000001").unwrap();
    // All same physical_ms: would set counter to max(MAX_COUNTER, MAX_COUNTER) + 1
    // Should recover by advancing physical_ms instead of panicking.
    state.update_on_receive(&remote, 1000);
    assert_eq!(
        state.last_physical_ms, 1001,
        "physical_ms should advance by 1ms on overflow"
    );
    assert_eq!(
        state.counter, 0,
        "counter should reset to 0 after overflow recovery"
    );
}

#[test]
fn counter_overflow_on_receive_clamps_to_ceiling() {
    // the apply-side overflow recovery must mirror
    // the generate-side clamp. Without this, a remote envelope
    // received at exactly the ceiling with both counters
    // saturated would push `last_physical_ms` to the ceiling+1,
    // emitting a 14-digit physical half that lex-sorts above
    // every legitimate 13-digit entry forever.
    let mut state = HlcState::new("10ca100100000001").unwrap();
    state.last_physical_ms = MAX_HLC_PHYSICAL_MS;
    state.counter = MAX_COUNTER;
    let remote = Hlc::new(MAX_HLC_PHYSICAL_MS, MAX_COUNTER, "de0070e100000001").unwrap();
    state.update_on_receive(&remote, MAX_HLC_PHYSICAL_MS);
    assert_eq!(
        state.last_physical_ms, MAX_HLC_PHYSICAL_MS,
        "ceiling clamp must hold last_physical_ms at the cap, not push to cap+1",
    );
    assert_eq!(
        state.counter, 0,
        "overflow recovery still resets counter to 0",
    );
}

#[test]
fn receive_saturating_on_max_u32_remote_counter() {
    // `update_on_receive` is typed over `Hlc`, so a malformed peer
    // envelope with counter == u32::MAX can no longer reach this
    // method. The parser/constructor reject it at the HLC boundary
    // before HlcState has to reason about it.
    assert!(
        Hlc::new(1000, u32::MAX, "de0070e100000001").is_err(),
        "non-canonical remote counters must be rejected before HlcState::update_on_receive",
    );
}

#[test]
fn generate_saturating_on_max_u32_local_counter() {
    // Same concern as above but on the local-generate path: if
    // the counter was already at u32::MAX (e.g. post-seed from a
    // tainted history), the next generate must not panic.
    let mut state = HlcState::new("10ca100100000001").unwrap();
    state.last_physical_ms = 1000;
    state.counter = u32::MAX;

    // Same ms → would try counter += 1 → saturating_add to u32::MAX
    // → > MAX_COUNTER → roll physical forward, reset counter.
    let hlc = state.generate_with_physical(1000);
    assert!(hlc.physical_ms() >= 1001);
    assert_eq!(hlc.counter(), 0);
}
