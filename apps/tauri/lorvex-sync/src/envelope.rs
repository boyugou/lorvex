use serde::{Deserialize, Serialize};

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::EntityKind;
use lorvex_domain::validation::ValidationError;
use lorvex_domain::version::PAYLOAD_SCHEMA_VERSION;

/// Maximum size of the canonicalized JSON payload inside a single
/// envelope. The biggest legitimate payload is a full task aggregate
/// with long body + notes + many checklist items + many reminders,
/// which fits comfortably in a few hundred KiB. Anything bigger is
/// treated as malformed.
pub const MAX_ENVELOPE_PAYLOAD_BYTES: usize = 1024 * 1024;

/// Maximum JSON nesting depth permitted in a payload.
///
/// The apply pipeline calls `serde_json::from_str::<Value>` at 20+
/// sites. `serde_json` defaults to a 128-level recursion budget, but
/// the byte cap (`MAX_ENVELOPE_PAYLOAD_BYTES`) only mitigates depth
/// bombs indirectly — a 1 MiB payload of pure `[[[[...]]]]` reaches
/// several hundred thousand frames, far past 128. Asserting depth at
/// the envelope boundary keeps every downstream parse inside a
/// single, predictable budget.
///
/// Re-exports `lorvex_domain::canonical_json::MAX_JSON_DEPTH` so the
/// envelope-validate gate and the canonicalize-emit gate share one
/// constant. A wider cap on the envelope side would let a payload
/// pass envelope validation but fail when re-emitted through
/// `canonicalize_json` on the next outbox enqueue, surfacing as a
/// flapping outbox row.
pub const MAX_JSON_DEPTH: usize = lorvex_domain::canonical_json::MAX_JSON_DEPTH;
/// Maximum length of an entity_type string.
const MAX_ENVELOPE_ENTITY_TYPE_LEN: usize = 128;
/// Maximum length of an entity_id string (UUIDv7 is 36 chars;
/// composite keys like `task_id:tag_id` are ~73).
const MAX_ENVELOPE_ENTITY_ID_LEN: usize = 256;
/// Maximum length of an HLC version string (canonical form is 34 chars
/// including separators; we allow headroom).
const MAX_ENVELOPE_VERSION_LEN: usize = 128;
/// Maximum length of a device_id string (suffix is 8 chars hex; the
/// full identity carried on the wire is the 36-char UUIDv7-style value
/// produced by `get_or_create_device_id`).
pub const MAX_ENVELOPE_DEVICE_ID_LEN: usize = 128;
/// forward-compat headroom for `payload_schema_version`.
/// `validate()` rejects envelopes whose declared schema version is
/// further ahead than `PAYLOAD_SCHEMA_VERSION + MAX_PAYLOAD_SCHEMA_VERSION_AHEAD`.
///
/// Without this cap a peer (or an audit / replay tool re-feeding raw
/// bytes) could send `payload_schema_version: u32::MAX`, which the
/// `apply` pipeline's "version too far ahead" branch routes into
/// `sync_pending_inbox` where it sits and consumes
/// `MAX_PENDING_INBOX_ATTEMPTS = 50` retries — forever. 100 is well
/// past any plausible legitimate forward jump (the version bumps by 1
/// per breaking payload change) while staying short enough that
/// malformed envelopes are rejected at the envelope boundary instead
/// of poisoning the inbox for the full retention horizon.
pub const MAX_PAYLOAD_SCHEMA_VERSION_AHEAD: u32 = 100;

/// Validation error produced by [`SyncEnvelope::validate`].
#[derive(Debug, Clone)]
pub enum EnvelopeValidationError {
    EmptyField {
        field: &'static str,
    },
    FieldTooLong {
        field: &'static str,
        len: usize,
        max: usize,
    },
    UnsafeEntityId {
        entity_id: String,
        reason: &'static str,
    },
    /// `payload_schema_version` is further ahead of the
    /// local build than [`MAX_PAYLOAD_SCHEMA_VERSION_AHEAD`] permits.
    PayloadSchemaVersionTooFarAhead {
        version: u32,
        local_max: u32,
    },
    /// Payload JSON exceeds [`MAX_JSON_DEPTH`] nesting. The byte cap
    /// doesn't bound depth on its own — a stream of `[[[...]]]` of any
    /// non-trivial size hits serde_json's 128-frame default before the
    /// 1 MiB byte cap fires. Reject at the boundary so the apply
    /// pipeline's 20+ `from_str::<Value>` sites all run inside a
    /// predictable budget.
    PayloadJsonTooDeep {
        depth: usize,
        max: usize,
    },
}

