//! Allocation-free cross-string HLC comparator used by every LWW gate
//! in `lorvex_sync::apply::*`. Falls back to byte-compare when either
//! side fails to parse so tainted local versions still refuse a
//! delete.

use super::core::MAX_HLC_PHYSICAL_MS;

/// Compare two HLC version strings, falling back to a byte-compare when
/// either side fails to parse.
///
/// Every LWW gate (`evaluate_delete_lww` in
/// `lorvex_sync::apply::aggregate::helpers`,
/// `blob_delete_lww_decision` in `lorvex_sync::apply::blob`, and the
/// implicit byte-compare path in the upsert SQL `version_cmp`
/// predicate) routes through this comparator so the parse-failure
/// semantics stay aligned across every reader. The byte-compare
/// fallback preserves the SQL `:version >= version` predicate's
/// safety for tainted local versions: a value that sorts strictly
/// greater than a well-formed envelope still wins the comparison
/// and refuses the delete.
///
/// Returns the [`std::cmp::Ordering`] of `left` vs `right` under the
/// HLC ordering when both parse, else under raw byte ordering.
pub fn compare_versions_with_fallback(left: &str, right: &str) -> std::cmp::Ordering {
    // Either side unparseable — fall back to a byte compare. The
    // call sites in `lorvex_sync::apply` are responsible for
    // logging the corruption to `error_logs` so diagnostics
    // surface the unparseable version; this comparator is the
    // pure decision primitive and stays IO-free.
    compare_canonical_hlc_strs(left, right).unwrap_or_else(|| left.cmp(right))
}

/// Allocation-free HLC comparator. Splits each side on `_` into the
/// three lex-sortable segments (`physical_ms`, `counter`,
/// `device_suffix`), parses the numeric segments as `u64` / `u32`,
/// and falls back to byte comparison on the device_suffix. Returns
/// `None` when either side fails to parse so the caller can route
/// through the byte-compare fallback in
/// [`compare_versions_with_fallback`].
///
/// The previous shape went through `Hlc::parse` twice, each
/// allocating a `String` for the lowercased device suffix even on
/// the canonical lowercase happy path. Two `String` allocations per
/// LWW comparison on the apply hot path was an avoidable
/// allocator-churn cost; the segment-wise compare here reads-only.
fn compare_canonical_hlc_strs(left: &str, right: &str) -> Option<std::cmp::Ordering> {
    let (l_phys, l_ctr, l_suf) = split_canonical_hlc_segments(left)?;
    let (r_phys, r_ctr, r_suf) = split_canonical_hlc_segments(right)?;
    // Mirror `Hlc::cmp`'s case-insensitive suffix order: `Hlc::parse`
    // lowercases the suffix on construction so `_AABBCCDD` and
    // `_aabbccdd` compare equal. Walk both byte streams under
    // `to_ascii_lowercase` so the same equivalence holds without
    // allocating either side. The 16-char invariant is enforced
    // upstream by `validate_device_suffix`; here we only need the
    // case-insensitive comparison ordering.
    Some(
        l_phys
            .cmp(&r_phys)
            .then_with(|| l_ctr.cmp(&r_ctr))
            .then_with(|| {
                l_suf
                    .bytes()
                    .map(|b| b.to_ascii_lowercase())
                    .cmp(r_suf.bytes().map(|b| b.to_ascii_lowercase()))
            }),
    )
}

/// Split a canonical HLC string into `(physical_ms, counter,
/// device_suffix)`. Returns `None` for any malformed shape — wrong
/// segment count, non-numeric physical_ms / counter, or
/// physical_ms past the lex-sort ceiling. The device_suffix is
/// returned verbatim (no normalization); a caller that needs the
/// canonical lowercase form must use [`Hlc::parse`](super::Hlc::parse).
fn split_canonical_hlc_segments(s: &str) -> Option<(u64, u32, &str)> {
    let mut iter = s.splitn(3, '_');
    let phys_str = iter.next()?;
    let ctr_str = iter.next()?;
    let suf = iter.next()?;
    if iter.next().is_some() {
        return None;
    }
    let phys = phys_str.parse::<u64>().ok()?;
    if phys > MAX_HLC_PHYSICAL_MS {
        return None;
    }
    let ctr = ctr_str.parse::<u32>().ok()?;
    Some((phys, ctr, suf))
}
