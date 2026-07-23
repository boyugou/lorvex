use super::super::{
    default_get_list_limit, default_list_health_limit, IDEMPOTENCY_KEY_DESCRIPTION,
};
use schemars::JsonSchema;

// the `IDEMPOTENCY_KEY_DESCRIPTION` const lives in
// `server_contract.rs` (single source of truth) and every list-write
// surface re-uses it.
// (etc.) re-emitted audit + sync envelopes for the duplicate call;
// the cache shorts subsequent identical retries within ~24h.

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct CreateListArgs {
    #[schemars(description = "List name")]
    pub(crate) name: String,
    #[schemars(description = "Hex color")]
    pub(crate) color: Option<String>,
    #[schemars(description = "List icon")]
    pub(crate) icon: Option<String>,
    #[schemars(description = "List description")]
    pub(crate) description: Option<String>,
    #[schemars(description = "AI-only list scope/profile notes")]
    pub(crate) ai_notes: Option<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct UpdateListArgs {
    #[schemars(description = "List ID")]
    pub(crate) id: String,
    #[schemars(description = "New list name")]
    pub(crate) name: Option<String>,
    #[schemars(description = "Hex color. Use null to clear.")]
    #[serde(default, skip_serializing_if = "lorvex_domain::Patch::is_unset")]
    pub(crate) color: lorvex_domain::Patch<String>,
    #[schemars(description = "List icon. Use null to clear.")]
    #[serde(default, skip_serializing_if = "lorvex_domain::Patch::is_unset")]
    pub(crate) icon: lorvex_domain::Patch<String>,
    #[schemars(description = "List description. Use null to clear.")]
    #[serde(default, skip_serializing_if = "lorvex_domain::Patch::is_unset")]
    pub(crate) description: lorvex_domain::Patch<String>,
    #[schemars(description = "AI-only list scope/profile notes. Use null to clear.")]
    #[serde(default, skip_serializing_if = "lorvex_domain::Patch::is_unset")]
    pub(crate) ai_notes: lorvex_domain::Patch<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum ReorganizeListStrategy {
    Deadline,
    Priority,
    Manual,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct ReorganizeListArgs {
    #[schemars(description = "List ID to reorganize")]
    pub(crate) id: String,
    #[schemars(
        description = "Sort strategy: priority (by priority + due_date), deadline (by due_date), manual (provide a full ordered permutation of every open task ID in the list)"
    )]
    pub(crate) strategy: ReorganizeListStrategy,
    #[schemars(
        description = "Required when strategy='manual': full ordered array of every open task ID in the list. Use [] only when the list currently has no open tasks."
    )]
    pub(crate) task_ids: Option<Vec<String>>,
    #[schemars(
        description = "Issue #2370: if true, compute the reorganize plan, return the would-be response with `dry_run: true`, and roll back without logging a normal changelog or emitting sync envelopes. Still writes a single `reorganize_list_preview` audit row so the user sees the preview happened. Default false."
    )]
    // schemars must mirror serde's default so
    // strict assistant clients don't reject calls that omit the
    // field.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

// #3607 — derive intentionally dropped: production accepts the
// `'inbox'` literal as a valid list_id, while the prior `#[validate(uuid)]`
// attribute would have rejected it. The runtime contract is membership
// (validate_list_exists), not UUID shape; dropping the derive keeps a
// single source of truth.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct DeleteListArgs {
    #[schemars(description = "List ID")]
    pub(crate) id: String,
    #[schemars(
        description = "Issue #2370: if true, compute the would-be deletion (validation + cascade counts), return the shape with `dry_run: true`, and roll back without persisting changes. Default false."
    )]
    // see `ReorganizeListArgs::dry_run`.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

// #3607 — derive intentionally dropped: see `DeleteListArgs`.
// Production accepts `'inbox'` as a valid list_id and the runtime is
// membership-based via `validate_list_exists`.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCancelTasksInListArgs {
    #[schemars(description = "List ID whose tasks to cancel")]
    pub(crate) list_id: String,
    #[schemars(
        description = "Only cancel tasks with these statuses (default: open only). Valid: open, completed, cancelled, someday"
    )]
    pub(crate) statuses: Option<Vec<super::TaskStatusValue>>,
    #[schemars(
        description = "If true, stop entire recurring series (clear recurrence fields, no successor). Default false (skip this occurrence, spawn next)."
    )]
    pub(crate) cancel_series: Option<bool>,
    #[schemars(
        description = "Issue #2370: if true, return the would-be cancellation shape (including per-task ids that would be cancelled and any recurrence successors that would be spawned) with `dry_run: true`, and roll back without persisting changes. Default false."
    )]
    // see `ReorganizeListArgs::dry_run`.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

/// Pagination args for `list_lists`. #3019-M1 closed the gap where
/// the tool returned every list at once with no `limit` or `offset` —
/// a workspace with hundreds of lists had no way to walk the catalog
/// in pages.
#[derive(Debug, Default, serde::Deserialize, JsonSchema)]
pub(crate) struct ListListsArgs {
    #[serde(default)]
    #[schemars(
        default,
        description = "Maximum number of lists to return. Default 100 (hard cap 1000).",
        range(min = 1, max = 1000)
    )]
    pub(crate) limit: u32,
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset for stable pagination. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

// #3607 — derive intentionally dropped: see `DeleteListArgs`.
#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetListArgs {
    #[schemars(description = "List ID")]
    pub(crate) id: String,
    #[serde(default = "default_get_list_limit")]
    #[schemars(
        description = "Maximum number of tasks to return. Default 250 (hard cap 1000).",
        default = "default_get_list_limit",
        range(min = 1, max = 1000)
    )]
    pub(crate) limit: u32,
    // #3029-M2: paginate the per-list task page so >1000-task
    // lists (and now even retention-windowed snapshots) stop
    // silently truncating beyond the limit. The shape mirrors
    // `ListListsArgs`: zero-based offset + canonical
    // `next_offset` slot in the response.
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset for stable pagination over the list's tasks. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetListHealthSnapshotArgs {
    #[serde(default = "default_list_health_limit")]
    #[schemars(
        description = "Maximum number of lists to return. Default 50 (hard cap 200).",
        default = "default_list_health_limit",
        range(min = 1, max = 200)
    )]
    pub(crate) limit: u32,
    // #3029-M2: paginate the lists window so workspaces with
    // >200 lists can walk past the hard cap. Same shape as the
    // sibling `GetListArgs.offset`.
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset for stable pagination over lists. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}
