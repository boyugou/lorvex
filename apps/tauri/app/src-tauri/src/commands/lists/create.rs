//! `create_list` IPC command — typed
//! [`lorvex_workflow::mutation::Mutation`] descriptor routed through
//! [`crate::commands::shared::effects::execute_ipc_entity_mutation`]
//! so the create stamp, outbox enqueue, `local_change_seq` bump, and
//! event-bus broadcast all share one HLC session and one ordering
//! contract with every other Tauri write.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_LIST, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::shared::effects::execute_ipc_entity_mutation;
use crate::commands::{enqueue_list_upsert, with_immediate_transaction, TaskList};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

use super::reload_list_as_task_list;

/// Validated, sanitized arguments for a single `create_list` write.
///
/// Built at the IPC boundary after `sanitize_user_text` + the
/// validation helpers; the descriptor carries borrowed slices so
/// `apply` never re-validates.
struct CreateListMutation<'a> {
    id: &'a lorvex_domain::ListId,
    name: &'a str,
    color: Option<&'a str>,
    icon: Option<&'a str>,
    description: Option<&'a str>,
}

impl<'a> Mutation for CreateListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    /// Create has no pre-row by definition.
    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        lorvex_store::repositories::list_repo::create_list(
            conn,
            self.id,
            self.name,
            self.color,
            self.icon,
            self.description,
            &version,
        )?;
        // The Tauri surface does not write `ai_changelog`
        // (`log_change` is a no-op by design), so `after_json` is
        // unused downstream. Stamp the canonical row id + name shape
        // so the field still carries something diagnostically useful
        // if a future audit funnel is wired in.
        let after = serde_json::json!({
            "id": self.id.as_str(),
            "name": self.name,
        });
        let summary = format!("Created list '{}'", self.name);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn create_list_inner(
    name: String,
    color: Option<String>,
    icon: Option<String>,
    description: Option<String>,
) -> AppResult<TaskList> {
    // Unicode hygiene (#2427): scrub name / description before the trim +
    // emptiness check so a name made entirely of invisible controls is
    // rejected. color / icon are short-token fields that the app writes
    // itself (hex / emoji) and should not be altered here.
    let name = lorvex_domain::sanitize_user_text(&name).trim().to_string();
    let description = description.map(|s| lorvex_domain::sanitize_user_text(&s));
    if name.is_empty() {
        return Err(AppError::Validation(
            "list name must not be empty".to_string(),
        ));
    }
    use crate::invariants::validation::{
        validate_color_hex, validate_list_description, validate_list_name, validate_short_text,
    };
    validate_list_name(&name)?;
    validate_list_description(description.as_deref())?;
    // enforce `#rrggbb` hex shape on the Tauri create
    // path so MCP / CLI / Tauri all accept the same color syntax.
    validate_color_hex(color.as_deref())?;
    validate_short_text(icon.as_deref(), "icon")?;

    let conn = get_conn()?;
    let id = lorvex_domain::ListId::from_trusted(lorvex_domain::new_entity_id_string());
    let id_str = id.as_str().to_string();

    let list = with_immediate_transaction(&conn, |conn| {
        let mutation = CreateListMutation {
            id: &id,
            name: &name,
            color: color.as_deref(),
            icon: icon.as_deref(),
            description: description.as_deref(),
        };
        execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
            // Reload via the Tauri IPC mapper so the outbox
            // envelope ships the wire-stable `TaskList` shape
            // (matches the historical behavior of this command,
            // which preserved the existing enqueue helper's
            // payload format).
            let list = reload_list_as_task_list(conn, &id_str)?;
            enqueue_list_upsert(conn, &list)?;
            Ok(())
        })?;
        reload_list_as_task_list(conn, &id_str)
    })?;
    Ok(list)
}

#[tauri::command]
pub fn create_list(
    name: String,
    color: Option<String>,
    icon: Option<String>,
    description: Option<String>,
) -> Result<TaskList, String> {
    create_list_inner(name, color, icon, description).map_err(String::from)
}
