//! Canonical HLC seed constants and runtime gate for test fixtures.
//!
//! the apply pipeline grew a `WHERE excluded.version >
//! version` LWW guard. A test seed using a non-HLC literal — anything
//! that doesn't sort strictly below realistic post-update HLCs — would
//! silently no-op the test's mutation when the guard fires, producing
//! a "row never updated" error rather than a real assertion failure.
//!
//! HLC strings are `{13-digit-ms}_{4-hex-ctr}_{16-char-device}` and
//! lex-sortable. The canonical seed below uses `0` for both the ms
//! and counter slots so it sorts strictly below every realistic
//! post-update HLC (real ms today is ~1.7e12). The device suffix is
//! a deterministic `test0000` tag — distinct from real device IDs
//! so the fixture-vs-production origin is obvious in a debug session.
//!
//! Use [`TEST_VERSION`] for any seed that the test does NOT mutate
//! through a code path with an active LWW gate. Use
//! [`seed_test_row_check`] (or, for a builder-style call, a future
//! `seed_test_row` helper) when you want a runtime assertion that
//! fires before the gate would silently swallow the mutation.

/// Canonical version literal for test fixtures.
///
/// Format: `{ms=0}_{ctr=0}_{device=test0000}`.
///
/// * `0000000000000` (13-digit ms): every realistic post-update HLC
///   has ms ≥ ~1.7e12, so this seed lex-sorts strictly below any
///   freshly-generated HLC. The LWW gate `excluded.version >
///   version` therefore always accepts the mutation.
/// * `0000` (4-hex counter): same lex argument applies — a real
///   counter increment within the same ms still produces a string
///   that sorts above this seed.
/// * `a0a0a0a0a0a0a0a0` (16-hex device suffix): satisfies the strict
///   `Hlc::parse` invariant from #2973-H5 (16 lowercase hex chars)
///   while staying visibly distinct from realistic device suffixes
///   so a debug session can tell "this version came from a test
///   fixture" at a glance.
pub const TEST_VERSION: &str = "0000000000000_0000_a0a0a0a0a0a0a0a0";

/// Validate that `version` will not silently no-op a test mutation
/// against an apply-pipeline LWW gate.
///
/// Rejects strings whose first character is not an ASCII digit
/// (HLCs always start with the millisecond timestamp). Letter-
/// prefixed seeds like `'test_ver'`, `'seed-v1'`, or `'seedseed'`
/// sort strictly ABOVE every realistic HLC, so any LWW-gated
/// mutation against the seeded row would be silently rejected.
///
/// Returns `Ok(())` for any HLC-shaped string (including the
/// canonical [`TEST_VERSION`]). Returns an `Err` whose `String`
/// payload names the offending seed so the panic surface in the
/// caller's `.expect("seed_test_row_check")` is actionable.
pub fn seed_test_row_check(version: &str) -> Result<(), String> {
    let first = version.chars().next();
    match first {
        Some(c) if c.is_ascii_digit() => Ok(()),
        Some(c) => Err(format!(
            "test fixture version `{version}` starts with non-digit `{c}`. \
             HLC strings begin with a 13-digit millisecond timestamp; a \
             letter-prefixed seed sorts strictly above every realistic \
             HLC and would silently no-op any LWW-gated mutation. Use \
             `lorvex_store::test_support::TEST_VERSION` (or a per-row \
             variant with a unique counter slot) instead."
        )),
        None => Err("test fixture version is empty".to_string()),
    }
}

#[cfg(test)]
mod tests;
