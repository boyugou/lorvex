//! Unicode hygiene for user-supplied free-text fields.
//!
//! This module provides [`sanitize_user_text`], a minimal scrubber that removes
//! invisible / formatting control codepoints that enable rendering attacks
//! (bidi spoofing, zero-width tag merges, line-terminator injection) and then
//! normalizes the result to NFC.
//!
//! Scope (intentionally narrow):
//! - Strip bidi overrides and isolates (U+202A–E, U+2066–9).
//! - Strip zero-width chars (U+200B–D) and the BOM (U+FEFF).
//! - Strip Unicode line/paragraph separators (U+2028, U+2029).
//! - Normalize to NFC so combining-mark stacking collapses to a canonical form.
//!
//! Non-scope (deliberately not done here):
//! - Visible letters from any script (Latin, CJK, Cyrillic, RTL, emoji, accents)
//!   are preserved verbatim. Homoglyph detection belongs in a UI warning layer,
//!   not in the write-boundary hygiene pass.
//! - Tag lookup-key normalization already performs NFKC + casefold + whitespace
//!   collapse (see `tag::normalize_lookup_key`). This helper is additive and
//!   meant to be applied *before* tag normalization on the display name.
//! - No Unicode Technical Report #39 restricted-identifier logic.
//!
//! ## When to use this vs. [`crate::text_sanitize`]
//!
//! Both modules share [`is_disallowed_codepoint`] as the single
//! source of truth for the strip set, so they can never drift on
//! *which* codepoints are dropped. They differ on two policy axes:
//!
//! - **CR (`\r`)**: this module preserves CR (Windows authors of
//!   multi-line task bodies); `text_sanitize` drops it for
//!   CRLF→LF canonicalization on inbound peer text.
//! - **NFC normalization**: this module applies it (predictable
//!   search/equality at the write boundary); `text_sanitize`
//!   skips it (a peer's ICS feed may have authored its combining
//!   marks intentionally).
//!
//! Reach for **`sanitize_user_text`** when a human or model has just
//! authored the string and you're about to persist it. Reach for
//! **`text_sanitize::strip_dangerous_codepoints`** when the bytes
//! came from an untrusted peer (calendar feeds, sync payload
//! previews) and you only want the minimal control-codepoint scrub.

use unicode_normalization::UnicodeNormalization;

/// Sanitize user-supplied text: strip zero-width, bidi-override, and format
/// control codepoints; then normalize to NFC.
///
/// This is the single canonical hygiene pass applied at every write boundary
/// that accepts free-text from a human or model (task title/body/ai_notes,
/// tag display names, list names, subscription names, etc.).
///
/// Does NOT touch letter-like characters from any script — only the
/// invisible/format control codepoints that enable bidi or zero-width attacks.
///
/// # Examples
///
/// ```
/// use lorvex_domain::sanitize_user_text;
///
/// // Letter-like characters from any script are preserved.
/// assert_eq!(sanitize_user_text("Hello"), "Hello");
/// assert_eq!(sanitize_user_text("こんにちは"), "こんにちは");
/// assert_eq!(sanitize_user_text("привет"), "привет");
///
/// // Zero-width and bidi-override codepoints are stripped.
/// assert_eq!(sanitize_user_text("paypal\u{202E}moc"), "paypalmoc");
/// assert_eq!(sanitize_user_text("ad\u{200B}min"), "admin");
/// assert_eq!(sanitize_user_text("\u{FEFF}prefix"), "prefix");
///
/// // Newlines / tabs / CR are preserved (multi-line bodies).
/// assert_eq!(sanitize_user_text("a\nb\tc\rd"), "a\nb\tc\rd");
///
/// // ESC / null / other C0 controls are stripped (terminal-escape attacks).
/// assert_eq!(sanitize_user_text("safe\u{1B}[31mred"), "safe[31mred");
/// assert_eq!(sanitize_user_text("a\0b"), "ab");
///
/// // Output is NFC-normalized; combining marks collapse to canonical form.
/// // U+0301 (COMBINING ACUTE) on top of "e" canonicalizes to U+00E9 (é).
/// assert_eq!(sanitize_user_text("e\u{0301}"), "é");
/// ```
pub fn sanitize_user_text(input: &str) -> String {
    input
        .chars()
        .filter(|c| !is_disallowed_codepoint(*c))
        .nfc()
        .collect()
}

