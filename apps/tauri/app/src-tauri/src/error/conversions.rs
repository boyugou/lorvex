use super::types::AppError;

// The `From<String> for AppError` impl maps to the purpose-named
// `TransactionRollbackFailed` variant rather than the catch-all
// `AppError::Internal(s)`. Mapping into `Internal` would let every
// `?`-propagated `Result<_, String>` silently upgrade into the
// opaque "An internal error occurred." toast (the IPC envelope
// sanitizes the message) and rob the renderer of any actionable
// signal.
//
// The impl exists only because
// `lorvex_store::with_immediate_transaction` requires the closure's
// error type to implement `From<String>` so it can surface SQLite
// rollback-failure cases. Every other caller that needs to translate
// a `String` error MUST pick an explicit variant
// (`AppError::Validation`, `AppError::Internal`, `AppError::NotFound`,
// ...) so the typed envelope routes correctly.
impl From<String> for AppError {
    fn from(s: String) -> Self {
        Self::TransactionRollbackFailed(s)
    }
}

/// `Box::new`-wrapping `From` impls for the boxed variants of
/// [`AppError`]. The variants are boxed to keep `AppError` under the
/// 128-byte `clippy::result_large_err` threshold; these impls let
/// `?` propagation continue working from the inner error types.
impl From<lorvex_store::StoreError> for AppError {
    fn from(e: lorvex_store::StoreError) -> Self {
        Self::Store(Box::new(e))
    }
}

impl From<lorvex_sync::error::SyncError> for AppError {
    fn from(e: lorvex_sync::error::SyncError) -> Self {
        Self::Sync(Box::new(e))
    }
}

impl From<lorvex_sync::outbox_enqueue::EnqueueError> for AppError {
    fn from(e: lorvex_sync::outbox_enqueue::EnqueueError) -> Self {
        Self::OutboxEnqueue(Box::new(e))
    }
}

impl From<rusqlite::Error> for AppError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sql(Box::new(e))
    }
}

impl From<tauri::Error> for AppError {
    fn from(e: tauri::Error) -> Self {
        Self::Tauri(Box::new(e))
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization(e.to_string())
    }
}

// Per-domain task and calendar exception variants live on
// `StoreError`, so the `#[from] StoreError` arm on `AppError`
// handles every boundary mapping uniformly. Bespoke per-domain
// conversions that spelled out `Validation` / `NotFound` / `Sql`
// arms by hand would drift out of sync as new variants land.

impl From<lorvex_workflow::recurrence_config::RecurrenceChangeError> for AppError {
    fn from(error: lorvex_workflow::recurrence_config::RecurrenceChangeError) -> Self {
        use lorvex_workflow::recurrence_config::RecurrenceChangeError;

        match error {
            RecurrenceChangeError::ClearDueDateOnRecurring => Self::Validation(error.to_string()),
            RecurrenceChangeError::DueTimeWithoutDueDate => Self::Validation(error.to_string()),
            RecurrenceChangeError::Db(e) => Self::Sql(Box::new(e)),
            // `apply_recurrence_change` now self-wraps
            // in an immediate transaction when invoked outside one; the
            // wrap helper surfaces failures as `TransactionWrap`. The
            // payload is a free-form description, not a structured DB
            // error, so route to `Internal` rather than `Sql` (which is
            // reserved for `rusqlite::Error` round-trips).
            RecurrenceChangeError::TransactionWrap(message) => Self::Internal(message),
            // LWW gate rejected the UPDATE because a peer envelope
            // landed between the boundary's HLC mint and our write.
            // Mirrors the `StoreError::StaleVersion` mapping in
            // `From<StoreError> for AppError`: surface as
            // `Validation` so the caller handles it the same as a
            // stale-row write — re-stamp HLC and retry.
            ref err @ RecurrenceChangeError::StaleVersion { .. } => {
                Self::Validation(err.to_string())
            }
        }
    }
}

