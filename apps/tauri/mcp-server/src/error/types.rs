//! `McpError` enum + the structured `ErrorKind` discriminator that
//! the wire-encoding layer maps it to.

use serde::Serialize;
use thiserror::Error;

/// Canonical error type for MCP-side internal helpers.
#[derive(Debug, Error)]
pub enum McpError {
    /// A pre-sanitized, user-facing message produced by MCP helpers.
    #[error("{0}")]
    UserMessage(String),

    /// An error propagated from the `lorvex-store` crate (SQL, IO, serialization, invariant).
    ///
    /// Boxed so `McpError` stays under the 128-byte
    /// `clippy::result_large_err` threshold — the inner `StoreError`
    /// carries a `rusqlite::Error` payload that dominates the variant size.
    #[error(transparent)]
    Store(Box<lorvex_store::StoreError>),

    /// An error propagated from the `lorvex-sync` crate.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`McpError::Store`].
    #[error(transparent)]
    Sync(Box<lorvex_sync::error::SyncError>),

    /// An error propagated from the shared outbox enqueue core.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`McpError::Store`].
    #[error(transparent)]
    OutboxEnqueue(Box<lorvex_sync::outbox_enqueue::EnqueueError>),

    /// A raw `rusqlite` error propagated from the database layer.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`McpError::Store`].
    #[error("database error: {0}")]
    Sql(Box<rusqlite::Error>),

    /// A caller-supplied value failed validation.
    #[error("{0}")]
    Validation(String),

    /// The requested entity was not found.
    #[error("{0}")]
    NotFound(String),

    /// A serialization/deserialization error.
    #[error("serialization error: {0}")]
    Serialization(String),

    /// The session-wide write rate limit is exhausted. Distinguished from
    /// `Validation` so batch loops can short-circuit on a fatal limiter
    /// rejection rather than swallowing the rejection per-item and
    /// continuing to drain the bucket. Retryable after the limiter
    /// refills (see `server_rate_limit`).
    #[error("{0}")]
    RateLimited(String),

    /// A catch-all for internal errors that don't fit other variants.
    #[error("{0}")]
    Internal(String),

    /// The client sent `notifications/cancelled` (or dropped the
    /// transport) mid-call, and a cooperative cancellation check fired
    /// between logical steps. The handler unwinds immediately, and the
    /// `with_conn` wrapper's `MutexGuard`s release the writer connection
    /// via `Drop` — no partial commits reach SQLite because the
    /// `BEGIN IMMEDIATE` savepoint is rolled back on error (#2133).
    #[error("cancelled by client")]
    CancelledByClient,
}

/// Structured error classes exposed to MCP callers. Each kind implies
/// both a suggested remediation (retry vs. reshape args vs. escalate)
/// and — where applicable — a concrete docs pointer in `docs_hint`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ErrorKind {
    /// Caller-supplied args failed validation. Non-retryable; the
    /// assistant must reshape its request.
    Validation,
    /// The requested entity does not exist. Non-retryable; the
    /// assistant must abandon or re-query.
    NotFound,
    /// SQLite reported `SQLITE_BUSY` / `SQLITE_LOCKED`. Retryable
    /// with exponential backoff.
    DbBusy,
    /// A sync-layer error (envelope processing, outbox, conflict log,
    /// version stamping). Retryable from the assistant's perspective
    /// once the sync pipeline catches up; `docs_hint` points at the
    /// recovery playbook.
    SyncConflict,
    /// A JSON / envelope (de)serialization failure. Non-retryable —
    /// the payload is structurally invalid.
    Serialization,
    /// The session-wide write rate limit was exhausted. Retryable
    /// once the limiter refills (caller backoff is mandatory — the
    /// limiter is the only signal that the assistant is in a
    /// runaway-loop pattern).
    RateLimited,
    /// Catch-all for failures that don't fit a more specific kind.
    Internal,
}

impl ErrorKind {
    pub(super) const fn retryable(self) -> bool {
        matches!(self, Self::DbBusy | Self::SyncConflict | Self::RateLimited,)
    }

    pub(super) const fn docs_hint(self) -> Option<&'static str> {
        match self {
            Self::SyncConflict => Some("docs/execution/SYNC_RECOVERY_PLAYBOOK.md"),
            Self::DbBusy => Some("docs/design/ARCHITECTURE.md#sqlite-concurrency"),
            _ => None,
        }
    }
}
