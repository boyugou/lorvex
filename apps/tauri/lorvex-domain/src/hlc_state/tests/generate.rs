use crate::hlc::MAX_HLC_PHYSICAL_MS;
use crate::hlc_state::*;

#[test]
fn advance_clock_resets_counter() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let h1 = state.generate_with_physical(1000);
    assert_eq!(h1.physical_ms(), 1000);
    assert_eq!(h1.counter(), 0);

    let h2 = state.generate_with_physical(2000);
    assert_eq!(h2.physical_ms(), 2000);
    assert_eq!(h2.counter(), 0);
}

#[test]
fn same_ms_increments_counter() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let h1 = state.generate_with_physical(1000);
    assert_eq!(h1.counter(), 0);

    let h2 = state.generate_with_physical(1000);
    assert_eq!(h2.physical_ms(), 1000);
    assert_eq!(h2.counter(), 1);

    let h3 = state.generate_with_physical(1000);
    assert_eq!(h3.counter(), 2);
}

#[test]
fn backward_clock_increments_counter() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let h1 = state.generate_with_physical(5000);
    assert_eq!(h1.physical_ms(), 5000);
    assert_eq!(h1.counter(), 0);

    // Clock goes backward.
    let h2 = state.generate_with_physical(3000);
    assert_eq!(h2.physical_ms(), 5000, "physical_ms should stay at max");
    assert_eq!(h2.counter(), 1, "counter should increment");
}

#[test]
fn monotonically_increasing() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let mut prev = state.generate_with_physical(100);

    for ms in [100, 100, 200, 200, 150, 300, 300, 300] {
        let next = state.generate_with_physical(ms);
        assert!(
            next > prev,
            "HLC must be strictly increasing: {prev} should be < {next}"
        );
        prev = next;
    }
}

#[test]
fn generate_uses_wall_clock() {
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let h1 = state.generate();
    let h2 = state.generate();
    assert!(
        h2 > h1,
        "wall-clock generates should be monotonically increasing"
    );
}

#[test]
fn generate_clamps_far_future_physical_ms_to_ceiling() {
    // a clock-skewed local wall clock (future-dated NTP
    // response, mis-set system time, restored-from-snapshot VM) must
    // not propagate a poisoned physical_ms that lex-sorts above every
    // legitimate HLC forever.
    let mut state = HlcState::new("dec0000100000001").unwrap();
    let hlc = state.generate_with_physical(u64::MAX);
    assert_eq!(
        hlc.physical_ms(),
        MAX_HLC_PHYSICAL_MS,
        "generate must clamp far-future physical_ms to the 14-digit ceiling",
    );
}
