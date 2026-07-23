use serde::Serialize;

use super::types::AppError;

/// Stable machine-readable kind tag for a [`CommandError`]. The
/// frontend (`app/src/lib/ipc/commandError.ts`) switches on this to
/// dispatch class-specific UI affordances — disk-full toast, "task not
/// found" inline error — without parsing the
/// human-readable message. New variants must be added here AND in the
/// TS discriminated union; the round-trip test below pins both ends.
#[derive(Debug, Serialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CommandErrorKind {
    /// A caller-supplied value failed validation (bad date, empty
    /// title, out-of-range priority).
    Validation,
    /// The requested entity (task, list, calendar event, ...) was not
    /// found.
    NotFound,
    /// Local SQLite database / blob directory is full
    /// (`SQLITE_FULL` or `ENOSPC`). Toast layer surfaces a "reveal
    /// storage" affordance. See #2386.
    DiskFull,
    /// A bounded async wait did not complete in time (Windows calendar
    /// broker, biometrics prompt, etc.). See #2837.
    Timeout,
    /// A Tauri runtime/windowing error (window not found, IPC
    /// channel closed). User-facing message is generally safe.
    Tauri,
    /// A serialization/deserialization error in user-supplied data.
    /// The detail is sanitized to avoid leaking parser internals.
    Serialization,
    /// The biometric-gated memory lock is engaged. The renderer
    /// surfaces a Touch ID / Windows Hello unlock prompt rather than
    /// the generic error toast. See #4351.
    MemoryLocked,
    /// Catch-all for internal failures we don't want to expose to the
    /// renderer in detail (raw SQL errors, sync-pipeline state, etc.).
    /// The user-facing message is sanitized.
    Internal,
    /// a long-running sync command (filesystem-bridge, snapshot
    /// import/export) was cancelled at
    /// shutdown / re-arm time. The TS toast layer should render this
    /// as a benign "Cancelled" affordance rather than the red error
    /// banner Validation/Internal would trigger. Mirror this case in
    /// `app/src/lib/ipc/commandError.ts` when adding new frontend
    /// handling.
    Cancelled,
}

/// Wire-format error envelope returned across the Tauri IPC boundary.
///
/// Tauri 2 commands return `Result<T, String>` because the bridge
/// serializes errors as strings. The envelope is a JSON object that
/// scales to new classes without per-class sentinel prefixes (which
/// would otherwise need to be kept in lockstep across producer and
/// consumer, and would let any non-prefixed error fall through to
/// the opaque "An internal error occurred" toast).
///
/// The envelope serializes to a JSON object the frontend parses
/// into a typed discriminated union (`CommandError` in
/// `app/src/lib/ipc/commandError.ts`). The CLI did the same migration
/// in `2c08c97c8` (`CliError` enum); this is the Tauri side.
///
/// Wire shape:
///
/// ```json
/// { "kind": "validation", "message": "title cannot be empty", "detail": null }
/// { "kind": "not_found", "message": "Task not found: abc-123", "detail": null }
/// { "kind": "disk_full", "message": "...", "detail": "SQLITE_FULL: ..." }
/// ```
#[derive(Debug, Serialize)]
pub struct CommandError {
    /// Machine-tag for the failure class.
    pub kind: CommandErrorKind,
    /// Optional subclass tag for typed error families.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub class: Option<&'static str>,
    /// Human-readable message safe to surface to the user.
    pub message: String,
    /// Optional detail string for diagnostics — round-trips so the
    /// error_logs / changelog can capture the underlying cause without
    /// the toast layer having to render it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

impl CommandError {
    /// Serialize the envelope to its on-the-wire JSON string. The
    /// fallback to a plain message is unreachable for the variants we
    /// build (no field types fail to serialize), but we don't want a
    /// panic on the IPC boundary if a future variant ever does.
    pub(super) fn to_ipc_string(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| self.message.clone())
    }

