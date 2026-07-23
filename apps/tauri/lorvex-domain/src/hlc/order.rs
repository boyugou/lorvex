//! `Ord` / `PartialOrd` impls for [`Hlc`] — lexicographic order over
//! `(physical_ms, counter, device_suffix)` matching the canonical
//! display string's byte order.

use super::core::Hlc;
use super::parse_error::HLC_DEVICE_SUFFIX_HEX_LEN;

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        // assert the device-suffix length invariant
        // before letting `String::cmp` arbitrate the third tier of
        // ordering. Both `Hlc::new` and `Hlc::parse` reject any
        // suffix that is not exactly `HLC_DEVICE_SUFFIX_HEX_LEN`
        // lowercase hex characters (issue #2973-H5), so every Hlc
        // value reachable through the public API satisfies this
        // invariant. The assertion catches a regression in any
        // future internal constructor that bypasses parsing — a
        // 1-char or 31-char suffix would silently win or lose
        // against a canonical 16-char peer in raw lex order, which
        // is exactly the cross-device LWW poisoning the parser
        // contract was tightened to prevent. Debug-only; release
        // builds compile this away (the parser/`new` checks already
        // hold the invariant in production).
        debug_assert_eq!(
            self.device_suffix.len(),
            HLC_DEVICE_SUFFIX_HEX_LEN,
            "Hlc::cmp: device_suffix '{}' must be exactly {HLC_DEVICE_SUFFIX_HEX_LEN} hex chars",
            self.device_suffix
        );
        debug_assert_eq!(
            other.device_suffix.len(),
            HLC_DEVICE_SUFFIX_HEX_LEN,
            "Hlc::cmp: device_suffix '{}' must be exactly {HLC_DEVICE_SUFFIX_HEX_LEN} hex chars",
            other.device_suffix
        );
        self.physical_ms
            .cmp(&other.physical_ms)
            .then_with(|| self.counter.cmp(&other.counter))
            .then_with(|| self.device_suffix.cmp(&other.device_suffix))
    }
}

impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
