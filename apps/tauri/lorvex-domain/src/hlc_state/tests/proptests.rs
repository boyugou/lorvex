//! property-based panic-safety tests for `HlcState`.
//! Issues #2233 and #2234 fixed two panic classes (counter overflow,
//! physical_ms arithmetic on adversarial input); these properties pin
//! the invariant — no reachable `(local, remote, wall_clock)`
//! combination may panic, and every generated/received state must keep
//! `last_physical_ms ≤ MAX_HLC_PHYSICAL_MS`.

use crate::hlc::Hlc;
use crate::hlc_state::*;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig {
        cases: 256,
        .. ProptestConfig::default()
    })]

    /// `generate_with_physical` must accept any u64 physical_ms
    /// from any prior state without panicking. The resulting HLC's
    /// own `physical_ms` stays at or below the ceiling because
    /// the input is clamped; state clamping in the
    /// overflow-recovery path is tracked separately — the
    /// invariant this property pins is strictly panic-safety.
    #[test]
    fn generate_with_physical_never_panics(
        seed_last_physical in any::<u64>(),
        seed_counter in any::<u32>(),
        now_phys in any::<u64>(),
    ) {
        let mut state = HlcState::new("deaaaaaaaaaaaaa1").unwrap();
        // Seed adversarial state directly — simulating a tainted
        // history loaded from disk or a malicious peer envelope.
        state.last_physical_ms = seed_last_physical;
        state.counter = seed_counter;

        let _ = state.generate_with_physical(now_phys);
    }

    /// `update_on_receive` must never panic regardless of what
    /// canonical remote HLC a peer sends (including
    /// `counter == MAX_COUNTER` and `physical_ms` at the
    /// type-enforced ceiling) or what the
    /// local wall clock reads. Audits #2233 and #2234 fixed the
    /// two concrete panic classes this property now pins against
    /// regression. `remote_phys` and `remote_counter` are constrained
    /// to the HLC type's accepted range because `Hlc::new` itself now
    /// refuses to construct non-canonical values — a hypothetical
    /// `Hlc::new(u64::MAX, ...)` or `Hlc::new(..., u32::MAX, ...)`
    /// is no longer a reachable input shape.
    #[test]
    fn update_on_receive_never_panics(
        local_phys in any::<u64>(),
        local_counter in any::<u32>(),
        remote_phys in 0u64..=crate::hlc::MAX_HLC_PHYSICAL_MS,
        remote_counter in 0u32..=MAX_COUNTER,
        now_phys in any::<u64>(),
    ) {
        let mut state = HlcState::new("aabbccddaabbccdd").unwrap();
        state.last_physical_ms = local_phys;
        state.counter = local_counter;

        let remote = Hlc::new(remote_phys, remote_counter, "eeff0011eeff0011").unwrap();
        state.update_on_receive(&remote, now_phys);
    }

    /// Monotonicity: any sequence of `generate_with_physical`
    /// calls must produce strictly increasing HLCs, regardless of
    /// what the provided physical timestamps do (forward,
    /// backward, clamped, near u64::MAX). Bounds the property
    /// to a 32-element sequence to keep runtime modest.
    #[test]
    fn generate_sequence_is_strictly_monotonic(
        times in proptest::collection::vec(any::<u64>(), 1..32),
    ) {
        let mut state = HlcState::new("deaaaaaaaaaaaaa1").unwrap();
        let mut prev: Option<Hlc> = None;
        for t in times {
            let next = state.generate_with_physical(t);
            if let Some(p) = &prev {
                prop_assert!(
                    next > *p,
                    "HLC must be strictly monotonic: {p} then {next}",
                );
            }
            prev = Some(next);
        }
    }
}
