use super::*;
use crate::commands::shared::reject_traversing_or_relative_path;
use crate::error::{AppError, AppResult};

pub(crate) fn resolve_filesystem_bridge_root_path(raw: &str) -> AppResult<PathBuf> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(AppError::Validation(
            "filesystem-bridge root path cannot be empty".to_string(),
        ));
    }

    let resolved = if trimmed == "~" {
        dirs::home_dir()
            .ok_or_else(|| AppError::Internal("Unable to resolve home directory".to_string()))?
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        let home = dirs::home_dir()
            .ok_or_else(|| AppError::Internal("Unable to resolve home directory".to_string()))?;
        home.join(rest)
    } else {
        PathBuf::from(trimmed)
    };

    // After `~` expansion the path must be absolute and free of `..`
    // components and symlinked entries — same rule that
    // `data_snapshot::import` enforces, so a malformed IPC string that
    // slips a relative path through can't redirect the bridge root to
    // an attacker-controlled location below the working directory.
    reject_traversing_or_relative_path(&resolved, "filesystem-bridge root path")
        .map_err(AppError::Validation)?;

    Ok(resolved)
}