impl std::fmt::Display for EnvelopeValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EnvelopeValidationError::EmptyField { field } => {
                write!(f, "sync envelope field {field} must not be empty")
            }
            EnvelopeValidationError::FieldTooLong { field, len, max } => {
                write!(f, "sync envelope field {field} exceeds cap: {len} > {max}")
            }
            EnvelopeValidationError::UnsafeEntityId { entity_id, reason } => write!(
                f,
                "sync envelope entity_id is unsafe ({reason}): {entity_id:?}"
            ),
            EnvelopeValidationError::PayloadSchemaVersionTooFarAhead { version, local_max } => {
                write!(
                    f,
                    "sync envelope payload_schema_version {version} exceeds local cap \
                 {local_max} (= PAYLOAD_SCHEMA_VERSION + MAX_PAYLOAD_SCHEMA_VERSION_AHEAD)"
                )
            }
            EnvelopeValidationError::PayloadJsonTooDeep { depth, max } => {
                write!(
                    f,
                    "sync envelope payload exceeds JSON nesting cap: depth {depth} > max {max}"
                )
            }
        }
    }
}

/// Scan the JSON payload string for nesting depth without parsing it
/// into a `serde_json::Value`. Counts `{` and `[` openers (skipping
/// those inside string literals) and tracks the maximum stack depth.
/// Returns `Ok(max_depth)` once the string is consumed, or
/// `Err(PayloadJsonTooDeep)` the first time the running depth exceeds
/// `cap`. Linear in `payload.len()`, allocation-free, and runs ahead
/// of any `serde_json::from_str` call.
fn scan_max_json_depth(payload: &str, cap: usize) -> Result<usize, EnvelopeValidationError> {
    let mut depth: usize = 0;
    let mut max: usize = 0;
    let mut in_string = false;
    let mut prev_was_backslash = false;
    for byte in payload.bytes() {
        if in_string {
            if prev_was_backslash {
                prev_was_backslash = false;
            } else if byte == b'\\' {
                prev_was_backslash = true;
            } else if byte == b'"' {
                in_string = false;
            }
            continue;
        }
        match byte {
            b'"' => in_string = true,
            b'{' | b'[' => {
                depth += 1;
                if depth > max {
                    max = depth;
                }
                if depth > cap {
                    return Err(EnvelopeValidationError::PayloadJsonTooDeep { depth, max: cap });
                }
            }
            b'}' | b']' => {
                depth = depth.saturating_sub(1);
            }
            _ => {}
        }
    }
    Ok(max)
}

/// reject entity_ids that carry path-traversal sequences
/// or control bytes. Applied at the envelope boundary so every
/// transport-ingested envelope (filesystem-bridge, remote-provider pull)
/// drops the payload before it reaches the apply pipeline. Legacy
/// UUIDs and composite edge ids (e.g. `task_id:tag_id`) are unaffected.
fn reject_unsafe_entity_id(entity_id: &str) -> Result<(), EnvelopeValidationError> {
    if entity_id.contains("..") {
        return Err(EnvelopeValidationError::UnsafeEntityId {
            entity_id: entity_id.to_string(),
            reason: "contains path-traversal sequence '..'",
        });
    }
    if entity_id.contains('/') || entity_id.contains('\\') {
        return Err(EnvelopeValidationError::UnsafeEntityId {
            entity_id: entity_id.to_string(),
            reason: "contains path separator",
        });
    }
    if entity_id.chars().any(char::is_control) {
        return Err(EnvelopeValidationError::UnsafeEntityId {
            entity_id: entity_id.to_string(),
            reason: "contains control character",
        });
    }
    // Rust's `char::is_control` derives from the Unicode general
    // category `Cc`, which excludes U+2028 LINE SEPARATOR and U+2029
    // PARAGRAPH SEPARATOR even though both routinely break naive
    // line-oriented JSON parsers (and break `JSON.parse` on legacy V8
    // builds). Reject explicitly so a remote-provider / filesystem-bridge
    // envelope can't smuggle them through. Same defensive posture as
    // the path-traversal and control-byte arms above.
    if entity_id
        .chars()
        .any(|c| c == '\u{2028}' || c == '\u{2029}')
    {
        return Err(EnvelopeValidationError::UnsafeEntityId {
            entity_id: entity_id.to_string(),
            reason: "contains line/paragraph separator (U+2028/U+2029)",
        });
    }
    Ok(())
}

