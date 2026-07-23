//! Payload canonicalization for deterministic sync envelopes.
//!
//! Guarantees that two structurally identical JSON payloads — regardless of
//! original key order or whitespace — produce byte-identical output.
//!
//! Rules:
//! - Object keys sorted alphabetically (recursive)
//! - Compact format (no extra spaces, no trailing whitespace)
//!
//! **Does NOT rewrite string values.** User content (task titles, body text,
//! notes) survives byte-for-byte. Unicode normalization (NFC/NFKC) is applied
//! only to specific machine-comparable fields via their own normalization
//! functions (e.g., tag `lookup_key` via `normalize_lookup_key()`).
//!
//! ## serde_json default-features contract (locked)
//!
//! every site in this crate that re-serializes a
//! `serde_json::Value` for wire emission MUST go through
//! [`canonicalize_json`] rather than calling `serde_json::to_string`
//! directly. The two paths happen to produce identical output today
//! ONLY because `serde_json::Map` is a `BTreeMap` alias when the
//! `preserve_order` feature is OFF — i.e. the workspace
//! `serde_json = "1"` declaration in the root `Cargo.toml` keeps
//! default features ON and `preserve_order` OFF. If a downstream
//! consumer (or this workspace) ever flips `preserve_order` on (a
//! transitive feature unification can do this without touching
//! `Cargo.toml` directly), `serde_json::to_string` would start
//! emitting keys in insertion order instead of sorted order, silently
//! breaking content-addressed dedupe between every existing
//! payload-shadow row, every coalesced outbox envelope, and every
//! peer's pre-merge canonical form.
//!
//! Routing through `canonicalize_json` removes the dependency on the
//! `Map` representation: this writer sorts keys explicitly via
//! `Vec::sort_unstable_by` regardless of which map type backs `Value`.
//! Treat `serde_json` default-features ON as a hard contract for this
//! crate.
//!
//! See spec Section 5: Payload Canonicalization.

use serde_json::Value;
use std::fmt;

/// Maximum allowed nesting depth for a canonicalized JSON value.
///
/// Re-exports `lorvex_domain::canonical_json::MAX_JSON_DEPTH` so the
/// wire-side wrapper and the in-process domain serializer share one
/// constant. Bumping one without the other would let a payload pass
/// the store-side encoder and fail the wire-side encoder, or vice
/// versa.
pub const MAX_JSON_DEPTH: usize = lorvex_domain::canonical_json::MAX_JSON_DEPTH;

/// Maximum allowed byte size for a canonicalized JSON envelope.
///
/// depth-only protection guards the stack but not the
/// heap or the disk. Without a byte cap, a malicious peer could push
/// a single 100MB string, a million flat keys, or a wide array
/// through `canonicalize_json`. The result lands in
/// `sync_payload_shadow`, `sync_pending_inbox`, and `sync_outbox`,
/// where the LWW preservation guarantee keeps it forever.
///
/// re-exports the canonical
/// `lorvex_domain::storage_schema::MAX_PAYLOAD_BYTES` so the
/// canonicalize gate and the shadow writer
/// (`lorvex_sync_payload::payload_shadow`) share one source of truth.
pub const MAX_CANONICAL_PAYLOAD_BYTES: usize = lorvex_domain::storage_schema::MAX_PAYLOAD_BYTES;

/// Errors returned by canonicalization.
#[derive(Debug)]
pub enum CanonError {
    /// The input JSON is nested deeper than [`MAX_JSON_DEPTH`].
    DepthExceeded,
    /// The canonicalized output is larger than [`MAX_CANONICAL_PAYLOAD_BYTES`].
    PayloadTooLarge {
        /// Size of the canonicalized output in bytes.
        size_bytes: usize,
    },
}

impl fmt::Display for CanonError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CanonError::DepthExceeded => {
                write!(f, "JSON nesting exceeds maximum depth of {MAX_JSON_DEPTH}")
            }
            CanonError::PayloadTooLarge { size_bytes } => {
                write!(
                    f,
                    "canonicalized payload is {size_bytes} bytes; \
                     exceeds maximum of {MAX_CANONICAL_PAYLOAD_BYTES} bytes"
                )
            }
        }
    }
}

impl std::error::Error for CanonError {}

/// Canonicalize a JSON value: sorted keys, compact format.
///
/// String values are preserved byte-for-byte — no NFC or other Unicode
/// normalization is applied to user content.
///
/// Returns [`CanonError::DepthExceeded`] if `value` is nested deeper than
/// [`MAX_JSON_DEPTH`] — this guards against stack-overflow DoS from
/// maliciously crafted sync envelopes. Returns
/// [`CanonError::PayloadTooLarge`] if the serialized output exceeds
/// [`MAX_CANONICAL_PAYLOAD_BYTES`] (#2860).
///
/// the underlying writer (sorted-key streaming serializer
/// with serde_json-parity escape table) lives in
/// [`lorvex_domain::canonical_json::canonicalize_json`]. This wrapper
/// delegates to it and adds the wire-envelope payload-size cap
/// (`MAX_CANONICAL_PAYLOAD_BYTES`).
/// byte-duplicated across the two crates (~100 LOC including the JSON
/// escape table); any drift in the escape choices would silently
/// corrupt content-addressed dedupe between every existing
/// `sync_payload_shadow` row, every coalesced outbox envelope, and
/// every peer's pre-merge canonical form.
pub fn canonicalize_json(value: &Value) -> Result<String, CanonError> {
    let out = lorvex_domain::canonical_json::canonicalize_json(value).map_err(|err| match err {
        lorvex_domain::canonical_json::CanonError::DepthExceeded => CanonError::DepthExceeded,
    })?;
    if out.len() > MAX_CANONICAL_PAYLOAD_BYTES {
        return Err(CanonError::PayloadTooLarge {
            size_bytes: out.len(),
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests;
