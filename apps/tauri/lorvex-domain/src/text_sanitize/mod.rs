//! Untrusted-text sanitization helpers.
//!
//! Strips codepoints that have no legitimate place in user-readable string
//! payloads flowing through Lorvex from untrusted peers (calendar feeds,
//! synced memory entries, etc.). See the per-range comments in
//! [`is_dangerous_codepoint`] for rationale.
//!
//! ## When to use this vs. [`crate::unicode_hygiene`]
//!
//! Both modules share the same codepoint allowlist
//! ([`crate::unicode_hygiene::is_disallowed_codepoint`]) so they can
//! never drift on the strip set. They differ on two policy dimensions:
//!
//! | Concern | `text_sanitize` (this module) | `unicode_hygiene` |
//! |---|---|---|
//! | CR (`\r`) handling | Stripped (canonicalize CRLF→LF) | Preserved |
//! | NFC normalization | Not applied | Applied |
//! | Intended caller | Untrusted-peer text after the bytes have already crossed our trust boundary (ICS imports, sync payload previews) | Write boundaries where a human or model has just authored the text (task title/body/ai_notes, list/tag display names) |
//!
//! Use **`text_sanitize::strip_dangerous_codepoints`** when you've
//! received text from an untrusted peer and want the cheapest pass
//! that strips dangerous codepoints without altering combining-mark
//! intent (which a peer's ICS feed may have set deliberately). Use
//! **`unicode_hygiene::sanitize_user_text`** at the typed-field write
//! boundary inside Lorvex, where NFC normalization is the right
//! call (composed canonical form makes search/equality predictable)
//! and where bare CR is part of a multi-line body authored on Windows.
//!
//! Issues:
//! - #2425 (`unescape_ics` — calendar subscription feeds)
//! - #2429 (`read_memory_session_summary` — synced memory content)
//!
//! Newline (U+000A) and tab (U+0009) are preserved because multi-paragraph
//! content is a legitimate use case; every other C0 code, DEL, the C1 block,
//! bidi overrides/isolates, zero-width joiners, and BOM/ZWNBSP are dropped.
//! CR (U+000D) is also dropped: callers are expected to have already
//! canonicalized CRLF→LF (RFC 5545 unfolding etc.), so a bare CR reaching
//! this helper is either a Windows-line-ending artifact or a spoofing
//! attempt, and we canonicalize to LF either way.
//!
//! Unicode NFC normalization is intentionally NOT performed here — that's
//! tracked separately in #2427.

/// Return `true` for codepoints that have no legitimate place in a
/// user-readable string payload from an untrusted source.
///
/// Delegates to `unicode_hygiene::is_disallowed_codepoint` for the
/// bulk of the strip set so the two surfaces never drift on the
/// codepoint allowlist (any divergence — e.g. one side missing
/// U+061C / U+2060-2064 — would let hostile peer text slip past one
/// boundary while the other rejects it). The only addition here is
/// CR (U+000D), dropped so callers (ICS feeds, memory previews) get
/// a CRLF→LF canonicalization for free; the write-boundary surface
/// preserves CR for multi-line task bodies authored on Windows. NFC
/// normalization is still NOT applied here — that's
/// `sanitize_user_text`'s job at the typed-field write boundary;
/// applying it to untrusted peer text could mangle a calendar
/// feed's intentional combining-mark stacking.
pub fn is_dangerous_codepoint(c: char) -> bool {
    // CR canonicalization: untrusted-text path drops CR so a stray
    // bare \r doesn't smuggle through as a layout artifact.
    if c == '\u{000D}' {
        return true;
    }
    crate::unicode_hygiene::is_disallowed_codepoint(c)
}

/// Pure, single-pass filter that drops every codepoint flagged by
/// [`is_dangerous_codepoint`]. Allocates once at the input's byte capacity
/// to match the unchanged string in the common case where nothing is
/// stripped.
pub fn strip_dangerous_codepoints(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if !is_dangerous_codepoint(c) {
            out.push(c);
        }
    }
    out
}

#[cfg(test)]
mod tests;
