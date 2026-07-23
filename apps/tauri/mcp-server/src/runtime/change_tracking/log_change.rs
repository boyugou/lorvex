//! The `log_change` write funnel and the preview-only audit row writer.
//!
//! Every mutating MCP tool routes through [`log_change`], which writes
//! the `ai_changelog` row, enqueues the outbox envelopes for both the
//! changelog row and the per-entity payloads, refreshes the widget
//! snapshot, and bumps `local_change_seq`. [`write_preview_audit_entry`]
//! is the sibling for `dispatch_dry_run`-style local-only audit rows,
//! while [`write_local_audit_entry`] records local-only audit rows after
//! another finalizer has already handled invalidation.

use std::collections::HashMap;

use lorvex_domain::naming::ENTITY_PREFERENCE;
use lorvex_runtime::bump_local_change_seq;
use lorvex_store::changelog::{encode_state_json, sanitize_changelog_summary};
use rusqlite::Connection;
use serde_json::{json, Value};

use super::get_or_create_sync_device_id;
use super::outbox::write_to_outbox;
use super::resolve_ai_actor_name;
use super::retention::{enqueue_changelog_to_outbox, read_changelog_retention_days};
use super::snapshot::{read_current_entity_snapshot, read_current_entity_snapshots};
use super::{dedupe_entity_ids, is_delete_sync_operation};
use crate::error::McpError;
use crate::system::handler_support::{new_uuid, utc_now_iso};
fn should_sync_entity(entity_type: &str, entity_id: &str) -> bool {
    !(entity_type == ENTITY_PREFERENCE
        && lorvex_domain::preference_keys::is_local_only_preference(entity_id))
}

/// Parameters for the [`log_change`] funnel.
#[derive(Default)]
pub(crate) struct LogChangeParams {
    pub(crate) operation: &'static str,
    pub(crate) entity_type: &'static str,
    pub(crate) entity_id: Option<String>,
    pub(crate) entity_ids: Option<Vec<String>>,
    pub(crate) summary: String,
    pub(crate) mcp_tool: &'static str,
    /// #2373: pre-mutation JSON snapshot for update operations. Consumers
    /// populate this from a DB read taken BEFORE the mutation so the UI
    /// can reconstruct exactly what changed. Always `None` for
    /// create/delete paths and for operations that don't carry a
    /// meaningful before-state.
    pub(crate) before_json: Option<Value>,
    /// #2373: post-mutation JSON snapshot for update operations. Must be
    /// taken AFTER the DB write but BEFORE [`log_change`] so the stored
    /// `after_json` reflects the row's pre-stamp shape. Always `None`
    /// for delete paths.
    pub(crate) after_json: Option<Value>,
    /// Serialized MCP undo token (see [`crate::runtime::undo`]). When
    /// `Some(..)` the log call persists it into `ai_changelog.undo_token`
    /// as a pre-state snapshot a reverse write can restore from. It does
    /// not affect how the outbox envelopes are enqueued — every envelope
    /// this write emits is immediately dispatchable.
    pub(crate) undo_token: Option<String>,
    /// Opt out of the per-entity sync-emit pass even when `entity_type`
    /// is in `ALL_SYNCABLE_TYPES` and `entity_id` / `entity_ids` are
    /// populated. Used by no-op-mutation surfaces (`reorganize_list`
    /// computes a sort order without touching any row, so emitting an
    /// envelope would stamp a fresh HLC on unchanged participants and
    /// could overwrite concurrent peer edits via LWW). Defaults to
    /// `false`; set to `true` only when the audit row's intent is
    /// "log this read/compute, not a mutation."
    pub(crate) skip_sync_enqueue: bool,
    /// #3033-M4: typed preview discriminator. Set `true` for
    /// preview-shaped surfaces that still route through [`log_change`].
    /// The local-only audit helpers stamp their own preview state.
    /// Defaults to `false`.
    pub(crate) is_preview: bool,
}

