//! Structured defer reasons — typed mirror of TS `DeferReason`
//! (`shared/src/types.ts`).
//!
//! Rust IPC payloads serialised this as `Option<String>`
//! while TypeScript declared `DeferReason | null`, so the wire format
//! was statically narrow on one side and free-form on the other. The
//! `serde(rename_all = "snake_case")` form keeps the persisted /
//! transmitted bytes byte-identical to the existing string constants.

use serde::{Deserialize, Serialize};

pub const DEFER_REASON_NOT_TODAY: &str = "not_today";
pub const DEFER_REASON_BLOCKED: &str = "blocked";
pub const DEFER_REASON_LOW_ENERGY: &str = "low_energy";
pub const DEFER_REASON_NEEDS_BREAKDOWN: &str = "needs_breakdown";
pub const DEFER_REASON_NEEDS_INFO: &str = "needs_info";

pub const ALL_DEFER_REASONS: &[&str] = &[
    DEFER_REASON_NOT_TODAY,
    DEFER_REASON_BLOCKED,
    DEFER_REASON_LOW_ENERGY,
    DEFER_REASON_NEEDS_BREAKDOWN,
    DEFER_REASON_NEEDS_INFO,
];

pub fn is_valid_defer_reason(reason: &str) -> bool {
    ALL_DEFER_REASONS.contains(&reason)
}

/// typed mirror of TS `DeferReason` (`shared/src/types.ts`).
/// Rust IPC payloads serialised this as `Option<String>` while
/// TypeScript declared `DeferReason | null`, so the wire format was
/// statically narrow on one side and free-form on the other. The
/// `serde(rename_all = "snake_case")` form keeps the persisted /
/// transmitted bytes byte-identical to the existing string constants.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeferReason {
    NotToday,
    Blocked,
    LowEnergy,
    NeedsBreakdown,
    NeedsInfo,
}

impl DeferReason {
    pub const fn as_str(self) -> &'static str {
        match self {
            DeferReason::NotToday => DEFER_REASON_NOT_TODAY,
            DeferReason::Blocked => DEFER_REASON_BLOCKED,
            DeferReason::LowEnergy => DEFER_REASON_LOW_ENERGY,
            DeferReason::NeedsBreakdown => DEFER_REASON_NEEDS_BREAKDOWN,
            DeferReason::NeedsInfo => DEFER_REASON_NEEDS_INFO,
        }
    }

    pub fn parse(reason: &str) -> Option<Self> {
        match reason {
            DEFER_REASON_NOT_TODAY => Some(DeferReason::NotToday),
            DEFER_REASON_BLOCKED => Some(DeferReason::Blocked),
            DEFER_REASON_LOW_ENERGY => Some(DeferReason::LowEnergy),
            DEFER_REASON_NEEDS_BREAKDOWN => Some(DeferReason::NeedsBreakdown),
            DEFER_REASON_NEEDS_INFO => Some(DeferReason::NeedsInfo),
            _ => None,
        }
    }
}

impl std::fmt::Display for DeferReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}
