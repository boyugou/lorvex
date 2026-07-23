//! property-based panic-safety tests for `Hlc::parse` and
//! the `Hlc::new` / `Display` round-trip. Any adversarial string must
//! return `Result` rather than panic; any in-bounds `(physical_ms,
//! counter, suffix)` triple must round-trip through `Display` → `parse`.

use crate::hlc::*;
use proptest::prelude::*;

proptest! {
    // Default case count is ample — parse is O(n) on short strings.
    #![proptest_config(ProptestConfig {
        cases: 256,
        .. ProptestConfig::default()
    })]

    /// Any unicode string of length ≤ 64 must be handled by
    /// `Hlc::parse` without panicking. This covers malformed
    /// envelopes, truncation, unicode injection, and empty input.
    #[test]
    fn parse_never_panics(s in "\\PC{0,64}") {
        let _ = Hlc::parse(&s);
    }

    /// ASCII-only adversarial inputs targeting the three segments:
    /// digits, underscores, alphanumerics. Increases coverage of
    /// near-valid inputs that survive the `splitn` but fail
    /// integer parsing or the physical_ms ceiling check.
    #[test]
    fn parse_never_panics_ascii(s in "[0-9a-zA-Z_]{0,32}") {
        let _ = Hlc::parse(&s);
    }

    /// Any in-range physical_ms and canonical counter with a canonical-shape
    /// suffix (exactly 16 lowercase hex chars per issue #2973-H5)
    /// must construct via `Hlc::new`, stringify via `Display`, and
    /// round-trip through `parse`. `Hlc::new` now
    /// itself enforces the `MAX_HLC_PHYSICAL_MS` ceiling, so the
    /// generator constrains physical_ms to the accepted range and
    /// the round-trip is unconditional.
    #[test]
    fn new_display_parse_roundtrip(
        physical_ms in 0u64..=MAX_HLC_PHYSICAL_MS,
        counter in 0u32..=MAX_COUNTER,
        suffix in "[0-9a-f]{16}",
    ) {
        let hlc = Hlc::new(physical_ms, counter, &suffix)
            .expect("canonical-shape suffix and in-range physical_ms must construct");
        let s = hlc.to_string();
        let parsed = Hlc::parse(&s).expect("Display output must round-trip");
        prop_assert_eq!(parsed.physical_ms(), physical_ms);
        prop_assert_eq!(parsed.counter(), counter);
        prop_assert_eq!(parsed.device_suffix(), suffix.to_ascii_lowercase());
    }

    /// `Hlc::new` rejects any `physical_ms` past
    /// `MAX_HLC_PHYSICAL_MS` regardless of how the suffix and
    /// counter look. Pre-fix only the parser enforced the
    /// ceiling, so an in-memory poison value could ride around
    /// the type system.
    #[test]
    fn new_rejects_physical_ms_past_ceiling_proptest(
        physical_ms in (MAX_HLC_PHYSICAL_MS + 1)..=u64::MAX,
        counter in 0u32..=MAX_COUNTER,
        suffix in "[0-9a-f]{16}",
    ) {
        prop_assert!(matches!(
            Hlc::new(physical_ms, counter, &suffix),
            Err(HlcParseError::PhysicalMsOutOfRange(_)),
        ));
    }

    /// a non-canonical suffix (wrong length OR
    /// non-hex character) must be rejected by `Hlc::new` rather
    /// than constructing a malformed value.
    /// physical_ms is constrained to the accepted range so the
    /// failure cleanly attributes to suffix shape rather than
    /// being shadowed by `PhysicalMsOutOfRange`.
    #[test]
    fn new_rejects_noncanonical_suffix(
        physical_ms in 0u64..=MAX_HLC_PHYSICAL_MS,
        counter in 0u32..=MAX_COUNTER,
        suffix in "[0-9a-zA-Z_]{0,64}"
            .prop_filter("must be non-canonical",
                |s: &String| {
                    s.len() != HLC_DEVICE_SUFFIX_HEX_LEN
                        || !s.chars().all(|c| c.is_ascii_hexdigit())
                }),
    ) {
        prop_assert!(Hlc::new(physical_ms, counter, &suffix).is_err());
    }

    /// Any counter outside the four-digit canonical range must be
    /// rejected even when the physical_ms and suffix are otherwise
    /// valid.
    #[test]
    fn new_rejects_counter_past_ceiling_proptest(
        physical_ms in 0u64..=MAX_HLC_PHYSICAL_MS,
        counter in (MAX_COUNTER + 1)..=u32::MAX,
        suffix in "[0-9a-f]{16}",
    ) {
        prop_assert!(matches!(
            Hlc::new(physical_ms, counter, &suffix),
            Err(HlcParseError::CounterOutOfRange(_)),
        ));
    }
}
