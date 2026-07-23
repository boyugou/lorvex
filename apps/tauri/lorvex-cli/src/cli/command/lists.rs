//! Task-list CRUD arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ListsCommand {
    List {
        format: OutputFormat,
    },
    Show {
        list_id: String,
        limit: u32,
        format: OutputFormat,
    },
    Health {
        limit: u32,
        format: OutputFormat,
    },
    Create {
        name: String,
        color: Option<String>,
        icon: Option<String>,
        description: Option<String>,
        format: OutputFormat,
    },
    Update {
        list_id: String,
        name: Option<String>,
        // tri-state per nullable field. `None` means
        // "no change", `Some(None)` means "clear", `Some(Some(v))`
        // means "set to v" — matches `lorvex_store::repositories::
        // list_repo::ListUpdatePatch` and the MCP contract.
        color: lorvex_domain::Patch<String>,
        icon: lorvex_domain::Patch<String>,
        description: lorvex_domain::Patch<String>,
        ai_notes: lorvex_domain::Patch<String>,
        format: OutputFormat,
    },
    Delete {
        list_id: String,
        format: OutputFormat,
    },
}