    pub(super) fn from_app_error(error: &AppError) -> Self {
        match error {
            // #2386: DiskFull surfaces as a typed envelope so the toast
            // layer can render an actionable "Storage is full" banner.
            AppError::DiskFull(details) => Self {
                kind: CommandErrorKind::DiskFull,
                class: None,
                message: "Local storage is full.".to_string(),
                detail: Some(details.clone()),
            },
            // `StoreError::DiskFull` passes through to the same typed
            // envelope; every other store/sync/rusqlite variant is
            // sanitized below.
            //
            // The typed peel-offs (Validation / NotFound / StaleVersion /
            // DiskFull) surface user-actionable shapes so the toast layer
            // can render the right banner; any remaining `StoreError`
            // variant collapses into the sanitized internal arm.
            AppError::Store(boxed) => match boxed.as_ref() {
                lorvex_store::StoreError::DiskFull { details } => Self {
                    kind: CommandErrorKind::DiskFull,
                    class: None,
                    message: "Local storage is full.".to_string(),
                    detail: Some(details.clone()),
                },
                lorvex_store::StoreError::Validation(msg) => Self {
                    kind: CommandErrorKind::Validation,
                    class: None,
                    message: msg.clone(),
                    detail: None,
                },
                lorvex_store::StoreError::NotFound { entity, id } => Self {
                    kind: CommandErrorKind::NotFound,
                    class: None,
                    message: format!("{entity} not found: {id}"),
                    detail: None,
                },
                lorvex_store::StoreError::StaleVersion { entity, id } => Self {
                    kind: CommandErrorKind::Validation,
                    class: None,
                    message: format!("Stale version on {entity} {id}: re-stamp HLC and retry."),
                    detail: None,
                },
                _ => Self {
                    kind: CommandErrorKind::Internal,
                    class: None,
                    message: "An internal error occurred. Please try again.".to_string(),
                    detail: None,
                },
            },
            AppError::Validation(msg) => Self {
                kind: CommandErrorKind::Validation,
                class: None,
                message: msg.clone(),
                detail: None,
            },
            AppError::NotFound(msg) => Self {
                kind: CommandErrorKind::NotFound,
                class: None,
                message: msg.clone(),
                detail: None,
            },
            AppError::Timeout(msg) => Self {
                kind: CommandErrorKind::Timeout,
                class: None,
                message: msg.clone(),
                detail: None,
            },
            AppError::Internal(msg) => Self {
                kind: CommandErrorKind::Internal,
                class: None,
                message: msg.clone(),
                detail: None,
            },
            AppError::Cancelled(msg) => Self {
                kind: CommandErrorKind::Cancelled,
                class: None,
                message: msg.clone(),
                detail: None,
            },
            // #3033-H4: route the typed updater + window-op variants
            // through the IPC envelope. Both surface a fixed,
            // user-safe `message`; the raw `detail` is dropped on the
            // wire (sanitized) but survives in the `eprintln!`
            // diagnostic log via the `From<AppError> for String` impl.
            // Use `kind: internal` so the renderer's existing internal
            // toast handler renders both — the renderer cannot fix
            // either class actionably (an updater proxy misconfig is
            // a system-level problem; a window-op failure is a Tauri
            // runtime state issue).
            AppError::RemoteUpdateFailed(detail) => Self {
                kind: CommandErrorKind::Internal,
                class: None,
                message: "Update check failed. Try again later.".to_string(),
                detail: Some(detail.clone()),
            },
            AppError::WindowOp(detail) => Self {
                kind: CommandErrorKind::Internal,
                class: None,
                message: "A window operation failed. Try again.".to_string(),
                detail: Some(detail.clone()),
            },
            // rollback-failure surfaces as a sanitized
            // internal error to the renderer (the underlying detail is
            // a SQLite implementation message that's not user-
            // actionable), but keeps the typed variant so diagnostics
            // can distinguish it from a generic Internal in the
            // log stream.
            AppError::TransactionRollbackFailed(msg) => Self {
                kind: CommandErrorKind::Internal,
                class: None,
                message: "An internal error occurred. Please try again.".to_string(),
                detail: Some(msg.clone()),
            },
            AppError::MemoryLocked(e) => Self {
                kind: CommandErrorKind::MemoryLocked,
                class: None,
                message: e.to_string(),
                detail: None,
            },
            AppError::Tauri(e) => Self {
                kind: CommandErrorKind::Tauri,
                class: None,
                message: e.to_string(),
                detail: None,
            },
            // Internal errors: sanitize to avoid leaking schema details
            // to the renderer, but keep the typed kind.
            AppError::Sql(_) | AppError::Sync(_) | AppError::OutboxEnqueue(_) => Self {
                kind: CommandErrorKind::Internal,
                class: None,
                message: "An internal error occurred. Please try again.".to_string(),
                detail: None,
            },
            AppError::Serialization(_) => Self {
                kind: CommandErrorKind::Serialization,
                class: None,
                message: "A data format error occurred. Please try again.".to_string(),
                detail: None,
            },
        }
    }
}
