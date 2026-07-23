use serde::{Deserialize, Serialize};

use lorvex_domain::naming::TaskStatus;

use crate::{commands::Task, error::AppError};

/// Lifecycle mutation that can be undone via [`UndoToken`].
///
/// The closed 3-value action set is a typed enum so the dispatch is
/// exhaustive and a rename of any variant cascades through the type
/// system. Serde `rename_all = "snake_case"` keeps the wire format
/// byte-identical to a stringly-typed `action: String` shape, which
/// would otherwise let each dispatch site fall back on
/// `match action.as_str()` and silently drift on a rename.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleAction {
    Complete,
    Cancel,
    Update,
}

impl LifecycleAction {
    pub const fn as_str(self) -> &'static str {
        match self {
            LifecycleAction::Complete => "complete",
            LifecycleAction::Cancel => "cancel",
            LifecycleAction::Update => "update",
        }
    }
}

impl std::fmt::Display for LifecycleAction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Serialized undo context returned to the frontend.
#[derive(Debug, Serialize, Deserialize)]
pub struct UndoToken {
    pub task_id: String,
    /// Lifecycle mutation being undone. Typed enum.
    pub action: LifecycleAction,
    /// Original cancel-series flag for cancel lifecycle mutations.
    /// Defaults false so older in-flight tokens remain single-task
    /// cancels.
    #[serde(default)]
    pub cancel_series: bool,
    /// Pre-mutation task status. Typed [`TaskStatus`] instead of a
    /// bare string so a malformed `pre_status` cannot be persisted
    /// into the token JSON and silently survive until the undo path
    /// tries to write it back.
    pub pre_status: TaskStatus,
    pub pre_completed_at: Option<String>,
    pub pre_planned_date: Option<String>,
    pub pre_defer_count: i64,
    pub pre_last_deferred_at: Option<String>,
    pub pre_last_defer_reason: Option<String>,
    pub spawned_successor_id: Option<String>,
    pub cancelled_reminder_ids: Vec<String>,
    pub deleted_dep_edges: Vec<(String, String)>,
    pub affected_dependent_ids: Vec<String>,
    pub expires_at: String,
    /// Full pre-mutation task snapshot used by the [`LifecycleAction::Update`]
    /// action (#2538). Unused by the `Complete` / `Cancel` paths which
    /// rely on the narrower `pre_*` fields above. Stored as the
    /// `Task` JSON shape (including tags, depends_on, etc.) so the
    /// undo restore can re-issue `update_task_internal` with every
    /// originally-updatable field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pre_task_snapshot: Option<serde_json::Value>,
}

/// Result of complete_task / cancel_task with undo support.
#[derive(Debug, Serialize)]
pub struct TaskWithUndo {
    pub task: Task,
    pub undo_token: String,
}

/// Serialized redo context returned to the frontend after a successful
/// undo. A redo re-applies the original lifecycle action (complete or
/// cancel), and the resulting mutation itself gets a fresh `undo_token`
/// — i.e. one level of back-and-forth between undo and redo.
///
/// Intentionally narrow: captures only what's needed to re-invoke the
/// forward mutation through the same pipeline that built the original
/// undo token. Does NOT attempt to re-create the exact same recurrence
/// successor IDs — re-running `complete_task_inner` / `cancel_task_inner`
/// spawns fresh successors, which is the semantically correct
/// interpretation of "redo the completion".
///
/// Encode the coupling between `action` and `cancel_series` as a
/// sum type: `cancel_series` only exists inside the `Cancel` variant,
/// so a tampered "complete with series=true" token fails to
/// deserialize at the wire boundary. A flat
/// `{ task_id, action: LifecycleAction, cancel_series: Option<bool>, expires_at }`
/// shape would let the frontend or a tampered persisted token parse
/// `action: Complete` + `cancel_series: Some(true)` cleanly, and the
/// dispatch would silently ignore `cancel_series` on the complete
/// arm with no compiler signal that a field coupling had been
/// violated.
#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "action", rename_all = "snake_case")]
pub(super) enum RedoToken {
    /// Redo a `complete_task` — re-invokes `complete_task_inner` which
    /// has no series concept (recurrence successors are spawned
    /// post-complete by the same pipeline).
    Complete { task_id: String, expires_at: String },
    /// Redo a `cancel_task` — re-invokes `cancel_task_inner` with the
    /// series flag preserved. Series-cancel redo (`cancel_series:
    /// true`) is intentionally allowed by the token shape so a future
    /// caller that opts in surfaces the right re-invocation; the
    /// current `redo_task_lifecycle` IPC preserves the original
    /// `cancel_series` decision from the undo token.
    Cancel {
        task_id: String,
        cancel_series: bool,
        expires_at: String,
    },
}

