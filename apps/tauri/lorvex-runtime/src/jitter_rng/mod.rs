//! Process-local jitter PRNG shared by sync back-off schedulers.
//!
//! Sync transports add ±10% jitter to their exponential-backoff intervals so
//! N devices that share a wall clock via NTP and hit the same outage don't
//! stampede back in
//! lockstep once connectivity returns. This module centralizes the
//! xorshift64*/SplitMix64-seeded helper those transports used to
//! duplicate verbatim (#2749), so there is exactly one implementation
//! to audit for randomness quality and one seeding strategy to reason
//! about.
//!
//! The output is explicitly **not cryptographic**. It exists only to
//! de-correlate retry schedules across devices and across invocations
//! within a process.

use std::time::{SystemTime, UNIX_EPOCH};

/// SplitMix64 / xorshift64* golden ratio constant. Used in the seed
/// mixing step. Do not edit without validating against the reference
/// suite (Vigna, 2014: <https://prng.di.unimi.it/splitmix64.c>).
const SPLITMIX_GOLDEN: u64 = 0x9E37_79B9_7F4A_7C15;

/// SplitMix64 mixer constant. Used in the seed mixing step and as the
/// non-zero fallback when the derived seed collapses to zero (which
/// would otherwise wedge xorshift64* at zero forever).
const SPLITMIX_MIXER: u64 = 0xBF58_476D_1CE4_E5B9;

/// xorshift64* multiplier from Vigna's "An experimental exploration of
/// Marsaglia's xorshift generators, scrambled" (2014).
const XORSHIFT64_STAR_MULTIPLIER: u64 = 0x2545_F491_4F6C_DD1D;

/// Process-local SplitMix64-seeded xorshift64* jitter RNG for
/// exponential-backoff fuzz.
///
/// Seeded from `SystemTime::now()` XOR `std::process::id()`. Not
/// cryptographic — used only to avoid thundering-herd reconnect
/// alignment across devices.
#[derive(Debug)]
pub struct JitterRng {
    state: u64,
}

impl JitterRng {
    /// Seed from wall clock + pid.
    ///
    /// Mixing the pid into the wall-clock-derived seed is what lets
    /// two devices whose clocks are NTP-aligned still diverge
    /// immediately on the first call — pid collisions across machines
    /// are extremely unlikely, and even a repeat lands in a different
    /// xorshift orbit because of the golden-ratio multiplications.
    pub fn from_entropy() -> Self {
        use std::sync::atomic::{AtomicU64, Ordering};
        // Monotonic per-process counter mixed into every seed so that
        // back-to-back constructions within the same process diverge
        // even when the wall clock hasn't ticked (nanos resolution
        // varies by platform — macOS `SystemTime` has microsecond
        // resolution on some kernels, so two `from_entropy()` calls in
        // a tight loop can observe identical nanos). Without this a
        // reseed storm — two transports both bouncing, both reseeding
        // on the same ms — could produce near-identical streams.
        static SEQ: AtomicU64 = AtomicU64::new(0);
        // the only invariant
        // this counter guarantees is "no two concurrent
        // `fetch_add` calls return the same value." That is a
        // property of atomicity itself — every `Ordering` variant
        // satisfies it — and there is no sibling state whose
        // visibility we need to order against the seq value, so
        // `Relaxed` is the right contract. Two transports reseeding
        // in the same wall-clock millisecond observe distinct seq
        // values and therefore distinct seeds, which is the only
        // property the de-correlation argument depends on.
        let seq = SEQ.fetch_add(1, Ordering::Relaxed);

        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos() as u64);
        let pid = u64::from(std::process::id());
        let candidate = nanos
            .wrapping_mul(SPLITMIX_GOLDEN)
            .wrapping_add(pid.wrapping_mul(SPLITMIX_MIXER))
            .wrapping_add(seq.wrapping_mul(SPLITMIX_GOLDEN));
        // xorshift64* is wedged at zero, so fall back to the mixer
        // constant if the derived seed is (astronomically unlikely to
        // be) zero.
        let state = if candidate == 0 {
            SPLITMIX_MIXER
        } else {
            candidate
        };
        Self { state }
    }

    /// For tests — injectable seed.
    ///
    /// Accepts any `u64`; the zero sentinel is remapped to `1` so the
    /// xorshift64* step can never wedge.
    pub const fn from_seed(seed: u64) -> Self {
        Self {
            state: if seed == 0 { 1 } else { seed },
        }
    }

    /// Next u64 (xorshift64*).
    pub const fn next_u64(&mut self) -> u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        // The trailing multiplication is what turns plain xorshift64
        // (known to fail several statistical tests) into xorshift64*
        // (passes BigCrush). Cheap; no reason to skip it.
        self.state.wrapping_mul(XORSHIFT64_STAR_MULTIPLIER)
    }

    /// Jitter in milliseconds, bounded to `[0, max)`.
    ///
    /// `max == 0` yields `0` (no jitter applied).
    pub const fn jitter_ms(&mut self, max: u64) -> u64 {
        if max == 0 {
            0
        } else {
            self.next_u64() % max
        }
    }
}

#[cfg(test)]
mod tests;
