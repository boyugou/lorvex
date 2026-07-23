//! Tag domain types and lookup key normalization.
//!
//! The `normalize_lookup_key` function is the single canonical way to convert
//! a human-supplied display name into a machine-comparable lookup key. All
//! code paths that need to match tags by name call this function. No ad-hoc
//! lowercasing elsewhere in the codebase.
//!
//! Rules:
//! 1. Unicode NFKC normalization
//! 2. Trim leading/trailing whitespace
//! 3. Collapse internal whitespace to single space
//! 4. Unicode casefold (lowercase as approximation — Rust std has no ICU casefold)
//! 5. Preserve emoji, CJK characters, all Unicode
//! 6. Never strip characters beyond whitespace normalization

use unicode_normalization::UnicodeNormalization;

use crate::sanitize_user_text;

/// Normalize a display name into a machine-comparable lookup key.
///
/// The output is suitable for UNIQUE constraint enforcement and
/// case-insensitive tag deduplication across sync boundaries.
///
/// switched from `c.to_lowercase()` (Rust std locale-
/// independent lowercase mapping) to `caseless::default_case_fold_str`
/// (Unicode UTS #18 R3 default casefold). The std `to_lowercase`:
///   - leaves Turkish dotless `ı` (U+0131) and dotted `İ` (U+0130)
///     mapping to distinct sequences (`ı`, `i\u{307}`)
///   - leaves German `ß` (U+00DF) lowercased to itself rather than
///     folding to `ss`
///   - does not unify Greek final sigma `ς` with medial `σ`
///
/// Two devices that locally produced the same display string therefore
/// reached different `lookup_key` values and the apply-time tag merge
/// (the very feature `lookup_key` exists to enable) silently failed.
/// Default casefold is the right primitive: locale-independent,
/// covers the full Unicode 14+ tables, lossless under NFKC re-
/// composition.
pub fn normalize_lookup_key(display_name: &str) -> String {
    // strip bidi controls, zero-width chars, BOM, and
    // other invisibles **before** NFKC. NFKC preserves these
    // codepoints, so without sanitization a tag named `Work\u{200B}`
    // (zero-width space) would compute a different lookup key than
    // `Work` and never dedupe across the sync boundary — and a
    // homoglyph attacker could force lookup-key collisions by
    // injecting invisibles into otherwise-identical display strings.
    let scrubbed = sanitize_user_text(display_name);
    let nfkc: String = scrubbed.nfkc().collect();
    let trimmed = nfkc.trim();

    // Casefold first so multi-codepoint expansions (e.g. `ß` → `ss`,
    // `İ` → `i\u{307}`) participate in whitespace collapsing.
    let folded = caseless::default_case_fold_str(trimmed);

    let mut result = String::with_capacity(folded.len());
    let mut prev_space = false;
    for c in folded.chars() {
        if c.is_whitespace() {
            if !prev_space {
                result.push(' ');
                prev_space = true;
            }
        } else {
            result.push(c);
            prev_space = false;
        }
    }
    result
}

#[cfg(test)]
mod tests;
