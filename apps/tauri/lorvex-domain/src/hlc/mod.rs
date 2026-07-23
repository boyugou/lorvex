//! Hybrid Logical Clock (HLC) value type.
//!
//! Format: `{physical_ms:013}_{counter:04}_{device_suffix}`
//!
//! - `physical_ms`: 13-digit zero-padded millisecond Unix timestamp
//! - `counter`: 4-digit zero-padded counter (0000-9999)
//! - `device_suffix`: 16 hex characters derived from the device's stable ID
//!   **and** the emitting surface (app / mcp / cli). Widened from 8
//!   chars per #2870 — 64 bits keeps cross-device birthday collisions
//!   vanishingly rare at realistic install scales.
//!
//! Properties:
//! - Lexicographically sortable (SQL `ORDER BY version` works correctly)
//! - Human-debuggable (timestamp is readable, device suffix identifies source)
//! - Globally unique (timestamp + counter + device suffix)
//! - Monotonically increasing per device
//!
//! a single 585-line `hlc.rs`; split per-concern so each
//! file holds one cohesive group (surface tag, parse-error variants,
//! `Hlc` core, `Ord`, cross-string comparator, serde + display).
//! The public surface is preserved verbatim through the re-exports
//! below — every external `use lorvex_domain::hlc::*` continues to
//! compile.

mod compare;
mod core;
mod order;
mod parse_error;
mod serde_impls;
mod surface;

pub use compare::compare_versions_with_fallback;
pub use core::{assert_test_version_safe, Hlc, MAX_COUNTER, MAX_HLC_PHYSICAL_MS, TEST_VERSION};
pub use parse_error::{HlcParseError, HLC_DEVICE_SUFFIX_HEX_LEN};
pub use surface::HlcSurface;

#[cfg(test)]
mod tests;
