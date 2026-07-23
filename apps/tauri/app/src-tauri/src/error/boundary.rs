use super::envelope::{CommandError, CommandErrorKind};
use super::types::AppError;

impl From<AppError> for String {
    fn from(error: AppError) -> Self {
        let command_error = CommandError::from_app_error(&error);
        append_app_error_boundary_log_best_effort(&error, &command_error);
        command_error.to_ipc_string()
    }
}

fn append_app_error_boundary_log_best_effort(error: &AppError, command_error: &CommandError) {
    if should_skip_app_error_boundary_log(command_error) {
        return;
    }
    crate::commands::diagnostics::try_append_error_log_best_effort(
        "app.command_error.boundary",
        "Tauri command returned diagnostic error",
        Some(app_error_boundary_details(error, command_error)),
        Some("error".to_string()),
    );
}

#[cfg(test)]
pub(super) fn append_app_error_boundary_log(
    conn: &rusqlite::Connection,
    error: &AppError,
    command_error: &CommandError,
) {
    if should_skip_app_error_boundary_log(command_error) {
        return;
    }
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "app.command_error.boundary",
        "Tauri command returned diagnostic error",
        Some(app_error_boundary_details(error, command_error)),
        Some("error".to_string()),
    );
}

const fn should_skip_app_error_boundary_log(command_error: &CommandError) -> bool {
    matches!(
        command_error.kind,
        CommandErrorKind::Validation
            | CommandErrorKind::NotFound
            | CommandErrorKind::Cancelled
            | CommandErrorKind::MemoryLocked
    )
}

fn app_error_boundary_details(error: &AppError, command_error: &CommandError) -> String {
    let class = command_error.class.unwrap_or("none");
    let detail = command_error.detail.as_deref().unwrap_or("none");
    format!(
        "kind={}; class={class}; variant={}; message={}; detail={detail}; error={error}",
        command_error_kind_tag(&command_error.kind),
        app_error_variant_name(error),
        command_error.message,
    )
}

const fn command_error_kind_tag(kind: &CommandErrorKind) -> &'static str {
    match kind {
        CommandErrorKind::Validation => "validation",
        CommandErrorKind::NotFound => "not_found",
        CommandErrorKind::DiskFull => "disk_full",
        CommandErrorKind::Timeout => "timeout",
        CommandErrorKind::Tauri => "tauri",
        CommandErrorKind::Serialization => "serialization",
        CommandErrorKind::Internal => "internal",
        CommandErrorKind::Cancelled => "cancelled",
        CommandErrorKind::MemoryLocked => "memory_locked",
    }
}

fn app_error_variant_name(error: &AppError) -> &'static str {
    match error {
        AppError::DiskFull(_) => "DiskFull",
        AppError::Store(boxed) => match boxed.as_ref() {
            lorvex_store::StoreError::DiskFull { .. } => "StoreDiskFull",
            lorvex_store::StoreError::Validation(_) => "StoreValidation",
            lorvex_store::StoreError::NotFound { .. } => "StoreNotFound",
            lorvex_store::StoreError::StaleVersion { .. } => "StoreStaleVersion",
            _ => "Store",
        },
        AppError::Sync(_) => "Sync",
        AppError::OutboxEnqueue(_) => "OutboxEnqueue",
        AppError::Sql(_) => "Sql",
        AppError::Tauri(_) => "Tauri",
        AppError::Validation(_) => "Validation",
        AppError::NotFound(_) => "NotFound",
        AppError::Serialization(_) => "Serialization",
        AppError::Internal(_) => "Internal",
        AppError::TransactionRollbackFailed(_) => "TransactionRollbackFailed",
        AppError::Timeout(_) => "Timeout",
        AppError::Cancelled(_) => "Cancelled",
        AppError::RemoteUpdateFailed(_) => "RemoteUpdateFailed",
        AppError::WindowOp(_) => "WindowOp",
        AppError::MemoryLocked(_) => "MemoryLocked",
    }
}
