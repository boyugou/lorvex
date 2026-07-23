//! Text-field validators (title, body, tag name).
//!
//! All length checks count Unicode codepoints so the
//! domain layer agrees with the MCP / Tauri / TS surfaces that all
//! count codepoints too.

use super::error::ValidationError;
use super::limits::{MAX_BODY_LENGTH, MAX_TAG_NAME_LENGTH, MAX_TITLE_LENGTH};
use crate::unicode_hygiene::is_disallowed_codepoint;

/// Returns true when `s` contains nothing but invisible/strippable
/// codepoints (zero-width joiners, bidi marks, BOM, control chars
/// excluding the legitimate `\t \n \r`) plus whitespace. Treating
/// "post-sanitize empty" as empty here closes a gap that `str::trim`
/// alone leaves: trim does not remove zero-width codepoints, so a
/// title that looks empty in the UI (nothing but ZWS / BOM / RLO
/// padding) would pass a bare non-empty check.
///
/// `validate_title`, `validate_body`, and `validate_tag_name` all
/// route through `measure_visibility_and_length` (a fused single-pass
/// variant) so the predicate lives in one place. Without a shared
/// helper, `validate_body` would still let a 50KB body of
/// `\u{200B}\u{FEFF}\u{202E}…` repeats consume the per-task body
/// budget while looking empty in every UI surface, and
/// `validate_tag_name` would have the same gap.
///
/// `pub` so the MCP / Tauri title validators (which deliberately
/// keep their own `"task title must not be empty"` wording for issue
/// #2994 H2) can apply the same visually-empty rejection without
/// forking the disallowed-codepoint set. A bare `trim().is_empty()`
/// would let a title made of nothing but ZWS / BOM / RLO padding
/// sneak past those two surfaces whenever upstream sanitization is
/// bypassed (tests, sync apply paths, or future callers that skip
/// `sanitize_user_text`).
pub fn is_visually_empty(s: &str) -> bool {
    s.chars()
        .all(|c| c.is_whitespace() || is_disallowed_codepoint(c))
}

/// Single-pass `(visually_empty, char_count)` measurement.
///
/// `validate_title` / `validate_tag_name` walked `chars()`
/// twice — once via `is_visually_empty(title)` and once for
/// `title.chars().count()`. Folding both checks into one walk halves
/// the per-call cost on the hot title-validation path without
/// changing semantics. The `trim().is_empty()` pre-guard the old
/// call sites carried was redundant: `is_whitespace()` is already in
/// the visibility predicate, so an all-whitespace title is reported
/// as visually-empty by this single pass.
fn measure_visibility_and_length(s: &str) -> (bool, usize) {
    let mut visually_empty = true;
    let mut char_count = 0;
    for c in s.chars() {
        char_count += 1;
        if !(c.is_whitespace() || is_disallowed_codepoint(c)) {
            visually_empty = false;
        }
    }
    (visually_empty, char_count)
}

/// Validate a task or list title: must be non-empty and within
/// [`MAX_TITLE_LENGTH`] Unicode codepoints.
///
/// Counts codepoints (matching the MCP + Tauri surfaces) so a
/// 1000-emoji title is treated identically across every entry
/// point. A byte-counting variant would let a long emoji title pass
/// MCP and fail this shared helper. Codepoints is the defensible
/// unit for user-facing text — a per-locale cap wouldn't make sense.
///
/// Also rejects titles that are visually empty after stripping
/// zero-width / bidi / control codepoints, so a 1000-codepoint
/// string of `"x\u{200B}"` repeats (which reads as `"x"` after
/// sanitization, or as nothing once the visible char is also
/// strippable) cannot pass the length gate on raw codepoint count
/// alone.
pub fn validate_title(title: &str) -> Result<(), ValidationError> {
    let (visually_empty, char_count) = measure_visibility_and_length(title);
    if visually_empty {
        return Err(ValidationError::Empty("title"));
    }
    if char_count > MAX_TITLE_LENGTH {
        return Err(ValidationError::TooLong {
            field: "title",
            max: MAX_TITLE_LENGTH,
            actual: char_count,
        });
    }
    Ok(())
}

