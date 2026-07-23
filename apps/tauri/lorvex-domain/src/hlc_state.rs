//! Mutable HLC generator state.
//!
//! Maintains the monotonicity invariant: every generated HLC is strictly
//! greater than the previous, even if the physical clock goes backward.
//!
//! # Key invariant
//!
//! `generate_with_physical` always sets `last_physical_ms = max(last_physical_ms,
//! now)` before branching on whether to increment the counter or reset it.

use crate::hlc::{Hlc, HlcParseError, MAX_HLC_PHYSICAL_MS};

/// Maximum counter value. On overflow (>9999 writes in the same ms on one
/// device), recovery advances physical_ms by 1 and resets counter to 0.
pub use crate::hlc::MAX_COUNTER;

/// Mutable state for HLC generation on a single device.
///
/// Fields are `pub(crate)` so external callers must go through the
/// `last_physical_ms()` / `counter()` / `device_suffix()` accessors
/// instead of poking the fields directly.
/// at the bottom of `hlc.rs` already documented that direct field
/// mutation would corrupt the LWW invariant; tightening visibility
/// makes the rule structurally enforceable rather than just
/// documented. The in-crate proptest / overflow tests can still seed
/// adversarial state because they live inside `lorvex-domain`.
#[derive(Debug)]
pub struct HlcState {
    pub(crate) last_physical_ms: u64,
    pub(crate) counter: u32,
    pub(crate) device_suffix: String,
}

impl HlcState {
    /// Read-only access to the current state for diagnostic /
    /// assertion sites (e.g. `lorvex-store`'s seeding tests).
    #[inline]
    pub const fn last_physical_ms(&self) -> u64 {
        self.last_physical_ms
    }

    /// Read-only access to the in-millisecond counter.
    #[inline]
    pub const fn counter(&self) -> u32 {
        self.counter
    }

    /// Read-only access to the canonical device suffix.
    #[inline]
    pub fn device_suffix(&self) -> &str {
        &self.device_suffix
    }

    /// Create a new HLC generator state for the given device.
    ///
    /// the suffix is validated up front by minting a
    /// throwaway `Hlc` so an invalid shape (wrong length / non-hex
    /// alphabet) surfaces immediately rather than at the first
    /// `generate_with_physical` call. The constructed value also
    /// canonicalizes the suffix to lowercase so subsequent
    /// `Hlc::new` calls inside `generate_with_physical` stay
    /// infallible.
    pub fn new(device_suffix: impl Into<String>) -> Result<Self, HlcParseError> {
        let suffix_str = device_suffix.into();
        // Validation lives in `Hlc::new`; reuse it so a single source
        // of truth governs what counts as a canonical suffix.
        let canon = Hlc::new(0, 0, &suffix_str)?;
        Ok(Self {
            last_physical_ms: 0,
            counter: 0,
            device_suffix: canon.device_suffix().to_string(),
        })
    }

    /// Generate an HLC using the provided physical timestamp (milliseconds).
    ///
    /// This is the core generation function. Use `generate()` for wall-clock
    /// time, or call this directly with a known timestamp for deterministic
    /// testing.
    pub fn generate_with_physical(&mut self, physical_ms: u64) -> Hlc {
        // clamp to the 13-digit lex-sortable ceiling before
        // it propagates. A future-dated NTP response or deliberately
        // mis-set local clock could otherwise emit a version that lex-
        // sorts above every legitimate entry forever, and LWW would
        // promote that poisoned value cluster-wide. Also sanitize the
        // stored `last_physical_ms` in case a tainted on-disk history
        // (or test harness) seeded it past the ceiling — `Hlc::new`
        // would otherwise panic at the bottom of this function.
        let physical_ms = physical_ms.min(MAX_HLC_PHYSICAL_MS);
        self.last_physical_ms = self.last_physical_ms.min(MAX_HLC_PHYSICAL_MS);
        let new_physical = std::cmp::max(self.last_physical_ms, physical_ms);

        if new_physical == self.last_physical_ms {
            // Same or backward clock: increment counter.
            // saturating_add protects against u32 overflow if a prior
            // malicious / malformed peer envelope forced the counter
            // to u32::MAX. The standard MAX_COUNTER guard below will
            // roll the clock forward immediately after.
            self.counter = self.counter.saturating_add(1);
        } else {
            // Clock advanced: reset counter.
            self.counter = 0;
        }

        self.last_physical_ms = new_physical;

        // Counter overflow recovery: advance physical time by 1ms, reset counter.
        // This is the standard HLC recovery for degenerate scenarios with >9999
        // writes in the same millisecond (e.g. batch import tight loops).
        //
        // clamp the post-bump physical to `MAX_HLC_PHYSICAL_MS`.
        // Without this clamp, the pathological case `last_physical_ms ==
        // MAX_HLC_PHYSICAL_MS && counter == MAX_COUNTER` bumps the stored ms
        // to `MAX_HLC_PHYSICAL_MS + 1`, escaping the 13-digit lex-sort
        // ceiling by one millisecond and breaking comparison against any
        // HLC written by a pre-overflow device. Saturating at the ceiling
        // keeps the same millisecond and just holds the counter at 0 —
        // liveness preserved, lex-sort invariant preserved.
        //
        // the race-audit explicitly verified
        // this branch as informational/safe — the saturating-add chain
        // (`#2233` on counter, `#2741` on physical_ms) plus the ceiling
        // clamp here means there is no path that emits an HLC larger
        // than the lex-sort ceiling, regardless of how malformed an
        // inbound peer envelope is or how tight a local loop pushes the
        // counter. The proptest below (`generate_saturating_on_max_u32_local_counter`)
        // pins the contract; do not weaken either guard without
        // updating that test.
        if self.counter > MAX_COUNTER {
            self.last_physical_ms = self
                .last_physical_ms
                .saturating_add(1)
                .min(MAX_HLC_PHYSICAL_MS);
            self.counter = 0;
        }

        // The suffix invariant is enforced at `HlcState::new`; if a
        // caller mutated `self.device_suffix` to something invalid we
        // surface that as a panic here — better to crash the writer
        // than to emit a malformed HLC the cluster will accept.
        Hlc::new(self.last_physical_ms, self.counter, &self.device_suffix)
            .expect("HlcState.device_suffix invariant violated after construction")
    }