pub(crate) struct LocalAuditEntryParams {
    pub(crate) operation: &'static str,
    pub(crate) entity_type: &'static str,
    pub(crate) summary: String,
    pub(crate) mcp_tool: &'static str,
    pub(crate) after_json: Option<Value>,
    pub(crate) is_preview: bool,
}

impl LogChangeParams {
    /// #3629: ergonomic constructor for the four required fields. Every
    /// site open-coded the struct literal with seven
    /// `: None` / `: false` / `: Default::default()` fields just to set
    /// `operation`, `entity_type`, `summary`, and `mcp_tool`. The
    /// builder collapses that boilerplate; optional fields slot in via
    /// the chainable `with_*` methods below.
    pub(crate) fn new(
        operation: &'static str,
        entity_type: &'static str,
        mcp_tool: &'static str,
        summary: impl Into<String>,
    ) -> Self {
        Self {
            operation,
            entity_type,
            mcp_tool,
            summary: summary.into(),
            ..Default::default()
        }
    }

    pub(crate) fn with_entity_id(mut self, id: impl Into<String>) -> Self {
        self.entity_id = Some(id.into());
        self
    }

    pub(crate) fn with_entity_ids(mut self, ids: Vec<String>) -> Self {
        self.entity_ids = Some(ids);
        self
    }

    pub(crate) fn with_before(mut self, before_json: Value) -> Self {
        self.before_json = Some(before_json);
        self
    }

    pub(crate) fn with_after(mut self, after_json: Value) -> Self {
        self.after_json = Some(after_json);
        self
    }

    /// Variant for sites that already hold an `Option<Value>` (e.g. when
    /// `before_json` was computed via `Option::map(...).transpose()?`).
    /// Lets the call site stay declarative without inserting a `match`
    /// to project into `with_before` / `Default`.
    pub(crate) fn with_before_opt(mut self, before_json: Option<Value>) -> Self {
        self.before_json = before_json;
        self
    }

    pub(crate) fn with_undo_token(mut self, token_json: String) -> Self {
        self.undo_token = Some(token_json);
        self
    }

    pub(crate) const fn skip_sync(mut self) -> Self {
        self.skip_sync_enqueue = true;
        self
    }
}

/// Write a local-only MCP audit row without outbox enqueueing or a
/// `local_change_seq` bump.
///
/// Snapshot import uses this after its shared import finalizer has
/// already handled local invalidation and sync reseed bookkeeping. The
/// regular [`log_change`] funnel would bump a second time and may enqueue
/// the changelog row even for a non-syncable `import_session` marker.
pub(crate) fn write_local_audit_entry(
    conn: &Connection,
    params: LocalAuditEntryParams,
) -> Result<(), McpError> {
    crate::runtime::rate_limit::check_write_rate_limit()?;

    let timestamp = utc_now_iso();
    let initiated_by = resolve_ai_actor_name();
    let device_id = get_or_create_sync_device_id(conn)?;
    let sanitized_summary = sanitize_changelog_summary(&params.summary);
    let after_json_str = encode_state_json(params.after_json.as_ref());
    read_changelog_retention_days(conn)?;

    let changelog_id = new_uuid();
    lorvex_store::changelog::write_changelog_row(
        conn,
        &lorvex_store::changelog::ChangelogRow {
            id: &changelog_id,
            timestamp: &timestamp,
            operation: params.operation,
            entity_type: params.entity_type,
            entity_id: None,
            entity_ids: &[],
            summary: &sanitized_summary,
            initiated_by: &initiated_by,
            mcp_tool: Some(params.mcp_tool),
            source_device_id: &device_id,
            before_json: None,
            after_json: after_json_str.as_deref(),
            undo_token: None,
            is_preview: params.is_preview,
        },
    )?;

    Ok(())
}

