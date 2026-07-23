//! Shared HLC successor minting for apply-side merge operations.

use lorvex_domain::hlc::{Hlc, MAX_HLC_PHYSICAL_MS};
use lorvex_domain::hlc_state::MAX_COUNTER;

use super::ApplyError;

/// Mint the smallest canonical HLC that strictly dominates `max_hlc`.
///
/// Merge handlers stamp locally-authored tombstones and re-pointed child rows
/// with a version above every participant. That successor is not always
/// representable: once a participant is already at the canonical physical-ms
/// ceiling with the maximum counter, there is no valid HLC above it.
pub(crate) fn mint_merge_hlc_after(
    max_hlc: &Hlc,
    merge_suffix: &str,
    context: &str,
) -> Result<Hlc, ApplyError> {
    let candidate = if max_hlc.counter() < MAX_COUNTER {
        Hlc::new(max_hlc.physical_ms(), max_hlc.counter() + 1, merge_suffix)
    } else if max_hlc.physical_ms() < MAX_HLC_PHYSICAL_MS {
        Hlc::new(max_hlc.physical_ms() + 1, 0, merge_suffix)
    } else {
        return Err(ApplyError::InvalidVersion(format!(
            "{context}: no canonical HLC successor exists after {max_hlc}"
        )));
    };

    candidate.map_err(|e| {
        ApplyError::InvalidVersion(format!(
            "{context}: minted merge_version with invalid merge device suffix: {e}"
        ))
    })
}

#[cfg(test)]
mod tests;
