//! Version constants for the Lorvex system.
//!
//! These are the single source of truth for all version-related values used
//! across sync protocol, export format, schema management, and UI display.

/// Application version string.
pub const APP_VERSION: &str = "1.0.0";

/// Schema version — tracks the highest migration version in the consolidated baseline.
pub const SCHEMA_VERSION: u32 = 1;

/// Payload schema version for sync envelopes.
pub const PAYLOAD_SCHEMA_VERSION: u32 = 1;

/// Export/import format version.
pub const EXPORT_FORMAT_VERSION: u32 = 1;

#[cfg(test)]
mod tests;