const fn canonical_entity_id_validation_reason(error: &ValidationError) -> &'static str {
    match error {
        ValidationError::InvalidFormat { expected, .. } => expected,
        ValidationError::Empty(_) => "must not be empty",
        ValidationError::TooLong { .. } => "exceeds canonical entity_id length",
        ValidationError::OutOfRange { .. } | ValidationError::Message(_) => {
            "failed canonical entity_id validation"
        }
    }
}

fn reject_noncanonical_entity_id(
    kind: EntityKind,
    entity_id: &str,
) -> Result<(), EnvelopeValidationError> {
    lorvex_domain::validate_sync_entity_id_for_kind(kind, entity_id).map_err(|error| {
        EnvelopeValidationError::UnsafeEntityId {
            entity_id: entity_id.to_string(),
            reason: canonical_entity_id_validation_reason(&error),
        }
    })
}

impl std::error::Error for EnvelopeValidationError {}

/// Unified sync envelope — the wire format for all sync transport.
/// See spec Section 5: Root Sync Model & Merge Rules.
///
/// NO `#[serde(deny_unknown_fields)]`. Any future
/// envelope-level additive field (signature, compression hint, inline
/// blob, causal predecessor, TTL) must be deserializable by today's
/// peers — otherwise `check_envelope_version` (the entire
/// payload-schema-version forward-compat machinery) never gets to
/// run, because serde rejects the envelope before it reaches us.
/// Forward-compat at the *envelope* level means: accept unknown
/// fields, ignore them, preserve behavior driven by known fields.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncEnvelope {
    /// Canonical entity type from the naming registry.
    ///
    /// Classified by serde at the wire boundary. `EntityKind`'s
    /// `#[serde(rename = "...")]` representation emits the canonical
    /// lowercase snake_case form, so the wire format is byte-stable
    /// across releases and every reader inside the process gets the
    /// typed enum without re-parsing. Forward-compat with future
    /// entity kinds is preserved: deserialization of an unknown
    /// variant fails at the envelope boundary, which is the same
    /// place `validate()` rejects oversized/empty payloads.
    pub entity_type: EntityKind,
    /// Stable identity (UUIDv7 string or natural key).
    pub entity_id: String,
    /// Whether this is an upsert or delete.
    pub operation: SyncOperation,
    /// HLC value — the authoritative merge truth. Per-row, sortable
    /// lex-by-canonical-string-form; LWW comparisons in `apply` use this.
    ///
    /// Typed at the wire boundary. `Hlc`'s `Serialize`/`Deserialize`
    /// impls (see `lorvex_domain::hlc`) emit and accept the canonical
    /// zero-padded string form, so the wire format is byte-stable
    /// across releases. Serde owns the "is this a well-formed HLC"
    /// check, so every reader inside the process gets a typed `Hlc`
    /// without re-parsing. Storage rows continue to hold `TEXT`
    /// strings; the conversion happens at the rusqlite bind site
    /// (`.to_string()`) and at row-read time (`Hlc::parse`).
    ///
    /// this is the `sync_outbox.version` (TEXT) column
    /// and is **not** the same thing as `payload_schema_version` below
    /// despite both having "version" in their name. They answer
    /// different questions: this answers "which write wins this row?"
    /// while `payload_schema_version` answers "can my apply pipeline
    /// parse this envelope?". Don't fold one into the other on read
    /// and don't compare them with the same operators. The schema-side
    /// disambiguation lives next to the `sync_outbox` table definition.
    pub version: Hlc,
    /// Envelope-format generation tag. Receiver checks compatibility
    /// against `lorvex_sync::envelope::PAYLOAD_SCHEMA_VERSION`.
    ///
    /// this is the `sync_outbox.payload_schema_version`
    /// (INTEGER) column and is **not** the same thing as `version`
    /// above. It bumps once per cross-cutting schema migration, not
    /// per write — every row produced under the same migration carries
    /// the same value here. See the `version` field doc above for the
    /// full disambiguation.
    pub payload_schema_version: u32,
    /// Canonicalized JSON payload (sorted keys, deterministic).
    pub payload: String,
    /// Source device identifier.
    pub device_id: String,
}