impl RedoToken {
    pub(super) const fn task_id(&self) -> &str {
        match self {
            RedoToken::Complete { task_id, .. } | RedoToken::Cancel { task_id, .. } => {
                task_id.as_str()
            }
        }
    }

    const fn expires_at(&self) -> &str {
        match self {
            RedoToken::Complete { expires_at, .. } | RedoToken::Cancel { expires_at, .. } => {
                expires_at.as_str()
            }
        }
    }

    /// Project to the matching [`LifecycleAction`] discriminant for
    /// test assertions that compare token shape against the lifecycle
    /// enum. Production dispatch matches `RedoToken` variants
    /// directly and does not need this projection.
    #[cfg(test)]
    pub const fn lifecycle_action(&self) -> LifecycleAction {
        match self {
            RedoToken::Complete { .. } => LifecycleAction::Complete,
            RedoToken::Cancel { .. } => LifecycleAction::Cancel,
        }
    }
}

/// Result of `undo_task_lifecycle` — the restored task plus a redo
/// token the UI can surface to let the user re-apply the original
/// mutation within a short window.
#[derive(Debug, Serialize)]
pub struct TaskWithRedo {
    pub task: Task,
    pub redo_token: Option<String>,
}

/// Length of the user-visible undo window: an undo token expires this
/// many seconds after the mutation that minted it.
const UNDO_WINDOW_SECONDS: i64 = 5;

/// Compute the undo token expiry timestamp (now + [`UNDO_WINDOW_SECONDS`])
/// in the shared canonical sync timestamp form.
pub(crate) fn compute_undo_expiry() -> String {
    let now = chrono::Utc::now();
    let expires = now + chrono::Duration::seconds(UNDO_WINDOW_SECONDS);
    lorvex_domain::format_sync_timestamp(expires)
}

/// Build a serialized UndoToken from pre-mutation task state and mutation results.
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_undo_token(
    task: &Task,
    action: LifecycleAction,
    cancel_series: bool,
    spawned_successor_id: Option<String>,
    cancelled_reminder_ids: Vec<String>,
    deleted_dep_edges: Vec<(String, String)>,
    affected_dependent_ids: Vec<String>,
    expires_at: &str,
) -> Result<String, AppError> {
    // Parse the bare `task.status` string into a typed `TaskStatus`
    // at the boundary so the undo token can never carry a
    // stringly-invalid status. Without this check a corrupt status
    // column would round-trip through the token JSON unchallenged
    // and only blow up when the undo handler tried to write it back
    // via `apply_single_undo_with_retracted_groups`.
    let pre_status = TaskStatus::parse(&task.status).ok_or_else(|| {
        AppError::Validation(format!(
            "Cannot build undo token for task {}: pre-mutation status '{}' is not a known TaskStatus",
            task.id, task.status
        ))
    })?;
    let token = UndoToken {
        task_id: task.id.clone(),
        action,
        cancel_series,
        pre_status,
        pre_completed_at: task.completed_at.clone(),
        pre_planned_date: task.planned_date.clone(),
        pre_defer_count: task.defer_count,
        pre_last_deferred_at: task.last_deferred_at.clone(),
        pre_last_defer_reason: task.last_defer_reason.map(|r| r.as_str().to_string()),
        spawned_successor_id,
        cancelled_reminder_ids,
        deleted_dep_edges,
        affected_dependent_ids,
        expires_at: expires_at.to_string(),
        pre_task_snapshot: None,
    };
    serde_json::to_string(&token).map_err(AppError::from)
}

/// Build an `UndoToken` for an `update_task` mutation (#2538). Captures a
/// full JSON snapshot of the pre-mutation task (enriched with tags +
/// depends_on) so the undo consumer can re-run `update_task_internal`
/// with every originally-updatable field restored. The narrower `pre_*`
/// columns are populated with the pre-state as a courtesy; they are not
/// consulted when `action == "update"`.
pub(crate) fn build_update_undo_token(
    pre_task: &Task,
    expires_at: &str,
) -> Result<String, AppError> {
    let snapshot = serde_json::to_value(pre_task).map_err(AppError::from)?;
    let pre_status = TaskStatus::parse(&pre_task.status).ok_or_else(|| {
        AppError::Validation(format!(
            "Cannot build update-undo token for task {}: pre-mutation status '{}' is not a known TaskStatus",
            pre_task.id, pre_task.status
        ))
    })?;
    let token = UndoToken {
        task_id: pre_task.id.clone(),
        action: LifecycleAction::Update,
        cancel_series: false,
        pre_status,
        pre_completed_at: pre_task.completed_at.clone(),
        pre_planned_date: pre_task.planned_date.clone(),
        pre_defer_count: pre_task.defer_count,
        pre_last_deferred_at: pre_task.last_deferred_at.clone(),
        pre_last_defer_reason: pre_task.last_defer_reason.map(|r| r.as_str().to_string()),
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: expires_at.to_string(),
        pre_task_snapshot: Some(snapshot),
    };
    serde_json::to_string(&token).map_err(AppError::from)
}

