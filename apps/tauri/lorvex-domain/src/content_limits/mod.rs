//! Centralised byte-length caps for user-authored free-text aggregates.
//!
//! These limits are the single source of truth for every write boundary
//! (Tauri UI commands, MCP write handlers, sync-apply inbound) so the
//! app, the MCP server, and peer devices all refuse — or clamp — the
//! same inputs. Keeping the value in `lorvex-domain` means the sync
//! layer, the storage layer, and the UI layer can all reference the
//! constant without pulling in each other's dependencies.
//!
/// Outcome of [`clamp_to_byte_limit`].
///
/// The discriminated-union shape forces every consumer to handle the
/// truncated case explicitly — a flat `(String, bool)` return would
/// let a caller destructure `(content, _)` and silently land an
/// oversize-then-truncated payload in SQLite without a single trace
/// in the conflict log, reintroducing the failure mode the cap
/// exists to detect. The typed payload also exposes `dropped_bytes`
/// because the apply pipeline needs to log the magnitude of the drop
/// for diagnostic surfaces.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClampOutcome {
    /// The input was already within the byte cap. The wrapped value is
    /// `content.to_string()`.
    Untouched(String),
    /// The input exceeded the cap and was truncated to the longest
    /// char-boundary-safe prefix that fits under `max_bytes`.
    Truncated {
        /// The clamped value; always valid UTF-8 and `<= max_bytes`.
        value: String,
        /// How many bytes the truncation dropped from the input. Equal
        /// to `original_byte_len - value.len()` (always strictly
        /// positive on the truncated arm because the let-else for
        /// `Untouched` already filtered the equal-length case).
        dropped_bytes: usize,
    },
}

impl ClampOutcome {
    /// Return the (possibly clamped) string value regardless of arm.
    /// Most callers want both the value and the truncation signal —
    /// for those, match the enum directly. This accessor exists for
    /// the narrow callers that only need the bytes (e.g. logging the
    /// final stored content).
    pub fn into_value(self) -> String {
        match self {
            ClampOutcome::Untouched(value) | ClampOutcome::Truncated { value, .. } => value,
        }
    }

    /// Borrow the value without consuming the outcome.
    pub fn value(&self) -> &str {
        match self {
            ClampOutcome::Untouched(value) | ClampOutcome::Truncated { value, .. } => {
                value.as_str()
            }
        }
    }

    /// `true` when the input exceeded the cap and was truncated.
    pub const fn was_truncated(&self) -> bool {
        matches!(self, ClampOutcome::Truncated { .. })
    }
}

/// Truncate `content` so its UTF-8 byte length is `<= max_bytes`
/// without splitting a multi-byte codepoint.
///
/// Returns a [`ClampOutcome`] discriminating the
/// already-within-cap path from the truncated path so callers cannot
/// silently drop the truncation signal — see #3004 M7 for the
/// motivation.
///
/// The invariant we preserve: the output is always valid UTF-8 and is
/// the longest prefix of `content` that fits under the byte cap. We
/// walk back from the raw byte cutoff until the next byte is a char
/// boundary, which for UTF-8 is any byte whose leading bits are not
/// `10` (continuation bytes).
pub fn clamp_to_byte_limit(content: &str, max_bytes: usize) -> ClampOutcome {
    let original_len = content.len();
    if original_len <= max_bytes {
        return ClampOutcome::Untouched(content.to_string());
    }
    // Walk back from `max_bytes` to the nearest char boundary.
    let mut cut = max_bytes;
    while cut > 0 && !content.is_char_boundary(cut) {
        cut -= 1;
    }
    let value = content[..cut].to_string();
    let dropped_bytes = original_len - value.len();
    ClampOutcome::Truncated {
        value,
        dropped_bytes,
    }
}

#[cfg(test)]
mod tests;
