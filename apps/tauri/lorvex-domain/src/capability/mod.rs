//! Capability-based sync gating — handshake and envelope-level compatibility.
//!
//! This module implements the pure logic for determining whether two sync
//! peers are compatible, degraded, or blocked. All functions are pure — no
//! IO, no database, no network.
//!
//! See spec Section 15: Capability-Based Sync Gating.

use std::collections::BTreeSet;

/// Handshake sent during sync session establishment.
#[derive(Debug, Clone)]
pub struct SyncHandshake {
    /// For quick reject and human readability.
    pub sync_protocol_version: u32,
    /// For envelope parsing compatibility.
    pub payload_schema_version: u32,
    /// Capabilities that MUST be understood to process sync data.
    pub required_capabilities: BTreeSet<String>,
    /// Capabilities that are safe to ignore if unknown.
    pub optional_capabilities: BTreeSet<String>,
    /// Informational app version string.
    pub app_version: String,
    /// Source device identifier.
    pub device_id: String,
}

/// Result of a handshake-level compatibility check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncCompatibility {
    /// All remote capabilities known; full sync can proceed.
    Compatible,
    /// Sync can proceed with reduced functionality.
    Degraded(Vec<DegradedReason>),
    /// Sync must be paused until versions align.
    Blocked(BlockedReason),
}

/// Reasons that cause sync to be blocked (requires app update to resolve).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockedReason {
    /// The sync protocol major version does not match.
    MajorVersionMismatch { local: u32, remote: u32 },
    /// The remote requires capabilities this version does not know.
    UnknownRequiredCapabilities { capabilities: Vec<String> },
    /// The remote payload schema is more than 1 version ahead.
    PayloadSchemaTooFarAhead { local: u32, remote: u32 },
}

/// Reasons that cause degraded sync (sync continues, but some data may
/// not be fully understood).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DegradedReason {
    /// The remote advertises optional capabilities we do not know.
    UnknownOptionalCapabilities { capabilities: Vec<String> },
    /// The remote payload schema is exactly 1 version ahead.
    PayloadSchemaAhead { local: u32, remote: u32 },
}

/// Per-envelope acceptance decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvelopeAcceptance {
    /// Known version: parse all fields.
    ParseFully,
    /// One version ahead: forward-compat — parse known fields, ignore unknown.
    ParseForwardCompat,
    /// Too far ahead: cannot safely parse — queue to pending inbox.
    DeferToPendingInbox,
}

/// Check handshake-level compatibility between local and remote peers.
///
/// The algorithm:
/// 1. Quick reject on major version mismatch.
/// 2. Block on unknown required capabilities.
/// 3. Block if payload schema is >1 version ahead.
/// 4. Degrade if payload schema is exactly 1 version ahead.
/// 5. Degrade if unknown optional capabilities exist.
/// 6. Otherwise: compatible.
pub fn check_handshake(local: &SyncHandshake, remote: &SyncHandshake) -> SyncCompatibility {
    // 1. Quick reject: major version incompatibility
    if major_version_differs(local.sync_protocol_version, remote.sync_protocol_version) {
        return SyncCompatibility::Blocked(BlockedReason::MajorVersionMismatch {
            local: local.sync_protocol_version,
            remote: remote.sync_protocol_version,
        });
    }

    // 2. Check required capabilities
    let known = known_capabilities();
    let unknown_required: Vec<String> = remote
        .required_capabilities
        .difference(&known)
        .cloned()
        .collect();

    if !unknown_required.is_empty() {
        return SyncCompatibility::Blocked(BlockedReason::UnknownRequiredCapabilities {
            capabilities: unknown_required,
        });
    }

    // 3. Check payload_schema_version
    let mut degraded_reasons = Vec::new();

    // `local.payload_schema_version + 1` panics in
    // debug builds when the local version is `u32::MAX` and wraps to
    // `0` in release. `saturating_add` keeps the comparison meaningful
    // at the upper bound — once we are at MAX, no remote can be
    // "more than one version ahead".
    if remote.payload_schema_version > local.payload_schema_version.saturating_add(1) {
        // Remote is >1 version ahead — payloads may have breaking changes
        return SyncCompatibility::Blocked(BlockedReason::PayloadSchemaTooFarAhead {
            local: local.payload_schema_version,
            remote: remote.payload_schema_version,
        });
    } else if remote.payload_schema_version > local.payload_schema_version {
        // Remote is exactly 1 version ahead — forward-compat: new additive fields
        degraded_reasons.push(DegradedReason::PayloadSchemaAhead {
            local: local.payload_schema_version,
            remote: remote.payload_schema_version,
        });
    }

    // 4. Check optional capabilities
    let unknown_optional: Vec<String> = remote
        .optional_capabilities
        .difference(&known)
        .cloned()
        .collect();

    if !unknown_optional.is_empty() {
        degraded_reasons.push(DegradedReason::UnknownOptionalCapabilities {
            capabilities: unknown_optional,
        });
    }

    if !degraded_reasons.is_empty() {
        return SyncCompatibility::Degraded(degraded_reasons);
    }

    SyncCompatibility::Compatible
}

/// Check per-envelope acceptance based on its payload schema version.
///
/// - Known version: parse fully.
/// - Exactly 1 ahead: parse known fields, ignore unknown (forward-compat).
/// - More than 1 ahead: defer to pending inbox (app update needed).
pub const fn check_envelope_version(
    envelope_payload_version: u32,
    local_max_version: u32,
) -> EnvelopeAcceptance {
    if envelope_payload_version <= local_max_version {
        EnvelopeAcceptance::ParseFully
    } else if envelope_payload_version == local_max_version.saturating_add(1) {
        EnvelopeAcceptance::ParseForwardCompat
    } else {
        EnvelopeAcceptance::DeferToPendingInbox
    }
}

/// Known capabilities for this version of Lorvex.
///
/// New capabilities are added here as features are built. Each capability
/// should be classified as required or optional at the handshake level.
/// The set of capabilities this version of Lorvex supports.
///
/// Uses a static slice to avoid per-call allocation; callers that need
/// `BTreeSet` can convert with `.iter().copied().collect()`.
const KNOWN_CAPABILITIES: &[&str] = &[
    "capability_negotiation",
    "content_addressed_blobs",
    "hlc_versioning",
    "recurrence_instance_key",
    "tag_lookup_keys",
    "tombstone_redirect",
];

pub fn known_capabilities() -> BTreeSet<String> {
    KNOWN_CAPABILITIES
        .iter()
        .map(std::string::ToString::to_string)
        .collect()
}

/// Extract the major version from a protocol/schema version number.
///
/// Convention: major = v / 1000 (e.g., 1001 -> major 1, 2000 -> major 2).
const fn major_version(v: u32) -> u32 {
    v / 1000
}

/// Check whether two version numbers have different major versions.
const fn major_version_differs(a: u32, b: u32) -> bool {
    major_version(a) != major_version(b)
}

#[cfg(test)]
mod tests;
