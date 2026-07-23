//! Undo token wire format and TTL validation.
//!
//! The [`EntityUndoToken`] is the opaque JSON blob that round-trips
//! through the frontend during a delete-undo flow. It carries the
//! pre-delete [`EntitySnapshot`] plus a short `expires_at` TTL so a
//! stale token (a refresh after the toast hold, a replay attack) is
//! rejected before any restore work is attempted.

use serde::{Deserialize, Serialize};

use crate::commands::TaskList;
use crate::error::{AppError, AppResult};

use super::super::CalendarEvent;

/// Window after which an undo token is no longer accepted.
///
/// Matches the frontend toast hold (~5s, see #3361 for the 5500ms
/// post-#3361 alignment) plus a small grace margin so an in-flight click
/// at the very end of the toast lifetime still completes.
const UNDO_TTL_SECONDS: i64 = 10;

/// Discriminator for the snapshot payload.
///
/// `#3420` extended this to lists. Lists are simpler than calendar
/// events because `delete_list` rejects deletion when any task is
/// still assigned, so there are no edges to replay — just the row.
///
/// The `CalendarEvent` payload is boxed (#3423) because `CalendarEvent`
/// is ~416 bytes while `TaskList` is ~192 bytes, which trips
/// `clippy::large_enum_variant`. `Box<T>` serializes transparently, so
/// the wire format is unchanged.
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EntitySnapshot {
    CalendarEvent {
        event: Box<CalendarEvent>,
        linked_task_ids: Vec<String>,
    },
    List {
        list: TaskList,
    },
}

/// Self-contained undo envelope round-tripped through the frontend.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct EntityUndoToken {
    pub snapshot: EntitySnapshot,
    pub expires_at: String,
}

fn compute_undo_expiry() -> String {
    let now = chrono::Utc::now();
    let until = now + chrono::Duration::seconds(UNDO_TTL_SECONDS);
    lorvex_domain::format_sync_timestamp(until)
}

/// Parse a serialized token and reject it if past its TTL. A malformed
/// JSON payload or unparseable `expires_at` surfaces as
/// `AppError::Validation` so the caller can distinguish replay/staleness
/// from real internal failures.
pub(super) fn parse_and_validate_token(token_str: &str) -> AppResult<EntityUndoToken> {
    let token: EntityUndoToken = serde_json::from_str(token_str)
        .map_err(|e| AppError::Validation(format!("Invalid undo token: {e}")))?;
    let expires_at = chrono::DateTime::parse_from_rfc3339(&token.expires_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .map_err(|e| AppError::Validation(format!("Invalid expires_at in undo token: {e}")))?;
    if chrono::Utc::now() > expires_at {
        return Err(AppError::Validation("Undo window has expired".to_string()));
    }
    Ok(token)
}

/// Build a serialized undo token from a captured snapshot. The TTL is
/// stamped at build time, so the toast window starts counting from the
/// moment the delete handler captured the row, not from any later
/// frontend interaction.
pub(crate) fn build_undo_token(snapshot: EntitySnapshot) -> AppResult<String> {
    let token = EntityUndoToken {
        snapshot,
        expires_at: compute_undo_expiry(),
    };
    serde_json::to_string(&token).map_err(AppError::from)
}
