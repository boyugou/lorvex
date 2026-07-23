/// Build a comma-separated list of numbered SQL positional placeholders.
///
/// Use when the surrounding statement mixes the IN list with other
/// `?N`-bound parameters and the explicit numbering keeps the bind
/// table readable. For an IN list whose binds are just the contents
/// of the iterator (no leading params), prefer
/// [`sql_csv_placeholders`] — it produces a more compact `"?, ?"`
/// shape and avoids the per-element `format!` allocation.
///
/// # Examples
///
/// ```
/// use lorvex_domain::sql_in_placeholders;
///
/// assert_eq!(sql_in_placeholders(3, 0), "?1, ?2, ?3");
/// assert_eq!(sql_in_placeholders(2, 5), "?6, ?7");
/// assert_eq!(sql_in_placeholders(0, 0), "");
/// ```
pub fn sql_in_placeholders(count: usize, offset: usize) -> String {
    use std::fmt::Write as _;
    if count == 0 {
        return String::new();
    }
    // Pre-allocate a generous buffer estimate based on the upper-bound
    // digit width of the highest placeholder index. The previous shape
    // allocated a fresh `String` per element via `format!`, then
    // collected into a `Vec`, then `.join(", ")` allocated the final
    // string — three allocations per call. Writing into a pre-sized
    // `String` directly drops to one allocation. The width estimate
    // upper-bounds via `final_index.checked_ilog10()`; for 1..=9 it's
    // 1 digit, 10..=99 is 2, etc. Adding 3 chars per element ("?, "
    // or "?N") plus the leading "?N" gives a buffer that never grows.
    let final_index = offset + count;
    let max_digits = final_index.checked_ilog10().unwrap_or(0) as usize + 1;
    let per_element = 1 + max_digits + 2; // `?`, digits, `, `
    let mut out = String::with_capacity(per_element * count);
    for i in 0..count {
        if i > 0 {
            out.push_str(", ");
        }
        write!(out, "?{}", offset + i + 1).expect("write! to String is infallible");
    }
    out
}

/// Build a comma-separated list of unnumbered SQL placeholders
/// (`?, ?, ?`) for an `IN (...)` clause whose binds are passed via
/// `params_from_iter` (or any other ordered binding shape).
///
/// Pre-allocates the exact byte length up-front: each placeholder is
/// `?` plus a `, ` separator (except the last), so the buffer length
/// is `3 * count - 2` for `count >= 1` and `0` otherwise. The
/// previous shapes scattered across the workspace —
/// `vec!["?"; n].join(", ")`, `std::iter::repeat_n("?", n).collect::<Vec<_>>().join(",")`,
/// hand-written `for` loops — each allocated an intermediate `Vec`
/// and re-derived the same string; folding them through this single
/// helper drops the temp Vec allocation and keeps the placeholder
/// shape consistent across crates.
///
/// # Examples
///
/// ```
/// use lorvex_domain::sql::sql_csv_placeholders;
///
/// assert_eq!(sql_csv_placeholders(3), "?, ?, ?");
/// assert_eq!(sql_csv_placeholders(1), "?");
/// assert_eq!(sql_csv_placeholders(0), "");
/// ```
pub fn sql_csv_placeholders(count: usize) -> String {
    if count == 0 {
        return String::new();
    }
    let mut out = String::with_capacity(3 * count - 2);
    out.push('?');
    for _ in 1..count {
        out.push_str(", ?");
    }
    out
}

#[cfg(test)]
mod tests;