/// Validate a task body: empty bodies are accepted (a body is
/// optional) but a non-empty body that contains nothing visible
/// after stripping zero-width / bidi / control codepoints is
/// rejected as `Empty("body")`.
///
/// Routes through the shared `is_visually_empty` helper so a 50KB
/// body of `\u{200B}\u{FEFF}\u{202E}…` repeats can't pass every gate
/// while rendering as nothing in the UI. Without that check, the
/// length cap alone would let a body that's invisible everywhere
/// burn the per-task body budget — the same hazard
/// `validate_title` guards against.
pub fn validate_body(body: &str) -> Result<(), ValidationError> {
    if body.is_empty() {
        return Ok(());
    }
    let (visually_empty, char_count) = measure_visibility_and_length(body);
    if char_count > MAX_BODY_LENGTH {
        return Err(ValidationError::TooLong {
            field: "body",
            max: MAX_BODY_LENGTH,
            actual: char_count,
        });
    }
    // Empty body is legal — the task simply has no narrative — but
    // a body that is non-empty in raw bytes yet visually empty after
    // stripping invisible codepoints is rejected so the on-disk
    // budget can't be burned on padding that no surface ever
    // displays.
    if visually_empty {
        return Err(ValidationError::Empty("body"));
    }
    Ok(())
}

/// Validate that an arbitrary string field does not exceed `max`
/// Unicode codepoints. Returns a typed
/// [`ValidationError::TooLong`] on overflow so caller surfaces (MCP,
/// Tauri, CLI) format their own wording — but the discriminant set
/// is shared.
///
/// The string-length call sites in Tauri validation
/// (`app/src-tauri/src/invariants/validation/mod.rs` and
/// `app/src-tauri/src/commands/habits/queries/writes.rs`) plus MCP task
/// validation (`mcp-server/src/tasks/validation.rs`) all route through this
/// helper so the wording never drifts. Hand-formatting an
/// `Err({Mcp,App}Error::Validation(format!("{field} exceeds maximum
/// length ({n} chars, limit {max})")))` per surface leaves the
/// wording free to diverge. The callers convert `ValidationError`
/// to their crate-local error
/// variant via the `From` impls already in place.
pub fn validate_string_length(
    value: &str,
    field: &'static str,
    max: usize,
) -> Result<(), ValidationError> {
    let char_count = value.chars().count();
    if char_count > max {
        return Err(ValidationError::TooLong {
            field,
            max,
            actual: char_count,
        });
    }
    Ok(())
}

/// Validate that an optional string field, if present, does not
/// exceed `max` Unicode codepoints. Triple-declared
/// shadow of [`validate_string_length`] for `Option<&str>` fields —
/// see that function's note.
pub fn validate_optional_string_length(
    value: Option<&str>,
    field: &'static str,
    max: usize,
) -> Result<(), ValidationError> {
    if let Some(v) = value {
        validate_string_length(v, field, max)?;
    }
    Ok(())
}

/// Validate a tag display name: must be non-empty and within
/// [`MAX_TAG_NAME_LENGTH`] Unicode codepoints. Also
/// rejects names that are visually empty after stripping zero-width
/// / bidi / control codepoints (same hazard `validate_title` was
/// hardened against in #2962-M4).
pub fn validate_tag_name(name: &str) -> Result<(), ValidationError> {
    let (visually_empty, char_count) = measure_visibility_and_length(name);
    if visually_empty {
        return Err(ValidationError::Empty("tag_name"));
    }
    if char_count > MAX_TAG_NAME_LENGTH {
        return Err(ValidationError::TooLong {
            field: "tag_name",
            max: MAX_TAG_NAME_LENGTH,
            actual: char_count,
        });
    }
    Ok(())
}
