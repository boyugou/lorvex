//! `From<…>` impls that lift external errors into [`McpError`].
//!
//! `From<McpError> for String` lives in `wire.rs` because the protocol-
//! boundary encoder is the heaviest piece of conversion logic and
//! pulls in the wire-format helpers.

use super::types::McpError;

impl From<String> for McpError {
    fn from(s: String) -> Self {
        Self::UserMessage(s)
    }
}

/// Lift `lorvex-runtime`'s typed error into `McpError`, preserving each
/// variant's retryability.
/// `get_or_create_sync_device_id`) wrapped this with
/// `.map_err(|e| McpError::Internal(e.to_string()))`, which durably
/// masked `RuntimeError::Sqlite(SQLITE_BUSY)` as `Internal` instead of
/// the retryable `DbBusy` ErrorKind. Routing the `Sqlite` variant
/// through `Self::Sql` lets the wire encoder's classifier fire.
impl From<lorvex_runtime::RuntimeError> for McpError {
    fn from(error: lorvex_runtime::RuntimeError) -> Self {
        use lorvex_runtime::RuntimeError as E;
        match error {
            E::Sqlite(sql_error) => Self::Sql(Box::new(sql_error)),
            other @ (E::DeviceIdentityUnavailable
            | E::InvalidLeaseTtl(_)
            | E::CorruptLocalChangeSeq { .. }
            | E::SystemClockOutOfRange) => Self::Internal(other.to_string()),
        }
    }
}

impl From<lorvex_store::StoreError> for McpError {
    fn from(e: lorvex_store::StoreError) -> Self {
        match e {
            lorvex_store::StoreError::Validation(msg) => Self::Validation(msg),
            lorvex_store::StoreError::NotFound { entity, id } => {
                Self::NotFound(format!("{entity} '{id}' not found"))
            }
            other => Self::Store(Box::new(other)),
        }
    }
}

impl From<lorvex_sync::error::SyncError> for McpError {
    fn from(e: lorvex_sync::error::SyncError) -> Self {
        match e {
            lorvex_sync::error::SyncError::Store(store_err) => Self::from(store_err),
            other => Self::Sync(Box::new(other)),
        }
    }
}

/// `Box::new`-wrapping `From` impls for the boxed variants of
/// [`McpError`]. The variants are boxed to keep `McpError` under the
/// 128-byte `clippy::result_large_err` threshold; these impls let
/// `?` propagation continue working from the inner error types.
impl From<rusqlite::Error> for McpError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sql(Box::new(e))
    }
}

impl From<lorvex_sync::outbox_enqueue::EnqueueError> for McpError {
    fn from(e: lorvex_sync::outbox_enqueue::EnqueueError) -> Self {
        Self::OutboxEnqueue(Box::new(e))
    }
}

impl From<serde_json::Error> for McpError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization(e.to_string())
    }
}

impl From<lorvex_domain::validation::ValidationError> for McpError {
    fn from(e: lorvex_domain::validation::ValidationError) -> Self {
        Self::Validation(e.to_string())
    }
}

/// bridge the canonical
/// `lorvex_domain::parse_json_string_field` error to the MCP boundary so
/// every JSON-string field validation surfaces with the same wording
/// regardless of which router invoked the parser.
impl From<lorvex_domain::JsonStringFieldError> for McpError {
    fn from(e: lorvex_domain::JsonStringFieldError) -> Self {
        Self::Validation(e.to_string())
    }
}

/// Lift the recurrence-config helper's typed error into `McpError`,
/// preserving each variant's retryability semantics.
/// caller used `.map_err(|e| McpError::Validation(e.to_string()))`,
/// which durably masked retryable failures: a `Db(SQLITE_BUSY)` was
/// surfaced to assistants as a non-retryable validation error, and a
/// `StaleVersion` race was surfaced as a user-shape problem instead of
/// a sync conflict the assistant should re-stamp and retry.
///
/// Routing now matches the rest of the `From<…>` impls in this file:
/// - `ClearDueDateOnRecurring` is genuine user-shape validation.
/// - `Db(rusqlite::Error)` carries the inner SQLite error verbatim so
///   the wire encoder's `SQLITE_BUSY → DbBusy` classifier (retryable)
///   fires correctly.
/// - `TransactionWrap(msg)` is an internal invariant break in the
///   transaction wrapper, not user input — surface as `Internal`.
/// - `StaleVersion { task_id }` mirrors the existing
///   `StoreError::StaleVersion` path so the wire encoder reuses the
///   `SyncConflict` ErrorKind (retryable after HLC re-stamp).
impl From<lorvex_workflow::recurrence_config::RecurrenceChangeError> for McpError {
    fn from(e: lorvex_workflow::recurrence_config::RecurrenceChangeError) -> Self {
        use lorvex_workflow::recurrence_config::RecurrenceChangeError as E;
        match e {
            E::ClearDueDateOnRecurring => {
                Self::Validation("recurring tasks must have a due_date".to_string())
            }
            E::DueTimeWithoutDueDate => Self::Validation(
                "due_time without due_date is invalid: a clock time requires a calendar day"
                    .to_string(),
            ),
            E::Db(sql) => Self::Sql(Box::new(sql)),
            E::TransactionWrap(msg) => {
                Self::Internal(format!("transaction wrapper failure: {msg}"))
            }
            E::StaleVersion { task_id } => {
                Self::Store(Box::new(lorvex_store::StoreError::StaleVersion {
                    entity: lorvex_domain::naming::ENTITY_TASK,
                    id: task_id,
                }))
            }
        }
    }
}
