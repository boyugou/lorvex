use thiserror::Error;

pub type AppResult<T> = Result<T, AppError>;

/// Canonical error type for Tauri-side internal helpers.
#[derive(Debug, Error)]
pub enum AppError {
    /// The local disk is full (SQLite `SQLITE_FULL` or `ENOSPC`). Keeps
    /// the original detail string for diagnostics. The
    /// `From<AppError> for String` impl formats this as a sentinel-
    /// prefixed envelope the frontend recognizes and surfaces via a
    /// dedicated actionable toast. See `lorvex_store::disk_full` for
    /// the classifier + process-wide circuit breaker, and #2386 for
    /// the full design.
    #[error("local storage is full: {0}")]
    DiskFull(String),

    /// An error propagated from the `lorvex-store` crate.
    ///
    /// Boxed so `AppError` stays under the 128-byte
    /// `clippy::result_large_err` threshold — the inner error types
    /// carry `rusqlite::Error` and other payloads that would otherwise
    /// inflate every `Result<T, AppError>` in the Tauri layer.
    #[error(transparent)]
    Store(Box<lorvex_store::StoreError>),

    /// An error propagated from the `lorvex-sync` crate.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`AppError::Store`].
    #[error(transparent)]
    Sync(Box<lorvex_sync::error::SyncError>),

    /// An error propagated from the shared outbox enqueue core.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`AppError::Store`].
    #[error(transparent)]
    OutboxEnqueue(Box<lorvex_sync::outbox_enqueue::EnqueueError>),

    /// A raw `rusqlite` error propagated from the database layer.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`AppError::Store`].
    #[error("database error: {0}")]
    Sql(Box<rusqlite::Error>),

    /// A Tauri runtime/windowing error.
    ///
    /// Boxed for the same `clippy::result_large_err` reason as
    /// [`AppError::Store`].
    #[error(transparent)]
    Tauri(Box<tauri::Error>),

    /// The biometric-gated memory lock is engaged. Surfaces as a typed
    /// `memory_locked` envelope so the renderer can prompt the user to
    /// re-authenticate via Touch ID / Windows Hello before retrying the
    /// command. Mapping the gate through
    /// `require_unlocked().map_err(|e| e.to_string())?` would collapse
    /// it into an opaque untyped string at the IPC boundary; this
    /// dedicated variant keeps the wire envelope typed.
    #[error(transparent)]
    MemoryLocked(#[from] crate::memory_lock::MemoryLocked),

    /// A caller-supplied value failed validation.
    #[error("{0}")]
    Validation(String),

    /// The requested entity was not found.
    #[error("{0}")]
    NotFound(String),

    /// A serialization/deserialization error.
    #[error("serialization error: {0}")]
    Serialization(String),

    /// A catch-all for internal errors that don't fit other variants.
    #[error("{0}")]
    Internal(String),

    /// Typed sentinel for transaction-rollback failure paths.
    /// `lorvex_store::with_immediate_transaction` reports a stringy
    /// "rollback failed" error when SQLite refuses to roll back
    /// after the closure returned an error. The transaction wrapper
    /// requires the closure's error type to implement `From<String>`
    /// so it can synthesize this case without leaking implementation
    /// details upstream. Routing through this dedicated variant (and
    /// not a catch-all `From<String> for AppError` that lands in
    /// `AppError::Internal`) keeps the `From<String>` impl scoped to
    /// the transaction-wrapper trait bound and stops it from
    /// silently capturing unrelated string errors.
    #[error("transaction rollback failed: {0}")]
    TransactionRollbackFailed(String),

    /// A bounded async wait did not complete in time. Used for WinRT
    /// `IAsyncOperation::get()` calls (and similar OS-async primitives)
    /// where the broker can stall indefinitely on hostile environments
    /// — see #2837 for the corporate-box Windows calendar broker case.
    /// The detail string carries the operation name and configured budget
    /// so the user-facing toast and the diagnostic log both reflect what
    /// gave up. Treated as a user-facing message in the
    /// `From<AppError> for String` impl below.
    #[error("{0}")]
    Timeout(String),

    /// a long-running sync command (filesystem-bridge sync, snapshot
    /// import/export) was cancelled
    /// during shutdown / re-arm. The detail string identifies which
    /// command and which phase was interrupted.
    /// Treated as a non-error from the user's perspective — the toast
    /// layer surfaces "Cancelled" rather than the alarming red banner.
    #[error("{0}")]
    Cancelled(String),

    /// #3033-H4: a `tauri_plugin_updater` failure (auto-update probe,
    /// download, signature check). The original `Display` of these
    /// errors can include `reqwest` URL paths, `HTTPS_PROXY`/
    /// `HTTP_PROXY` proxy authority fragments (`user:pass@host`), and
    /// signing-key library messages — none of which the renderer
    /// should see. The detail field carries the raw cause for the
    /// diagnostic log via the `From<AppError> for String` impl, while
    /// the wire `message` is a fixed user-facing string.
    #[error("update check failed")]
    RemoteUpdateFailed(String),

    /// #3033-H4: a Tauri window/webview operation failed (focus
    /// window hide/show/set_focus). The `tauri::Error::to_string()`
    /// for these can name the window-id, internal IPC channel state,
    /// and platform-specific objc/com error messages that are not
    /// renderer-actionable. Carry the raw detail to the diagnostic
    /// log; surface a fixed message to the toast layer.
    #[error("window operation failed: {0}")]
    WindowOp(String),
}
