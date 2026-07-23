//! Per-attendee normalization + canonicalization used by the
//! calendar_event upsert handler.
//!
//! Splits the attendee-shaped logic out of `mod.rs` so the
//! upsert handler in `upsert.rs` reads as pure RFC-5545
//! payload validation + SQL upsert. The normalizer enforces the
//! apply-side contract (email present + non-empty, optional name
//! is a string when present, status is a recognized RFC 5545
//! PARTSTAT value), captures forward-compat surplus keys for the
//! attendee shadow round-trip, and produces the canonical-JSON
//! tiebreaker used by email-collision dedupe (issue #2878).

use crate::canonicalize::canonicalize_json;

use super::super::helpers::scrub;
use super::super::ApplyError;

/// One attendee entry parsed and validated against the apply-side
/// contract. `attendee_id` is the synthesized device-local identity
/// (email / name / content-hash — see
/// `lorvex_domain::attendee_identity`) used as the dedupe + shadow
/// key; `email` is the trimmed, lowercased form (possibly empty for a
/// name-only or anonymous attendee); `canonical` is the canonical-JSON
/// serialization of the original entry, used as the deterministic
/// tiebreaker for identity-collision dedupe (issue #2878).
pub(super) struct NormalizedAttendee {
    pub(super) attendee_id: String,
    pub(super) email: String,
    pub(super) name: Option<String>,
    pub(super) status: Option<String>,
    /// Surplus per-attendee keys (`role`, `rsvp_deadline`, ...) that
    /// land in `calendar_event_attendee_shadow` for round-trip via the
    /// re-echo path. `None` when the entry has no surplus keys.
    pub(super) extras: Option<serde_json::Map<String, serde_json::Value>>,
    /// Canonical-JSON serialization of the source entry, used as the
    /// tiebreaker for email-collision dedupe.
    pub(super) canonical: String,
    /// Original JSON of the entry, preserved so the conflict-log
    /// row's `loser_payload` shows the user exactly which entry was
    /// dropped (post-PII-scrub).
    pub(super) raw_json: String,
}

pub(super) fn normalize_attendee(
    att: &serde_json::Value,
    index: usize,
) -> Result<NormalizedAttendee, ApplyError> {
    // Empty / absent / null email all normalize to ""; identity then falls
    // back to the name, then a hash of the entry's canonical JSON (untrusted
    // peer data must never drop the whole event). A non-string email is still
    // a shape error.
    let email_normalized = match att.get("email") {
        None | Some(serde_json::Value::Null) => String::new(),
        Some(serde_json::Value::String(raw)) => raw.trim().to_lowercase(),
        Some(_) => {
            return Err(ApplyError::InvalidPayload(format!(
                "calendar_event payload: attendees[{index}].email must be a string when present"
            )));
        }
    };
    // Unicode hygiene (#2427): attendee display name is free text.
    let name: Option<String> = match att.get("name") {
        None | Some(serde_json::Value::Null) => None,
        Some(value) => Some(scrub(value.as_str().ok_or_else(|| {
            ApplyError::InvalidPayload(format!(
                "calendar_event payload: attendees[{index}].name must be a string when present"
            ))
        })?)),
    };
    // Closing #3946: sync apply accepts the same canonical RFC 5545
    // PARTSTAT subset as the write surfaces and import path. Legacy
    // underscore values such as `needs_action` now fail closed instead
    // of being repaired on read.
    let raw_status: Option<&str> = match att.get("status") {
        None | Some(serde_json::Value::Null) => None,
        Some(value) => Some(value.as_str().ok_or_else(|| {
            ApplyError::InvalidPayload(format!(
                "calendar_event payload: attendees[{index}].status must be a string when present"
            ))
        })?),
    };
    // `parse_strict` returns the typed `AttendeeStatus` enum; we
    // persist the canonical string form via `as_str()`. The schema
    // CHECK is the last byte-level gate, but the closed RFC 5545
    // PARTSTAT subset is decided by the enum at the trust boundary.
    let status: Option<String> = match raw_status {
        None => None,
        Some(raw) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                None
            } else {
                let parsed =
                    lorvex_domain::AttendeeStatus::parse_strict(trimmed).ok_or_else(|| {
                        ApplyError::InvalidPayload(format!(
                            "calendar_event payload: attendees[{index}].status '{raw}' is not \
                         a recognized RFC 5545 PARTSTAT value (expected one of: {})",
                            lorvex_domain::attendee_status_allowlist_display()
                        ))
                    })?;
                Some(parsed.as_str().to_string())
            }
        }
    };
    // Capture surplus fields (everything that is NOT a known attendee
    // key) so we can re-emit them verbatim on the next outbound
    // enqueue. JSON Null is preserved as an explicit "value is null"
    // marker — dropping it would be indistinguishable from "key
    // absent" to a newer peer.
    let extras: Option<serde_json::Map<String, serde_json::Value>> =
        att.as_object().and_then(|obj| {
            let mut extras = serde_json::Map::new();
            for (k, v) in obj {
                if !lorvex_sync_payload::attendee_shadow::KNOWN_ATTENDEE_KEYS.contains(&k.as_str())
                {
                    extras.insert(k.clone(), v.clone());
                }
            }
            if extras.is_empty() {
                None
            } else {
                Some(extras)
            }
        });
    // Canonicalize the entry — sorted keys, compact format — so the
    // email-collision tiebreaker compares byte-stable forms.
    //
    // Critical detail: build the canonical form from a *normalized*
    // copy of the entry where the `email` field is replaced by the
    // already-trimmed/lowercased form. Two colliding entries differ
    // *by definition* in their pre-normalized email casing — if the
    // sort key embeds the raw email, the casing ALONE decides the
    // winner ('A' < 'a' at the byte level), which leaks raw wire
    // representation into the policy. Substituting the normalized
    // email makes the colliding entries truly comparable on their
    // remaining content.
    //
    // canonicalize_json may reject deeply-nested or oversize values
    // with the same envelope-trust-boundary semantics the rest of the
    // sync pipeline uses; surface that as InvalidPayload so a
    // pathological peer can't poison the collision sort.
    let mut canonical_source = att.clone();
    if let Some(obj) = canonical_source.as_object_mut() {
        obj.insert(
            "email".to_string(),
            serde_json::Value::String(email_normalized.clone()),
        );
    }
    let canonical = canonicalize_json(&canonical_source).map_err(|e| {
        ApplyError::InvalidPayload(format!(
            "calendar_event payload: attendees[{index}] failed canonicalization: {e}"
        ))
    })?;
    let raw_json = serde_json::to_string(att)
        .expect("serde_json::Value always serializes to a String successfully");
    // Synthesize the device-local identity. The anonymous content-hash basis
    // (built from the *materialized* shape — email + name/null + status/null +
    // surplus extras) is only evaluated for the fully-anonymous fallback; a
    // keyed attendee (email or name present) never hashes it.
    let attendee_id = if email_normalized.is_empty() && name.is_none() {
        let basis = lorvex_domain::attendee_identity::anonymous_identity_basis(
            &email_normalized,
            name.as_deref(),
            status.as_deref(),
            extras.as_ref(),
        );
        lorvex_domain::attendee_identity::synthesize(&email_normalized, name.as_deref(), &basis)
    } else {
        lorvex_domain::attendee_identity::synthesize(&email_normalized, name.as_deref(), "")
    };
    Ok(NormalizedAttendee {
        attendee_id,
        email: email_normalized,
        name,
        status,
        extras,
        canonical,
        raw_json,
    })
}