/// The single MCP write funnel: writes the `ai_changelog` row, enqueues
/// outbox envelopes for both the changelog row and the per-entity
/// payloads, refreshes the widget snapshot, and bumps `local_change_seq`.
///
/// Pass `tombstone_payloads = Some(map)` for delete-cascade flows that
/// captured each entity's pre-delete snapshot before deleting the row;
/// the per-entity outbox writer then prefers the supplied snapshot over
/// `read_current_entity_snapshot`. Pass `None` (the common case) for
/// every non-cascade write — non-delete operations and entities not
/// present in the supplied map fall back to the read+default chain
/// unchanged, so existing call sites retain bit-identical behavior by
/// passing `None`.
pub(crate) fn log_change(
    conn: &Connection,
    params: LogChangeParams,
    tombstone_payloads: Option<&HashMap<String, Value>>,
) -> Result<(), McpError> {
    // #2364: every logged write funnels through this function, so a
    // single rate-limit check here covers every MCP write surface
    // (task mutations, list mutations, habit mutations, memory upserts,
    // preference writes) without touching each
    // handler individually. The check is deliberately placed BEFORE
    // any database work so a rejected write emits zero side effects.
    crate::runtime::rate_limit::check_write_rate_limit()?;

    let timestamp = utc_now_iso();
    let initiated_by = resolve_ai_actor_name();
    let device_id = get_or_create_sync_device_id(conn)?;
    let entity_ids = dedupe_entity_ids(params.entity_id.clone(), params.entity_ids.clone());
    let sync_entity_ids: Vec<String> = entity_ids
        .iter()
        .filter(|entity_id| should_sync_entity(params.entity_type, entity_id))
        .cloned()
        .collect();
    // Sanitize once at the boundary so every call site is covered
    // without a multi-file refactor.
    let sanitized_summary = sanitize_changelog_summary(&params.summary);
    // #2373: serialize + size-cap the optional before/after snapshots.
    let before_json_str = encode_state_json(params.before_json.as_ref());
    let after_json_str = encode_state_json(params.after_json.as_ref());
    // Validate the retention preference early so a malformed preference
    // value surfaces as a clear write error instead of corrupting later
    // cleanup passes. We do NOT gate logging on the preference — the
    // user's choice only governs *cleanup*, not *logging*. ("Forever"
    // means log everything and never clean up.)
    read_changelog_retention_days(conn)?;

    // Destructive/bulk MCP writes attach a serialized undo token that
    // is persisted into `ai_changelog.undo_token` as a pre-state
    // snapshot for a reverse write.
    let undo_token_str: Option<&str> = params.undo_token.as_deref();

    let changelog_id = new_uuid();
    // Delegate the actual INSERT to the canonical writer in
    // `lorvex_store::changelog`. Every column the table carries
    // flows through `ChangelogRow`, so a future schema extension is a
    // single struct addition + one prepare_cached statement, not a
    // parallel update across MCP and CLI.
    lorvex_store::changelog::write_changelog_row(
        conn,
        &lorvex_store::changelog::ChangelogRow {
            id: &changelog_id,
            timestamp: &timestamp,
            operation: params.operation,
            entity_type: params.entity_type,
            entity_id: params.entity_id.as_deref(),
            entity_ids: &entity_ids,
            summary: &sanitized_summary,
            initiated_by: &initiated_by,
            mcp_tool: Some(params.mcp_tool),
            source_device_id: &device_id,
            before_json: before_json_str.as_deref(),
            after_json: after_json_str.as_deref(),
            undo_token: undo_token_str,
            is_preview: params.is_preview,
        },
    )?;

    if entity_ids.is_empty() || !sync_entity_ids.is_empty() {
        enqueue_changelog_to_outbox(conn, &changelog_id)?;
    }

    // Per-entity outbox writes only fire for syncable entity types
    // with a non-empty id set. Non-syncable entities skip this loop
    // but MUST still bump `local_change_seq` below so the Tauri app's
    // poll notices the queued UI command.
    if lorvex_domain::naming::is_syncable_type(params.entity_type)
        && !sync_entity_ids.is_empty()
        && !params.skip_sync_enqueue
    {
        let is_delete = is_delete_sync_operation(params.operation);
        let sync_operation = if is_delete {
            lorvex_domain::naming::OP_DELETE
        } else {
            lorvex_domain::naming::OP_UPSERT
        };

        // Pre-fetch all snapshots in one IN-list SELECT for the entity
        // types that map cleanly to a single-PK row. Delete operations
        // skip the prefetch — the row is already gone by the time the
        // funnel runs, so the SELECT would yield no rows. Caller-
        // supplied `tombstone_payloads` covers this path.
        let prefetched: HashMap<String, Value> = if is_delete {
            HashMap::new()
        } else {
            read_current_entity_snapshots(conn, params.entity_type, &sync_entity_ids)?
        };

        for entity_id in sync_entity_ids {
            // Prefer a caller-supplied pre-delete snapshot over the
            // live re-read for delete operations. For non-delete
            // operations or sites without a tombstone map we fall
            // back to the read+default chain unchanged.
            let snapshot = match (
                is_delete,
                tombstone_payloads.and_then(|m| m.get(&entity_id).cloned()),
            ) {
                (true, Some(supplied)) => supplied,
                _ => match prefetched.get(&entity_id).cloned() {
                    Some(value) => value,
                    None => read_current_entity_snapshot(conn, params.entity_type, &entity_id)?
                        .unwrap_or_else(|| json!({ "id": entity_id })),
                },
            };

            write_to_outbox(
                conn,
                params.entity_type,
                &entity_id,
                sync_operation,
                &snapshot,
                &device_id,
            )?;
        }
    }

    // Bump unconditionally: every successful write through this funnel
    // is something the Tauri app's poll-driven invalidation needs to
    // see, regardless of whether the entity also flows through sync.
    bump_local_change_seq(conn).map_err(|error| {
        McpError::Internal(format!("failed to bump local change sequence: {error}"))
    })?;

    Ok(())
}

