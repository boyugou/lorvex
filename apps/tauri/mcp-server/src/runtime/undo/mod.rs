//! MCP-side undo token construction.
//!
//! A small vocabulary of pre-state snapshots for destructive / bulk MCP
//! writes whose forward semantics are unrecoverable from the UI alone:
//! `delete_list`, `delete_habit`, `batch_create_tasks`,
//! `batch_update_tasks`, and `set_preference`. Every variant carries
//! enough snapshot data to identify what a reverse write would
//! restore — the deleted row (delete variants), the freshly-created ids
//! to remove (batch_create), the stored patches to re-apply
//! (batch_update), or the prior value (set_preference).
//!
//! Each token is produced inside the MCP handler's SQLite transaction,
//! serialized to JSON via [`McpUndoToken::to_json_string`], persisted
//! into `ai_changelog.undo_token`, and returned in the tool's response.
//! The token is a passive record of the pre-state; there is no outbox
//! hold and no retraction of already-enqueued sync envelopes.

use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Length of the undo-token expiry window, in seconds. Stamped into the
/// token's `expires_at` field so a consumer can tell when the token has
/// aged out. 5 seconds is long enough for a human to register the
/// change and act on the token.
pub(crate) const UNDO_WINDOW_SECONDS: i64 = 5;

/// RFC3339 timestamp at which the undo window closes, written to the
/// token's `expires_at` field.
pub(crate) fn compute_undo_expiry() -> String {
    let now = Utc::now();
    let expires = now + Duration::seconds(UNDO_WINDOW_SECONDS);
    lorvex_domain::format_sync_timestamp(expires)
}

/// Kind discriminator baked into every serialized `McpUndoToken`. It
/// names which reverse write would restore the captured pre-state.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpUndoKind {
    /// `delete_list` — re-insert the list row from `pre_entity_json`.
    DeleteList,
    /// `delete_habit` — re-insert the habit row from `pre_entity_json`.
    /// (Completions + reminder policies stay cascaded-gone: restoring
    /// them is out of scope for the undo window.)
    DeleteHabit,
    /// `batch_create_tasks` — delete every id in `created_ids`.
    BatchCreateTasks,
    /// `batch_update_tasks` — restore each task from the snapshots in
    /// `pre_entities_json`.
    BatchUpdateTasks,
    /// `set_preference` — restore `prior_value_json` for `entity_id`,
    /// or clear the key when the pre-state was absent.
    SetPreference,
}

/// Serialized MCP-side undo metadata. Persisted into
/// `ai_changelog.undo_token` and returned in the MCP tool response.
///
/// Field notes:
/// * `mcp_tool` is the tool name for UI labeling + audit.
/// * `pre_entity_json` carries the full entity row for single-entity
///   delete undos. Null for batch kinds.
/// * `created_ids` is populated on `BatchCreateTasks` only.
/// * `pre_entities_json` is a map of `id → pre-mutation entity JSON`
///   populated on `BatchUpdateTasks` only.
/// * `prior_value_json` is the pre-state `value` for `SetPreference`
///   (null when the key didn't exist before).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct McpUndoToken {
    pub(crate) kind: McpUndoKind,
    pub(crate) mcp_tool: String,
    pub(crate) entity_id: Option<String>,
    pub(crate) expires_at: String,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) pre_entity_json: Option<Value>,

    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(crate) created_ids: Vec<String>,

    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(crate) pre_entities_json: Vec<Value>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) prior_value_json: Option<Value>,

    /// `set_preference` only — whether the key existed pre-mutation.
    /// When false, the revert clears the key instead of restoring a
    /// prior value.
    #[serde(default)]
    pub(crate) had_prior_value: bool,
}

impl McpUndoToken {
    /// Build a delete-single-entity token (delete_list / delete_habit).
    pub(crate) fn delete_entity(
        kind: McpUndoKind,
        mcp_tool: &str,
        entity_id: String,
        pre_entity_json: Value,
        expires_at: String,
    ) -> Self {
        Self {
            kind,
            mcp_tool: mcp_tool.to_string(),
            entity_id: Some(entity_id),
            expires_at,
            pre_entity_json: Some(pre_entity_json),
            created_ids: Vec::new(),
            pre_entities_json: Vec::new(),
            prior_value_json: None,
            had_prior_value: false,
        }
    }

    /// Build a batch-create token capturing the ids freshly minted.
    pub(crate) fn batch_create(created_ids: Vec<String>, expires_at: String) -> Self {
        Self {
            kind: McpUndoKind::BatchCreateTasks,
            mcp_tool: "batch_create_tasks".to_string(),
            entity_id: None,
            expires_at,
            pre_entity_json: None,
            created_ids,
            pre_entities_json: Vec::new(),
            prior_value_json: None,
            had_prior_value: false,
        }
    }

    /// Build a batch-update token capturing the pre-mutation snapshot
    /// of each touched task.
    pub(crate) fn batch_update(pre_entities_json: Vec<Value>, expires_at: String) -> Self {
        Self {
            kind: McpUndoKind::BatchUpdateTasks,
            mcp_tool: "batch_update_tasks".to_string(),
            entity_id: None,
            expires_at,
            pre_entity_json: None,
            created_ids: Vec::new(),
            pre_entities_json,
            prior_value_json: None,
            had_prior_value: false,
        }
    }

    /// Build a set-preference token. `prior_value` is `None` iff the
    /// key did not exist before the write.
    pub(crate) fn set_preference(
        key: String,
        prior_value: Option<Value>,
        expires_at: String,
    ) -> Self {
        let had_prior_value = prior_value.is_some();
        Self {
            kind: McpUndoKind::SetPreference,
            mcp_tool: "set_preference".to_string(),
            entity_id: Some(key),
            expires_at,
            pre_entity_json: None,
            created_ids: Vec::new(),
            pre_entities_json: Vec::new(),
            prior_value_json: prior_value,
            had_prior_value,
        }
    }

    /// Serialize to the JSON string stored in `ai_changelog.undo_token`
    /// and returned in the MCP tool response. Infallible for well-formed
    /// construction; `serde_json` only fails on non-object keys or
    /// cycles, neither of which this struct can produce.
    pub(crate) fn to_json_string(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }
}

#[cfg(test)]
mod tests;
