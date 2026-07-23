//! Canonical archive / restore mutations for tasks.
//!
//! Soft-delete (archive) and restore are LWW-stamped writes on the
//! parent task row. They live in `lorvex-workflow` so every surface
//! (Tauri app, CLI, MCP, sync apply pipeline) shares one SQL site that
//! stamps `version`, `updated_at`, and `archived_at` together. Pre-
//! migration the Tauri app issued the raw UPDATE inline, which made
//! the contract verifier trivially regressable.
//!
//! Each op is gated by `?version > version` so a stale stamp from a
//! delayed caller cannot clobber a fresher peer write — zero rows
//! changed surfaces as [`StoreError::StaleVersion`] (or `NotFound`
//! when the row is missing the expected sentinel state) so the
//! surface adapter can map it to its own typed conflict error.

use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::{params, Connection, OptionalExtension};

/// Soft-delete a task by stamping `archived_at`. Requires the row to
/// be currently un-archived; returns [`StoreError::Validation`] if it
/// is already in the Trash and [`StoreError::NotFound`] if the id has
/// no row.
pub fn archive_task_op(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let archived_at: Option<Option<String>> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .optional()?;
    match archived_at {
        None => Err(StoreError::NotFound {
            entity: "task",
            id: task_id.as_str().to_string(),
        }),
        Some(Some(_)) => Err(StoreError::Validation(format!(
            "Task '{}' is already in the Trash",
            task_id.as_str()
        ))),
        Some(None) => {
            let rows = conn.execute(
                "UPDATE tasks SET archived_at = ?1, updated_at = ?1, version = ?2 \
                 WHERE id = ?3 AND archived_at IS NULL AND ?2 > version",
                params![now, version, task_id],
            )?;
            if rows == 0 {
                return Err(StoreError::StaleVersion {
                    entity: "task",
                    id: task_id.as_str().to_string(),
                });
            }
            Ok(())
        }
    }
}

/// Restore a previously-archived task by clearing `archived_at`.
/// Inverse of [`archive_task_op`]. Returns [`StoreError::Validation`]
/// if the row is not in the Trash and [`StoreError::NotFound`] if the
/// id has no row.
pub fn restore_task_op(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let archived_at: Option<Option<String>> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .optional()?;
    match archived_at {
        None => Err(StoreError::NotFound {
            entity: "task",
            id: task_id.as_str().to_string(),
        }),
        Some(None) => Err(StoreError::Validation(format!(
            "Task '{}' is not in the Trash",
            task_id.as_str()
        ))),
        Some(Some(_)) => {
            let rows = conn.execute(
                "UPDATE tasks SET archived_at = NULL, updated_at = ?1, version = ?2 \
                 WHERE id = ?3 AND archived_at IS NOT NULL AND ?2 > version",
                params![now, version, task_id],
            )?;
            if rows == 0 {
                return Err(StoreError::StaleVersion {
                    entity: "task",
                    id: task_id.as_str().to_string(),
                });
            }
            Ok(())
        }
    }
}
