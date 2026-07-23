//! Recurrence instance key generation for spawn dedup.
//!
//! When a recurring task is completed and a successor is spawned, the successor
//! receives an immutable `recurrence_instance_key`. If two devices complete the
//! same recurring task offline, each spawns a successor with a different UUIDv7
//! but the same instance key — enabling deterministic dedup during sync.
//!
//! Key format: `"{recurrence_group_id}:{canonical_occurrence_date}"`
//! where `canonical_occurrence_date` is the RRULE-computed date (YYYY-MM-DD),
//! NOT the user-editable planned_date.
//!
//! See spec Section 13: Recurring Task Spawn Dedup.

/// Generate a recurrence instance key for a spawned successor task.
///
/// This key is immutable after creation and used for cross-device dedup.
///
/// Format: `"{recurrence_group_id}:{canonical_occurrence_date}"`
/// where `canonical_occurrence_date` is the RRULE-computed date (YYYY-MM-DD),
/// NOT the user-editable `planned_date`.
///
/// `recurrence_group_id` MUST canonically be a UUID (typically
/// UUIDv7 — hex digits and `-` only). The validator below enforces
/// the unambiguous-key invariant by rejecting any byte that would
/// confuse downstream LIKE / exact-match queries built from the
/// returned key:
///
///   * the separator `:` itself,
///   * any ASCII whitespace (LF / CR / TAB / SPACE / FF / VT) which
///     would corrupt naive string-prefix matching,
///   * NUL or other ASCII control bytes,
///   * the SQL LIKE wildcards `%` and `_` which would let a
///     malformed peer payload masquerade as a wildcard match.
///
/// Returns `None` for empty input or any byte outside the safe set.
/// The byte allowlist rejects `%`, `_`, control bytes, whitespace,
/// and `:` so a hostile id can't round-trip into the key and pollute
/// downstream LIKE / exact-match queries.
pub fn generate_instance_key(
    recurrence_group_id: &str,
    canonical_occurrence_date: &str,
) -> Option<String> {
    if recurrence_group_id.is_empty() {
        return None;
    }
    // The separator is `:`, so reject any group id that contains one
    // (or any whitespace / SQL-wildcard / control byte that would
    // corrupt LIKE / exact-match queries built from the key).
    if recurrence_group_id.bytes().any(|b| {
        b == b':' || b.is_ascii_whitespace() || b.is_ascii_control() || b == b'%' || b == b'_'
    }) {
        return None;
    }
    // Validate the date side as well. Without this check,
    // `generate_instance_key("group", "not-a-date")` would return
    // `Some("group:not-a-date")`, letting a malformed peer payload
    // that sneaks past upstream validation produce a key that
    // pollutes downstream LIKE / exact-match queries on the canonical
    // YYYY-MM-DD shape.
    if !is_canonical_ymd(canonical_occurrence_date) {
        return None;
    }
    Some(format!("{recurrence_group_id}:{canonical_occurrence_date}"))
}

fn is_canonical_ymd(s: &str) -> bool {
    // Defer to chrono for month/day range validation: a digit/hyphen
    // position check alone would let semantically bogus values like
    // `"2026-13-99"` round-trip into the instance key. The canonical
    // 10-char zero-padded shape is still gated up-front because
    // `%Y-%m-%d` is lenient about zero-padding (`"2026-4-5"` parses)
    // and we require a fixed-width key for downstream LIKE / exact-
    // match queries.
    if s.len() != 10 {
        return false;
    }
    let bytes = s.as_bytes();
    if bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    crate::time::parse_iso_date(s).is_ok()
}

#[cfg(test)]
mod tests;