/// Build a serialized redo token capturing the minimum state the redo
/// pipeline needs to re-invoke the forward lifecycle mutation.
///
/// The redo itself runs through the ordinary `complete_task_inner` /
/// `cancel_task_inner` pipeline, which emits its own fresh undo token
/// — so the redo token is intentionally small and does NOT duplicate
/// the per-mutation state held inside `UndoToken`.
pub(super) fn build_redo_token(
    undo: &UndoToken,
    expires_at: &str,
) -> Result<Option<String>, AppError> {
    // the sum-typed `RedoToken` enforces the
    // coupling between `action` and `cancel_series` at the type
    // level. Update undos are one-way and therefore surface no redo token.
    let token = match undo.action {
        LifecycleAction::Complete => RedoToken::Complete {
            task_id: undo.task_id.clone(),
            expires_at: expires_at.to_string(),
        },
        LifecycleAction::Cancel => RedoToken::Cancel {
            task_id: undo.task_id.clone(),
            cancel_series: undo.cancel_series,
            expires_at: expires_at.to_string(),
        },
        LifecycleAction::Update => return Ok(None),
    };
    serde_json::to_string(&token)
        .map(Some)
        .map_err(AppError::from)
}

/// Parse and validate a redo token string, checking expiry.
pub(super) fn parse_and_validate_redo_token(token_str: &str) -> Result<RedoToken, AppError> {
    let redo: RedoToken = serde_json::from_str(token_str)
        .map_err(|e| AppError::Validation(format!("Invalid redo token: {e}")))?;

    validate_lifecycle_token_expiry(
        redo.expires_at(),
        LifecycleTokenKind::Redo,
        redo.task_id(),
        chrono::Utc::now(),
    )?;

    Ok(redo)
}

/// Parse and validate an undo token string, checking expiry.
pub(super) fn parse_and_validate_undo_token(token_str: &str) -> Result<UndoToken, AppError> {
    let undo: UndoToken = serde_json::from_str(token_str)
        .map_err(|e| AppError::Validation(format!("Invalid undo token: {e}")))?;

    validate_lifecycle_token_expiry(
        &undo.expires_at,
        LifecycleTokenKind::Undo,
        &undo.task_id,
        chrono::Utc::now(),
    )?;

    Ok(undo)
}

#[derive(Debug, Clone, Copy)]
pub(super) enum LifecycleTokenKind {
    Undo,
    Redo,
}

impl LifecycleTokenKind {
    const fn lower(self) -> &'static str {
        match self {
            LifecycleTokenKind::Undo => "undo",
            LifecycleTokenKind::Redo => "redo",
        }
    }

    const fn title(self) -> &'static str {
        match self {
            LifecycleTokenKind::Undo => "Undo",
            LifecycleTokenKind::Redo => "Redo",
        }
    }
}

pub(super) fn validate_lifecycle_token_expiry(
    expires_raw: &str,
    kind: LifecycleTokenKind,
    task_id: &str,
    now: chrono::DateTime<chrono::Utc>,
) -> Result<(), AppError> {
    let expires_at = parse_lifecycle_token_expiry(expires_raw, kind)?;
    if now > expires_at {
        return Err(AppError::Validation(format!(
            "{} window has expired for task {}",
            kind.title(),
            task_id
        )));
    }
    Ok(())
}

fn parse_lifecycle_token_expiry(
    expires_raw: &str,
    kind: LifecycleTokenKind,
) -> Result<chrono::DateTime<chrono::Utc>, AppError> {
    chrono::DateTime::parse_from_rfc3339(expires_raw)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .or_else(|_| {
            chrono::NaiveDateTime::parse_from_str(expires_raw, "%Y-%m-%dT%H:%M:%S%.3fZ")
                .map(|dt| dt.and_utc())
        })
        .map_err(|e| {
            AppError::Validation(format!("Invalid expires_at in {} token: {e}", kind.lower()))
        })
}
