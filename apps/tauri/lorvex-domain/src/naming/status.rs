//! Task lifecycle status + provider-scope runtime availability state.
//!
//! The [`TaskStatus`] enum is the typed Rust counterpart of the
//! frontend `TaskStatus` literal union in `shared/src/types.ts`.
//! Comparisons, transitions, and SQL bind sites all flow through the
//! typed enum so a typo'd literal is a compile error rather than a
//! silent comparison miss. The `STATUS_*` `&str` consts are retained
//! as `as_str()` of each variant for call sites that bind status to
//! SQL (`named_params! { ":status": STATUS_OPEN }`) while the typed
//! surface migrates incrementally.
//!
//! The `availability_state` constants for the
//! `provider_scope_runtime_state` table also live here so every SQL
//! builder shares one `format!`-substitutable token. Open-coding
//! the vocabulary as SQL string literals across `provider_repo.rs`,
//! `calendar_timeline/queries.rs`, `sync_runtime/status.rs`, and
//! the Tauri test fixtures would let a typo at any single site
//! silently fall out of the `availability_state IN (...)` predicate
//! without firing a CHECK violation.

use serde::{Deserialize, Serialize};

/// Typed task lifecycle status. Mirrors the TS literal union
/// `TaskStatus` in `shared/src/types.ts`.
///
/// The wire format (`as_str` / `parse`) is the canonical lower-snake-
/// case identifier shared across the SQL `tasks.status` column, sync
/// envelopes, and the frontend.
/// serde `rename_all = "snake_case"` keeps the wire
/// format byte-identical to the previous string-typed `status` column
/// (`open` / `completed` / `cancelled` / `someday`). Adding
/// Serialize+Deserialize lets typed boundaries (e.g. `UndoToken`) carry
/// `TaskStatus` directly instead of stringly-typed `String` columns.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    /// The default state for newly-created tasks. Eligible for
    /// scheduling, surfacing in Today, etc.
    Open,
    /// Terminal — task was finished. `completed_at` is set; the row
    /// no longer surfaces in active queries.
    Completed,
    /// Terminal — task was abandoned. `completed_at` is cleared and
    /// `defer` state is reset.
    Cancelled,
    /// Soft-park — task is tracked but excluded from the active list
    /// until manually re-opened. Distinct from `Cancelled` (which is
    /// terminal) and `Open` (which is actionable).
    Someday,
}

impl TaskStatus {
    /// Wire-format string (matches the SQL `tasks.status` column and
    /// the TS literal union).
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::Completed => "completed",
            Self::Cancelled => "cancelled",
            Self::Someday => "someday",
        }
    }

    /// Parse a wire-format string into a typed status. Returns `None`
    /// for unknown values — callers should treat `None` the same way
    /// they treated an arbitrary `&str` slipping past the prior CHECK
    /// constraint (i.e. surface as a validation error).
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "open" => Some(Self::Open),
            "completed" => Some(Self::Completed),
            "cancelled" => Some(Self::Cancelled),
            "someday" => Some(Self::Someday),
            _ => None,
        }
    }

    /// `true` for `Completed` / `Cancelled`. Issue #3001-M17 noted
    /// 35 ad-hoc `status === 'completed' || status === 'cancelled'`
    /// comparisons across the frontend; this method is the typed
    /// counterpart for the Rust side.
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Cancelled)
    }

    /// `true` for `Open`. Convenience inverse of `is_terminal` /
    /// `is_someday` for the common "actionable now" predicate.
    pub const fn is_open(self) -> bool {
        matches!(self, Self::Open)
    }
}

impl std::fmt::Display for TaskStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

pub const STATUS_OPEN: &str = TaskStatus::Open.as_str();
pub const STATUS_COMPLETED: &str = TaskStatus::Completed.as_str();
pub const STATUS_CANCELLED: &str = TaskStatus::Cancelled.as_str();
pub const STATUS_SOMEDAY: &str = TaskStatus::Someday.as_str();

/// The canonical "active task" predicate value list, ready to drop
/// into a `WHERE status IN ({…})` SQL fragment. "Active" here means
/// `open` or `someday` — the two statuses a user can still act on.
/// Centralizing the literal list keeps every cycle / dependency /
/// graph predicate aligned with the typed [`TaskStatus`] enum so
/// adding a new active variant is a single-site change.
pub const ACTIVE_STATUS_SQL_LIST: &str = "'open', 'someday'";

// ---------------------------------------------------------------------------
// Provider scope runtime availability states
// ---------------------------------------------------------------------------

/// `availability_state` value indicating the scope is healthy and queryable.
pub const AVAILABILITY_STATE_ENABLED: &str = "enabled";

/// `availability_state` value written when the OS denies the scope's
/// permission (Calendar, Reminders, Photos, etc. all surface here).
pub const AVAILABILITY_STATE_PERMISSION_DENIED: &str = "permission_denied";

/// `availability_state` / `last_refresh_result` value written when the OS
/// returns an authorization-shaped error during the actual fetch (the
/// permission was nominally granted, but the fetch is rejected anyway —
/// e.g. revoked TCC, container migration races).
pub const AVAILABILITY_STATE_AUTHORIZATION_ERROR: &str = "authorization_error";

/// `availability_state` / `last_refresh_result` value written when the
/// provider connector itself fails (network, RPC, OS API timeout). The
/// scope row stays in this state until the next periodic retry.
pub const AVAILABILITY_STATE_FETCH_ERROR: &str = "fetch_error";

/// `availability_state` / `last_refresh_result` value written when the
/// fetched payload could not be parsed into a provider event row. Indicates
/// a connector-side bug or a foreign-format envelope; the scope is
/// effectively dead until the connector ships a fix.
pub const AVAILABILITY_STATE_PARSE_ERROR: &str = "parse_error";

/// SQL fragment listing every `availability_state` / `last_refresh_result`
/// value that signals a degraded scope. Inlined into
/// `provider_scope_health` SQL so the table-level predicate stays in
/// lock-step with [`is_provider_error_label`].
pub const AVAILABILITY_STATE_ERROR_SQL_LIST: &str =
    "'permission_denied', 'authorization_error', 'fetch_error', 'parse_error'";