impl SyncEnvelope {
    /// Validate per-field caps and non-empty invariants. The transport
    /// layer (filesystem-bridge, remote providers) must call this on every
    /// incoming envelope before any further processing — otherwise a
    /// 200 MB `payload` or 10 MB `device_id` from a crafted file can
    /// OOM or stall the pipeline. Callers that accept in-process
    /// envelopes (from their own enqueue path) can skip validation
    /// since the shape is controlled locally.
    pub fn validate(&self) -> Result<(), EnvelopeValidationError> {
        const fn cap(
            field: &'static str,
            value: &str,
            max: usize,
        ) -> Result<(), EnvelopeValidationError> {
            if value.is_empty() {
                Err(EnvelopeValidationError::EmptyField { field })
            } else if value.len() > max {
                Err(EnvelopeValidationError::FieldTooLong {
                    field,
                    len: value.len(),
                    max,
                })
            } else {
                Ok(())
            }
        }

        // with `entity_type: EntityKind`, the wire-side
        // length and emptiness invariants are enforced by serde — an
        // empty or oversized entity_type cannot deserialize into the
        // closed enum. The cap is retained here as a defense-in-depth
        // assertion against future variant additions whose canonical
        // string exceeds the cap (currently no canonical name comes
        // close — the longest is `task_calendar_event_link` at 24
        // chars vs the 128-char cap).
        cap(
            "entity_type",
            self.entity_type.as_str(),
            MAX_ENVELOPE_ENTITY_TYPE_LEN,
        )?;
        cap("entity_id", &self.entity_id, MAX_ENVELOPE_ENTITY_ID_LEN)?;
        // entity_id is rejected if it carries path-traversal
        // sequences (`..`), path separators (`/` / `\`), or control
        // bytes — a crafted record_name with any of those would
        // otherwise round-trip through the sync apply path. The check
        // runs at the envelope boundary for every filesystem-bridge
        // and provider-ingested envelope per the `validate()`
        // contract. UUIDs and composite edge ids (e.g.
        // `task_id:tag_id`) are unaffected since the colon is the
        // canonical edge separator and composite ids are split AFTER
        // this check.
        reject_unsafe_entity_id(&self.entity_id)?;
        reject_noncanonical_entity_id(self.entity_type, &self.entity_id)?;
        // with `version: Hlc`, length and shape are
        // enforced by the typed serde deserialization — an empty,
        // oversized, or malformed version cannot deserialize into the
        // closed value type. The cap is retained as defense-in-depth
        // against any future internal constructor that bypasses
        // `Hlc::new`/`Hlc::parse`. Canonical HLC width is 34 chars
        // (13 + 4 + 16 + 2 separators), well under the 128-char cap.
        let version_str = self.version.to_string();
        cap("version", &version_str, MAX_ENVELOPE_VERSION_LEN)?;
        cap("device_id", &self.device_id, MAX_ENVELOPE_DEVICE_ID_LEN)?;
        if self.payload.len() > MAX_ENVELOPE_PAYLOAD_BYTES {
            return Err(EnvelopeValidationError::FieldTooLong {
                field: "payload",
                len: self.payload.len(),
                max: MAX_ENVELOPE_PAYLOAD_BYTES,
            });
        }
        // Assert JSON nesting depth at the boundary so every downstream
        // `from_str::<Value>` in the apply pipeline (day_scoped, edge,
        // child, changelog, tag, blob, aggregate/*) operates inside a
        // single explicit budget. Cheap linear scan.
        scan_max_json_depth(&self.payload, MAX_JSON_DEPTH)?;
        // cap forward-compat headroom on
        // `payload_schema_version`. The `apply` pipeline routes
        // versions ahead of local into `sync_pending_inbox` so a
        // future-build upgrade can drain them; without an upper bound
        // a peer (or a replay tool re-feeding raw bytes) sending
        // `u32::MAX` parks an envelope in the inbox that never
        // resolves and burns `MAX_PENDING_INBOX_ATTEMPTS` retries.
        // Reject at the boundary instead.
        let local_max = PAYLOAD_SCHEMA_VERSION.saturating_add(MAX_PAYLOAD_SCHEMA_VERSION_AHEAD);
        if self.payload_schema_version > local_max {
            return Err(EnvelopeValidationError::PayloadSchemaVersionTooFarAhead {
                version: self.payload_schema_version,
                local_max,
            });
        }
        Ok(())
    }
}

/// Sync operation type.
///
/// Unknown operation strings are rejected at the wire boundary. Pre-
/// public sync has no compatibility contract for future operation
/// semantics, and accepting then skipping an unknown mutation would
/// let transport checkpoints advance past data this build cannot
/// safely interpret.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SyncOperation {
    Upsert,
    Delete,
}

impl SyncOperation {
    /// Returns the canonical string name matching `OP_UPSERT` / `OP_DELETE`.
    pub const fn as_str(&self) -> &'static str {
        match self {
            SyncOperation::Upsert => lorvex_domain::naming::OP_UPSERT,
            SyncOperation::Delete => lorvex_domain::naming::OP_DELETE,
        }
    }
}

#[cfg(test)]
mod tests;
