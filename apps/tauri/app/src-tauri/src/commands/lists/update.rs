//! `update_list` IPC command — typed
//! [`lorvex_workflow::mutation::Mutation`] descriptor wrapping the
//! shared `list_repo::update_list_patched` call. Routes through
//! [`crate::commands::shared::effects::execute_ipc_entity_mutation`]
//! so the row UPDATE + LWW guard, outbox enqueue,
//! `local_change_seq` bump, and event-bus broadcast all share one
//! HLC session.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_LIST, OP_UPSERT};
use lorvex_domain::Patch;
use lorvex_store::repositories::list_repo::ListUpdatePatch;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::shared::effects::execute_ipc_entity_mutation;
use crate::commands::{
    enqueue_list_upsert, fetch_list_by_id, sync_timestamp_now, with_immediate_transaction, TaskList,
};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

use super::reload_list_as_task_list;

#[derive(Debug, serde::Deserialize)]
pub struct UpdateListArgs {
    id: String,
    name: Option<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    color: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    icon: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    description: Patch<String>,
}

/// Validated, sanitized arguments for the descriptor.
struct UpdateListMutation<'a> {
    id: &'a lorvex_domain::ListId,
    name: Option<&'a str>,
    color: Patch<&'a str>,
    icon: Patch<&'a str>,
    description: Patch<&'a str>,
    now: &'a str,
}

impl<'a> Mutation for UpdateListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        // The Tauri surface has no audit funnel that consumes
        // `before_json`, so skip the snapshot read on the hot path.
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let patch = ListUpdatePatch {
            name: self.name,
            color: self.color.clone(),
            icon: self.icon.clone(),
            description: self.description.clone(),
            ai_notes: Patch::Unset,
        };
        // `update_list_patched` raises `StoreError::StaleVersion`
        // directly when the LWW guard rejects the write (#3389).
        // Empty patches return `Ok(())` from the store layer (no SQL
        // runs), so the surrounding executor still owns the
        // outbox-skip decision.
        lorvex_store::repositories::list_repo::update_list_patched(
            conn, self.id, &patch, &version, self.now,
        )?;
        let summary = format!("Updated list '{}'", self.id.as_str());
        Ok(MutationOutput::new(
            serde_json::json!({ "id": self.id.as_str() }),
            summary,
        ))
    }
}

pub(crate) fn update_list_with_conn(
    conn: &rusqlite::Connection,
    args: UpdateListArgs,
) -> AppResult<TaskList> {
    let UpdateListArgs {
        id,
        name,
        color,
        icon,
        description,
    } = args;
    // Unicode hygiene (#2427): scrub free-text fields before validation.
    let name = name.map(|n| lorvex_domain::sanitize_user_text(&n).trim().to_string());
    let description: Patch<String> = description.map(|s| lorvex_domain::sanitize_user_text(&s));
    if let Some(ref n) = name {
        if n.is_empty() {
            return Err(AppError::Validation(
                "list name must not be empty".to_string(),
            ));
        }
        crate::invariants::validation::validate_list_name(n)?;
    }
    crate::invariants::validation::validate_list_description(
        description.as_deref().as_bind_value().copied(),
    )?;
    // enforce `#rrggbb` hex shape on the Tauri update
    // path so MCP / CLI / Tauri all accept the same color syntax.
    crate::invariants::validation::validate_color_hex(color.as_deref().as_bind_value().copied())?;
    crate::invariants::validation::validate_short_text(
        icon.as_deref().as_bind_value().copied(),
        "icon",
    )?;

    let has_patch = name.is_some()
        || color.is_set_or_clear()
        || icon.is_set_or_clear()
        || description.is_set_or_clear();
    let now = sync_timestamp_now();
    let id_typed = lorvex_domain::ListId::from_trusted(id.clone());
    let id_for_reload = id.clone();

    let list = with_immediate_transaction(conn, |conn| {
        fetch_list_by_id(conn, &id)?
            .ok_or_else(|| AppError::NotFound(format!("List {id} not found")))?;

        let mutation = UpdateListMutation {
            id: &id_typed,
            name: name.as_deref(),
            color: color.as_deref(),
            icon: icon.as_deref(),
            description: description.as_deref(),
            now: &now,
        };
        execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
            if !has_patch {
                return Ok(());
            }
            let list = reload_list_as_task_list(conn, &id_for_reload)?;
            enqueue_list_upsert(conn, &list)?;
            Ok(())
        })?;
        reload_list_as_task_list(conn, &id_for_reload)
    })?;

    // Post-commit: keep task search descriptions in sync after list metadata
    // changes via the shared reindex dispatcher.
    crate::commands::shared::reindex_list_after_metadata_change(conn, id);
    Ok(list)
}

#[tauri::command]
pub fn update_list(args: UpdateListArgs) -> Result<TaskList, String> {
    // shape-check the list id at the IPC boundary so a
    // malformed (post-trim) id never reaches the writer transaction.
    // this is a list-id field, so accept the
    // `INBOX_LIST_ID` sentinel (the canonical default list) too —
    // matches the CLI's `parse_list_id` (typed `IdKind::ListId`).
    let id = crate::commands::shared::validate_list_id(&args.id, "id")?;
    let conn = get_conn()?;
    update_list_with_conn(&conn, UpdateListArgs { id, ..args }).map_err(String::from)
}
