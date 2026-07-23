//! Forward-compat payload shadow subsystem.
//!
//! The shadow row preserves unknown JSON keys across LWW conflicts and
//! re-emits, so a peer running a newer schema can carry forward-compat
//! fields through a network of older peers without losing them. This
//! module hosts the shared types, size guard, and parsing helpers; the
//! actual CRUD primitives live in [`crud`] and the merge / redirect
//! logic lives in [`merge`].

use crate::error::PayloadError;
use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::EntityKind;
use serde::{Deserialize, Serialize};

mod crud;
mod merge;
mod owned_keys;
#[cfg(test)]
mod tests;

pub use crud::{
    get_shadow, list_shadows, remove_shadow, remove_shadow_if_superseded, restore_shadow,
    upsert_shadow,
};
pub use merge::{
    merge_payload_with_shadow, merge_payload_with_shadow_indexed, merge_shadow_into_redirect,
    ShadowIndex,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PayloadShadowRow {
    pub entity_type: EntityKind,
    pub entity_id: String,
    pub base_version: String,
    pub payload_schema_version: u32,
    pub raw_payload_json: String,
    /// original device_id from the envelope that
    /// preserved this shadow. Replayed verbatim by
    /// `promote_payload_shadows` so any conflict_log entry written
    /// during promotion attributes truncation / LWW losses to the
    /// real peer instead of the synthetic `"shadow-promotion"`
    /// string the previous code wrote into that column. Empty
    /// string for legacy rows that pre-date the column or for
    /// import archives produced before this field was tracked.
    #[serde(default)]
    pub source_device_id: String,
    pub updated_at: String,
}

/// Maximum allowed byte size for a `raw_payload_json` written to
/// `sync_payload_shadow`. Defense-in-depth (#2860): a peer running a
/// future schema version can stash arbitrary forward-compat fields
/// in the shadow row. The shadow row is preserved across LWW
/// conflict resolution and survives restarts, so an unbounded write
/// would pin disk + memory indefinitely.
///
/// re-exports the canonical
/// `lorvex_domain::storage_schema::MAX_PAYLOAD_BYTES` constant so the
/// canonicalize gate (`lorvex_sync::canonicalize`) and the shadow writer
/// (this module) share one source of truth.
pub const MAX_RAW_PAYLOAD_JSON_BYTES: usize = lorvex_domain::storage_schema::MAX_PAYLOAD_BYTES;

/// Shared size validator for `raw_payload_json`. Every writer entry
/// — including the import path's `restore_shadow` — must enforce the
/// same defense-in-depth cap. If only `upsert_shadow` checked,
/// `restore_shadow` (called by `apply_payload_shadows` during
/// import) would accept an arbitrarily large field-level payload,
/// and a single 50 MB `payload_shadows.jsonl` line could pin disk
/// and page-cache memory until horizon GC.
pub(super) fn validate_raw_payload_size(
    entity_type: &str,
    entity_id: &str,
    raw_payload_json: &str,
) -> Result<(), PayloadError> {
    if raw_payload_json.len() > MAX_RAW_PAYLOAD_JSON_BYTES {
        return Err(PayloadError::Validation(format!(
            "sync_payload_shadow raw_payload_json for {entity_type}:{entity_id} \
             is {} bytes; exceeds maximum of {MAX_RAW_PAYLOAD_JSON_BYTES} bytes",
            raw_payload_json.len()
        )));
    }
    Ok(())
}

pub(super) fn parse_hlc(version: &str, context: &str) -> Result<Hlc, PayloadError> {
    Hlc::parse(version)
        .map_err(|_| PayloadError::Validation(format!("invalid HLC in {context}: {version}")))
}
