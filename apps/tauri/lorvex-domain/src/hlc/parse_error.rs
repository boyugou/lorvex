//! Parse error variants for HLC strings, plus the device-suffix shape
//! validator used by both `Hlc::new` and `Hlc::parse`.

use std::fmt;

use super::core::{MAX_COUNTER, MAX_HLC_PHYSICAL_MS};

/// Number of hex characters in the HLC device suffix.
///
/// 16 hex chars = 64 bits of device-isolation entropy. Mirrors the
/// value in `lorvex_runtime::device_identity::HLC_DEVICE_SUFFIX_HEX_LEN`
/// (which re-exports this constant so the runtime helpers and the
/// type-system invariant stay aligned). `Hlc::new` and `Hlc::parse`
/// both reject suffixes that don't match this length AND aren't
/// lowercase hex; accepting any non-empty string would let a peer
/// envelope with a 1-char or 31-char suffix poison cross-device LWW
/// (different devices would emit different lex-orderings around the
/// malformed value).
pub const HLC_DEVICE_SUFFIX_HEX_LEN: usize = 16;

/// Error type for HLC string parsing failures.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HlcParseError {
    /// The input string does not have the expected format.
    InvalidFormat(String),
    /// The physical_ms segment is not a valid u64.
    InvalidPhysicalMs(String),
    /// The physical_ms segment exceeds [`MAX_HLC_PHYSICAL_MS`] — either
    /// from a clock-skewed peer (future-dated NTP response) or a
    /// malicious envelope. Accepting it would break the 13-digit
    /// zero-padded lex ordering (14+ digits lex above every
    /// legitimate entry forever, poisoning LWW).
    PhysicalMsOutOfRange(u64),
    /// The counter segment is not a valid u32.
    InvalidCounter(String),
    /// The counter segment exceeds the canonical four-digit HLC
    /// counter ceiling. Accepting it would widen the `{:04}` Display
    /// slot to five or more digits and break raw string ordering.
    CounterOutOfRange(u32),
    /// The device_suffix segment is empty.
    EmptyDeviceSuffix,
    /// The device_suffix is not exactly
    /// [`HLC_DEVICE_SUFFIX_HEX_LEN`] characters long. Without this
    /// length check, a peer authoring HLCs with 1-char or 31-char
    /// suffixes would silently survive parse and break cross-device
    /// LWW (different devices would reach different lex orderings
    /// around the malformed value). Surfacing the corrupt envelope
    /// as a typed error routes it to the pending-inbox / conflict-log
    /// diagnostics.
    InvalidDeviceSuffixLength {
        suffix: String,
        expected: usize,
        actual: usize,
    },
    /// the device_suffix contains a non-hex character.
    /// The runtime suffix is derived from `SHA-256(...)` and rendered
    /// lowercase hex; any non-ascii-hexdigit byte is corruption (legacy
    /// fixture, hand-edited DB, malicious peer). Refuse the parse so
    /// the same diagnostic surface that catches length violations
    /// catches alphabet violations.
    InvalidDeviceSuffixCharset(String),
}

impl fmt::Display for HlcParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidFormat(s) => write!(f, "invalid HLC format: {s}"),
            Self::InvalidPhysicalMs(s) => write!(f, "invalid physical_ms: {s}"),
            Self::PhysicalMsOutOfRange(ms) => write!(
                f,
                "physical_ms {ms} exceeds maximum {MAX_HLC_PHYSICAL_MS} (~year 2286)",
            ),
            Self::InvalidCounter(s) => write!(f, "invalid counter: {s}"),
            Self::CounterOutOfRange(counter) => write!(
                f,
                "counter {counter} exceeds maximum {MAX_COUNTER} (canonical HLC counter range is 0000-9999)",
            ),
            Self::EmptyDeviceSuffix => write!(f, "empty device suffix"),
            Self::InvalidDeviceSuffixLength {
                suffix,
                expected,
                actual,
            } => write!(
                f,
                "device suffix {suffix:?} length {actual} does not match required {expected}"
            ),
            Self::InvalidDeviceSuffixCharset(s) => write!(
                f,
                "device suffix {s:?} contains non-hex characters (must be lowercase ascii hex)"
            ),
        }
    }
}

impl std::error::Error for HlcParseError {}

/// Internal: validate that a device suffix has the canonical shape —
/// exactly [`HLC_DEVICE_SUFFIX_HEX_LEN`] characters, all ascii hex
/// (case-insensitive; the caller is responsible for lowercasing
/// before storage).
pub(super) fn validate_device_suffix(suffix: &str) -> Result<(), HlcParseError> {
    if suffix.is_empty() {
        return Err(HlcParseError::EmptyDeviceSuffix);
    }
    if suffix.len() != HLC_DEVICE_SUFFIX_HEX_LEN {
        return Err(HlcParseError::InvalidDeviceSuffixLength {
            suffix: suffix.to_string(),
            expected: HLC_DEVICE_SUFFIX_HEX_LEN,
            actual: suffix.len(),
        });
    }
    if !suffix.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(HlcParseError::InvalidDeviceSuffixCharset(
            suffix.to_string(),
        ));
    }
    Ok(())
}
