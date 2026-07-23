//! Stable, deterministic per-attendee identity for the
//! `calendar_event_attendees` / `calendar_event_attendee_shadow` sub-tables.
//!
//! Attendees are children of the `calendar_event` aggregate — never synced on
//! their own, always re-materialized (DELETE + re-INSERT) from the event's
//! embedded `attendees[]` array. They therefore need a *local* key that is
//! identical whenever two devices materialize the same array, and stable when
//! the same event is re-materialized. RFC 5545 keys an ATTENDEE by its
//! CAL-ADDRESS (an email-like URI); Lorvex relaxes the empty-email case (a
//! name-only attendee must no longer drop the whole event) by falling back to
//! the display name, then to a hash of the attendee's canonical content.
//!
//! Identity precedence:
//!   1. non-empty email        → `email:` + the normalized email
//!   2. else non-empty name    → `name:`  + the lowercased/trimmed name
//!   3. else (fully anonymous) → `anon:`  + the first 8 bytes of the SHA-256
//!      digest of the attendee's canonical JSON, as 16 lowercase hex chars
//!
//! Every case is content-derived, so the id is byte-identical across devices
//! and stable across a write → read → re-write round-trip. The outbound array
//! is emitted `ORDER BY attendee_id`, so an anonymous attendee's array index
//! shifts whenever a keyed peer sorts around it; keying on canonical content
//! instead of index keeps its identity invariant under that reorder. Two
//! byte-identical anonymous attendees collapse onto one id — the
//! `(event_id, attendee_id)` primary key deduplicates them on insert.
//! `attendee_id` is a device-local key, never emitted on the wire; each peer
//! re-synthesizes it from the array it receives.
//!
//! This mirrors the Apple app's `LorvexDomain.AttendeeIdentity` byte-for-byte
//! so the two implementations converge on identical device-local ids.

use serde_json::{Map, Value};
use sha2::{Digest, Sha256};

use crate::canonical_json::canonicalize_json;

/// Synthesize the `attendee_id` key.
///
/// `normalized_email` MUST already be trimmed + lowercased by the caller (both
/// the sync-apply and local-materialization paths lowercase/trim the email as
/// their collision key, so the id matches their existing normalization).
/// `name` is the display name (any casing); it is lowercased + trimmed here.
/// `canonical_json` is the attendee entry's canonical JSON, evaluated only for
/// the fully-anonymous fallback (no email AND no name) and hashed into the
/// content-stable `anon:` key; keyed attendees ignore it (callers may pass
/// `""`).
pub fn synthesize(normalized_email: &str, name: Option<&str>, canonical_json: &str) -> String {
    if !normalized_email.is_empty() {
        return format!("email:{normalized_email}");
    }
    if let Some(key) = normalized_name_key(name) {
        return format!("name:{key}");
    }
    format!("anon:{}", anon_content_hash(canonical_json))
}

/// Canonical JSON of the *materialized* attendee shape, used as the stable
/// content basis for the fully-anonymous [`synthesize`] fallback.
///
/// The surplus `extras` map, then the known columns `email` (always present),
/// `name` and `status` (each `null` when absent). Because the outbound array
/// re-emits every attendee in exactly this shape, an attendee's basis is
/// identical whether it arrives as the original wire object (which may omit
/// `name` / `status`) or as the re-materialized form (which spells them as
/// `null`), so the `anon:` id does not churn across a round-trip. Mirrors the
/// Apple app's `anonymousIdentityBasis`.
pub fn anonymous_identity_basis(
    email: &str,
    name: Option<&str>,
    status: Option<&str>,
    extras: Option<&Map<String, Value>>,
) -> String {
    let mut obj: Map<String, Value> = extras.cloned().unwrap_or_default();
    obj.insert("email".to_string(), Value::String(email.to_string()));
    obj.insert(
        "name".to_string(),
        name.map_or(Value::Null, |n| Value::String(n.to_string())),
    );
    obj.insert(
        "status".to_string(),
        status.map_or(Value::Null, |s| Value::String(s.to_string())),
    );
    // Small, flat object: canonicalization cannot exceed the depth/size caps.
    canonicalize_json(&Value::Object(obj)).unwrap_or_default()
}

/// First 8 bytes of the SHA-256 digest of `canonical_json`, as 16 lowercase
/// hex characters — the content-stable anonymous-attendee key body.
fn anon_content_hash(canonical_json: &str) -> String {
    let digest = Sha256::digest(canonical_json.as_bytes());
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut hex = String::with_capacity(16);
    for &byte in digest.iter().take(8) {
        hex.push(HEX[(byte >> 4) as usize] as char);
        hex.push(HEX[(byte & 0x0f) as usize] as char);
    }
    hex
}

/// Trim (Unicode whitespace) + lowercase a display name into its identity key,
/// or `None` when nothing identifying remains.
fn normalized_name_key(name: Option<&str>) -> Option<String> {
    let name = name?;
    let trimmed = name.trim().to_lowercase();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn email_takes_precedence() {
        assert_eq!(
            synthesize("alice@example.com", Some("Alice"), ""),
            "email:alice@example.com"
        );
    }

    #[test]
    fn name_fallback_when_email_empty() {
        assert_eq!(synthesize("", Some("  Bob Smith "), ""), "name:bob smith");
    }

    #[test]
    fn anonymous_fallback_is_stable_content_hash() {
        let basis = anonymous_identity_basis("", None, None, None);
        let id = synthesize("", None, &basis);
        assert!(id.starts_with("anon:"));
        assert_eq!(id.len(), "anon:".len() + 16);
        // Deterministic: same content → same id.
        assert_eq!(id, synthesize("", None, &basis));
        // Hex-only body.
        assert!(id["anon:".len()..].chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn whitespace_only_name_is_not_identifying() {
        // An empty/whitespace name with an empty email falls through to anon.
        let basis = anonymous_identity_basis("", Some("   "), None, None);
        assert!(synthesize("", Some("   "), &basis).starts_with("anon:"));
    }

    #[test]
    fn anonymous_basis_matches_materialized_shape() {
        // `null` name/status vs absent must produce the same basis so the id
        // is invariant across a materialize → re-emit round-trip.
        let a = anonymous_identity_basis("", None, None, None);
        let b = anonymous_identity_basis("", None, None, Some(&Map::new()));
        assert_eq!(a, b);
    }
}