/// Dry-run / preview audit row writer (issue #2370).
///
/// Unlike [`log_change`] this helper:
/// - never enqueues an outbox envelope (neither for the changelog row
///   itself nor for the entities the preview would have touched),
/// - never bumps the local change sequence,
/// - uses `operation = "<tool>_preview"` so peers reading the audit
///   feed can tell a preview from a real write, and
/// - still rate-limits through `check_write_rate_limit` so a runaway
///   assistant cannot spam the log.
///
/// The row is intentionally local-only — preview actions are a
/// conversational affordance for the user who sees them in the
/// changelog, not a replicable state transition.
pub(crate) fn write_preview_audit_entry(
    conn: &Connection,
    tool_name: &str,
    entity_type: &str,
    summary: &str,
    entity_ids: &[String],
) -> Result<(), McpError> {
    crate::runtime::rate_limit::check_write_rate_limit()?;

    let timestamp = utc_now_iso();
    let initiated_by = resolve_ai_actor_name();
    let device_id = get_or_create_sync_device_id(conn)?;

    let sanitized_summary = sanitize_changelog_summary(summary);
    // Validate retention preference eagerly, matching the primary
    // changelog write path's behavior.
    read_changelog_retention_days(conn)?;

    let changelog_id = new_uuid();
    let operation = format!("{tool_name}_preview");
    // #3033-M4: stamp the typed `is_preview` discriminator so the
    // changelog reader can filter preview rows structurally rather
    // than via the fragile `operation LIKE '%_preview'` /
    // `mcp_tool LIKE '%_preview'` string match.
    lorvex_store::changelog::write_changelog_row(
        conn,
        &lorvex_store::changelog::ChangelogRow {
            id: &changelog_id,
            timestamp: &timestamp,
            operation: &operation,
            entity_type,
            entity_id: None,
            entity_ids,
            summary: &sanitized_summary,
            initiated_by: &initiated_by,
            mcp_tool: Some(tool_name),
            source_device_id: &device_id,
            before_json: None,
            after_json: None,
            undo_token: None,
            is_preview: true,
        },
    )?;

    // Deliberately skip `enqueue_changelog_to_outbox` — a preview is
    // local audit only. Peers only ever see the real write that
    // follows (or never, if the user cancels), not the preview itself.

    Ok(())
}
