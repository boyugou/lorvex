use crate::hlc::{Hlc, MAX_HLC_PHYSICAL_MS};
use crate::hlc_state::*;

#[test]
fn receive_updates_state_remote_ahead() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    let _h1 = state.generate_with_physical(1000);

    // Remote is far ahead.
    let remote = Hlc::new(5000, 10, "de0070e100000001").unwrap();
    state.update_on_receive(&remote, 2000);

    // Next generate should be after the remote HLC.
    let h2 = state.generate_with_physical(3000);
    assert!(h2 > remote, "local HLC after receive should exceed remote");
}

#[test]
fn receive_updates_state_local_ahead() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    let _h1 = state.generate_with_physical(5000);

    // Remote is behind.
    let remote = Hlc::new(1000, 0, "de0070e100000001").unwrap();
    state.update_on_receive(&remote, 3000);

    let h2 = state.generate_with_physical(4000);
    assert_eq!(
        h2.physical_ms(),
        5000,
        "local physical_ms should remain at 5000"
    );
}

#[test]
fn receive_updates_state_same_physical() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    let _h1 = state.generate_with_physical(1000);
    // counter is now 0 for physical_ms 1000

    let remote = Hlc::new(1000, 5, "de0070e100000001").unwrap();
    state.update_on_receive(&remote, 1000);

    // All three timestamps equal: counter should be max(0, 5) + 1 = 6
    assert_eq!(state.counter, 6);
    assert_eq!(state.last_physical_ms, 1000);
}

#[test]
fn receive_wall_clock_ahead_resets_counter() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    let _h1 = state.generate_with_physical(1000);

    let remote = Hlc::new(2000, 5, "de0070e100000001").unwrap();
    // Wall clock at 5000 — ahead of both local and remote.
    state.update_on_receive(&remote, 5000);

    assert_eq!(state.last_physical_ms, 5000);
    assert_eq!(state.counter, 0, "wall clock ahead should reset counter");
}

/// the type now guarantees `physical_ms <=
/// MAX_HLC_PHYSICAL_MS` at every constructor (`Hlc::new` and
/// `Hlc::parse` both reject), so the apply-side clamp that used
/// to live in `update_on_receive` is no longer required. This
/// test pins the new contract: a remote HLC at the cap is
/// applied as-is, and `Hlc::new(u64::MAX, ...)` is refused at
/// construction time so an in-memory poison value cannot reach
/// the apply boundary in the first place.
#[test]
fn update_on_receive_at_ceiling_holds_state_at_ceiling() {
    let mut state = HlcState::new("10ca100100000001").unwrap();
    state.last_physical_ms = 1000;
    let remote = Hlc::new(MAX_HLC_PHYSICAL_MS, 0, "de0070e100000001").unwrap();
    state.update_on_receive(&remote, 2000);
    assert_eq!(
        state.last_physical_ms, MAX_HLC_PHYSICAL_MS,
        "remote at the cap must apply at the cap, not above it",
    );
}