/// Returns `true` for codepoints that should be stripped from user text.
///
/// The set is intentionally small and documented inline so auditors can verify
/// we are not overreaching into legitimate script characters.
///
/// exposed at crate-public scope so `text_sanitize::
/// is_dangerous_codepoint` can delegate to a single source of truth
/// for the strip set. The two sanitization surfaces differ only in
/// CR handling and NFC normalization (see the
/// `text_sanitize::is_dangerous_codepoint` doc); the codepoint
/// allowlist itself must stay in sync.
pub fn is_disallowed_codepoint(c: char) -> bool {
    // strip C0 (U+0000..=U+001F) and C1 (U+0080..=U+009F)
    // control codepoints, EXCEPT tab (U+0009), line feed (U+000A), and
    // carriage return (U+000D) — those are legitimate whitespace in
    // multi-line task bodies and notes content. Null bytes in
    // particular truncate at some display layers and break FTS5
    // indexing; U+001B (ESC) enables ANSI terminal escape sequences
    // that jailbreak terminal-hosted MCP clients.
    if (c as u32) <= 0x1F && c != '\t' && c != '\n' && c != '\r' {
        return true;
    }
    // include DEL (U+007F) alongside the C1 control
    // block (U+0080..=U+009F). Pre-L2 the write-boundary surface
    // missed U+007F entirely while the untrusted-text surface
    // (`text_sanitize::is_dangerous_codepoint`) correctly stripped
    // the entire `0x7F..=0x9F` range — a silent gap between the two
    // helpers. Now that this is the single source of truth for both
    // surfaces, DEL must be in the strip set.
    if c == '\u{007F}' || (0x80..=0x9F).contains(&(c as u32)) {
        return true;
    }
    matches!(c,
        // Bidi overrides / isolates (U+202A..=U+202E, U+2066..=U+2069)
        '\u{202A}'..='\u{202E}'
        | '\u{2066}'..='\u{2069}'
        // LRM (U+200E) / RLM (U+200F): single-codepoint bidi marks. Less
        // dramatic than the override range but still rendering-bidirectional;
        // strip per #2941-M4.
        | '\u{200E}' | '\u{200F}'
        // Arabic Letter Mark (U+061C) — completes the
        // bidi-mark family alongside LRM/RLM. Renders zero-width but
        // steers bidi for Arabic-numeral neighbors; strip for parity
        // with the rest of the bidi set.
        | '\u{061C}'
        // Zero-width chars (ZWSP, ZWNJ, ZWJ) + BOM used as ZWNBSP
        | '\u{200B}'..='\u{200D}'
        | '\u{FEFF}'
        // word-joiner (U+2060) and the deprecated
        // function-call invisible operators (U+2061..=U+2064). All
        // render as zero-width and can split FTS tokens or lookup
        // keys the same way ZWSP does. The function operators were
        // intended for math typesetting; they have no place in
        // user-facing free-text.
        | '\u{2060}'..='\u{2064}'
        // Mongolian Vowel Separator (U+180E): default-ignorable in Unicode 6.3+
        // and behaves as a zero-width separator in many renderers, so it can
        // split lookups the same way ZWSP does (#2941-M4).
        | '\u{180E}'
        // Unicode line/paragraph separators
        | '\u{2028}' | '\u{2029}'
    )
}

/// Recursively scrub every JSON string leaf via `sanitize_user_text`.
///
/// write surfaces that accept arbitrary JSON (the MCP
/// `set_preference` payload, task note values, memory
/// revision payloads) stored their values verbatim — a
/// nested string field carrying a bidi override or zero-width
/// joiner round-tripped to disk and back unchanged, defeating the
/// #2427 hygiene gate at the leaf. This walks the tree in place
/// and rewrites every string leaf through the same canonical
/// scrubber the flat-text surfaces use.
///
/// Object keys are NOT scrubbed: keys are schema-defined identifiers
/// that the caller (or an upstream contract validator) constrains to
/// safe ASCII. Scrubbing them would silently change the shape of the
/// stored object and break round-trip equality. Numbers, booleans,
/// and null pass through unchanged because they cannot carry the
/// invisible-control attack vector.
///
/// Mutates in place; the function name uses `_in_place` to make the
/// mutation explicit at the call site.
pub fn sanitize_user_text_in_json_in_place(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::String(s) => {
            // Avoid the allocation when sanitization is a no-op (the
            // common case for already-clean values). Only re-write
            // when the scrubbed form differs from the original.
            let scrubbed = sanitize_user_text(s);
            if scrubbed != *s {
                *s = scrubbed;
            }
        }
        serde_json::Value::Array(items) => {
            for item in items.iter_mut() {
                sanitize_user_text_in_json_in_place(item);
            }
        }
        serde_json::Value::Object(map) => {
            for (_key, v) in map.iter_mut() {
                sanitize_user_text_in_json_in_place(v);
            }
        }
        // Number / Bool / Null carry no string data — pass through.
        _ => {}
    }
}

#[cfg(test)]
mod tests;