impl From<lorvex_sync::apply::ApplyError> for AppError {
    fn from(error: lorvex_sync::apply::ApplyError) -> Self {
        // Peel each `ApplyError` variant onto the semantically
        // correct `AppError`. A catch-all `Validation` arm would
        // mis-classify internal-state failures (`UnknownEntityType`,
        // `TombstoneRedirectCycle`, `InvalidOperation`) that the
        // renderer cannot fix — forward-compat or peer-protocol
        // errors should route as `Internal` so the toast doesn't
        // promise the user an actionable fix.
        use lorvex_sync::apply::ApplyError;

        match error {
            ApplyError::Db(e) => Self::Sql(Box::new(e)),
            ApplyError::Store(e) => Self::Store(Box::new(e)),
            // True caller-validation failures: the inbound payload
            // was malformed (bad version string, bad JSON shape, bad
            // field type / value). Surface as `Validation` so the
            // typed envelope routes the message verbatim.
            err @ (ApplyError::InvalidVersion(_) | ApplyError::InvalidPayload(_)) => {
                Self::Validation(err.to_string())
            }
            // Internal / forward-compat / peer-protocol failures
            // that are not caller-fixable. Route as `Internal` so the
            // IPC envelope sanitizes the wire payload (the diagnostic
            // detail is preserved via the `error_logs` chain
            // upstream).
            err @ (ApplyError::TransactionRequired
            | ApplyError::UnknownEntityType(_)
            | ApplyError::TombstoneRedirectCycle { .. }
            | ApplyError::TombstoneRedirectChainTooDeep { .. }
            | ApplyError::InvalidOperation { .. }
            // a redirect chase that produced an over-
            // sized canonical payload is structurally a peer-protocol
            // failure (the chain of merges produced a payload-FK
            // expansion this device cannot canonically encode), not
            // a caller-fixable validation failure.
            | ApplyError::RedirectPayloadTooLarge { .. }) => Self::Internal(err.to_string()),
        }
    }
}

impl From<lorvex_runtime::RuntimeError> for AppError {
    fn from(error: lorvex_runtime::RuntimeError) -> Self {
        // Peel each `RuntimeError` variant onto the closest-matching
        // `AppError` so the typed IPC envelope surfaces the right
        // `kind` to the renderer. Collapsing every variant into
        // `AppError::Internal(to_string())` would sanitize the wire
        // payload to the opaque "An internal error occurred." toast
        // and make caller-actionable variants like `InvalidLeaseTtl`
        // indistinguishable from genuinely opaque `Sqlite` failures.
        use lorvex_runtime::RuntimeError;
        match error {
            // SQLite-shaped errors flow through the existing
            // `Sql` arm so the disk-full classifier and the rest of
            // the typed routing still apply.
            RuntimeError::Sqlite(sql_err) => Self::Sql(Box::new(sql_err)),
            // `DeviceIdentityUnavailable` is a startup-state
            // failure: the device-identity row could not be
            // initialized. The renderer can do nothing actionable
            // about it, so route as `Internal` but keep the typed
            // message instead of the opaque "internal error" toast.
            err @ RuntimeError::DeviceIdentityUnavailable => Self::Internal(err.to_string()),
            // The remaining variants are caller-validation failures
            // (non-positive lease TTL, corrupt local-counter row that
            // the caller authored or stored, system clock pre-1970).
            // Surface them as `Validation` so the IPC envelope sets
            // `kind: validation` and the renderer can render the
            // actionable typed message verbatim.
            err @ (RuntimeError::InvalidLeaseTtl(_)
            | RuntimeError::CorruptLocalChangeSeq { .. }
            | RuntimeError::SystemClockOutOfRange) => Self::Validation(err.to_string()),
        }
    }
}

impl From<lorvex_domain::validation::ValidationError> for AppError {
    fn from(e: lorvex_domain::validation::ValidationError) -> Self {
        Self::Validation(e.to_string())
    }
}
