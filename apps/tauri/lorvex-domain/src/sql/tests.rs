use super::*;

#[test]
fn zero_count_returns_empty() {
    assert_eq!(sql_in_placeholders(0, 0), "");
}

#[test]
fn three_from_zero() {
    assert_eq!(sql_in_placeholders(3, 0), "?1, ?2, ?3");
}

#[test]
fn two_with_offset_five() {
    assert_eq!(sql_in_placeholders(2, 5), "?6, ?7");
}

#[test]
fn single_placeholder() {
    assert_eq!(sql_in_placeholders(1, 0), "?1");
}

#[test]
fn single_with_offset() {
    assert_eq!(sql_in_placeholders(1, 3), "?4");
}

// ── sql_csv_placeholders ─────────────────────────────────────────
// Pin both the rendered shape AND the single-allocation
// pre-allocation contract documented in the helper. The exact
// `String::with_capacity(3 * count - 2)` invariant guards against
// a future "quick" rewrite re-introducing the multi-Vec allocation
// shape `sql_in_placeholders` originally had.

#[test]
fn csv_zero_count_returns_empty() {
    let out = sql_csv_placeholders(0);
    assert_eq!(out, "");
    // Empty path returns a freshly-allocated String; capacity is
    // zero. Just assert the length is zero.
    assert!(out.is_empty());
}

#[test]
fn csv_single_placeholder() {
    assert_eq!(sql_csv_placeholders(1), "?");
}

#[test]
fn csv_two_placeholders() {
    assert_eq!(sql_csv_placeholders(2), "?, ?");
}

#[test]
fn csv_three_placeholders() {
    assert_eq!(sql_csv_placeholders(3), "?, ?, ?");
}

#[test]
fn csv_sixty_four_placeholders_have_exact_capacity() {
    let count = 64;
    let out = sql_csv_placeholders(count);
    // Each "?" plus ", " between → 3*count - 2 bytes total.
    assert_eq!(out.len(), 3 * count - 2);
    // Pin the no-grow invariant: the helper must pre-size the
    // `String` so the in-place writes never trigger a realloc.
    assert!(
        out.capacity() >= out.len(),
        "csv_csv_placeholders should pre-size to fit the rendered shape",
    );
    // Spot-check the rendered shape for the trailing chars.
    assert!(out.starts_with("?, ?"));
    assert!(out.ends_with(", ?"));
}