    /// Generate an HLC using the current wall-clock time.
    pub fn generate(&mut self) -> Hlc {
        // `duration_since(UNIX_EPOCH)` returns Err on a pre-1970
        // clock (devices without an RTC battery, VMs restored from
        // bad snapshots, deliberately-mis-set test clocks).
        // `.expect()`-ing this would panic on every HLC generation
        // and crash the Tauri app, the MCP server, and the CLI.
        // Fall back to Duration::ZERO and let
        // `generate_with_physical` preserve monotonicity via the
        // counter — HLC is explicitly designed for this case.
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or(std::time::Duration::ZERO)
            .as_millis() as u64;
        self.generate_with_physical(now_ms)
    }

    /// Update local state after receiving a remote HLC.
    ///
    /// Ensures subsequent local HLCs are strictly greater than the remote one.
    /// `physical_ms` is the current wall-clock time at the moment of receive.
    pub fn update_on_receive(&mut self, remote: &Hlc, physical_ms: u64) {
        // clamp the local wall clock to the accepted range
        // so a future-dated NTP response cannot push state past the
        // 13-digit lex-sort ceiling. The matching
        // `remote.physical_ms.min(MAX_HLC_PHYSICAL_MS)` clamp was
        // removed because every `Hlc` value is now guaranteed by the
        // type's constructors (`Hlc::new` and `Hlc::parse`) to satisfy
        // `physical_ms <= MAX_HLC_PHYSICAL_MS` — the defense-in-depth
        // clamp that live here can no longer observe a
        // violating value.
        let physical_ms = physical_ms.min(MAX_HLC_PHYSICAL_MS);
        // Sanitize a seeded-past-ceiling local state for the same
        // reason as `generate_with_physical` — a tainted on-disk
        // history would otherwise survive every receive and keep
        // emitting >13-digit physicals after the next generate.
        self.last_physical_ms = self.last_physical_ms.min(MAX_HLC_PHYSICAL_MS);
        let remote_physical_ms = remote.physical_ms();
        let new_physical = std::cmp::max(
            std::cmp::max(self.last_physical_ms, remote_physical_ms),
            physical_ms,
        );

        // `remote.counter` comes from a peer-supplied
        // HLC string parsed as u32, so the `+ 1` below could panic
        // (debug) or wrap to 0 (release) on a malicious / malformed
        // envelope with counter ≈ u32::MAX. Use saturating_add so the
        // MAX_COUNTER recovery guard below catches it and rolls the
        // physical clock forward, preserving monotonicity.
        if new_physical == self.last_physical_ms && new_physical == remote_physical_ms {
            // All three timestamps are the same: take max counter + 1.
            self.counter = std::cmp::max(self.counter, remote.counter()).saturating_add(1);
        } else if new_physical == self.last_physical_ms {
            // Local is the max: increment local counter.
            self.counter = self.counter.saturating_add(1);
        } else if new_physical == remote_physical_ms {
            // Remote is the max: continue from remote counter + 1.
            self.counter = remote.counter().saturating_add(1);
        } else {
            // Wall clock is strictly ahead of both: reset counter.
            self.counter = 0;
        }

        self.last_physical_ms = new_physical;

        // Counter overflow recovery: advance physical time by 1ms,
        // reset counter. Clamp the bump
        // to `MAX_HLC_PHYSICAL_MS` to match the generate path.
        // Without the clamp, a pathological case where both sides
        // are at the ceiling and the counter saturates would push
        // `last_physical_ms` to `MAX_HLC_PHYSICAL_MS + 1` — the
        // resulting HLC string would be 14 digits in the physical
        // half and lex-sort above every legitimate 13-digit entry,
        // poisoning every LWW comparison from this device forward.
        // Saturating at the ceiling preserves the lex-sort invariant
        // at the cost of holding the counter at 0 in this same ms,
        // which is the standard hold-and-retry HLC degenerate case.
        if self.counter > MAX_COUNTER {
            self.last_physical_ms = self
                .last_physical_ms
                .saturating_add(1)
                .min(MAX_HLC_PHYSICAL_MS);
            self.counter = 0;
        }
    }
}

#[cfg(test)]
mod tests;
