use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::render::render_list_detail;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::{create_list_with_conn, delete_list_with_conn, update_list_with_conn};

pub(crate) fn run_list_create(
    name: &str,
    color: Option<&str>,
    icon: Option<&str>,
    description: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let list = create_list_with_conn(&mut conn, name, color, icon, description)?;
    match format {
        OutputFormat::Text => render_list_detail(&db_path, &list, &[], format),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "list.create",
            &db_path,
            json!({
                "list": list_row_to_json(&list),
                "tasks": Vec::<serde_json::Value>::new(),
            }),
        ),
    }
}

pub(crate) fn run_list_update(
    list_id: &str,
    name: Option<&str>,
    // tri-state args. `Patch::Clear` clears the column;
    // `Patch::Set(v)` sets it; `Patch::Unset` skips the field.
    color: lorvex_domain::Patch<&str>,
    icon: lorvex_domain::Patch<&str>,
    description: lorvex_domain::Patch<&str>,
    ai_notes: lorvex_domain::Patch<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let list = update_list_with_conn(&mut conn, list_id, name, color, icon, description, ai_notes)?;
    match format {
        OutputFormat::Text => render_list_detail(&db_path, &list, &[], format),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "list.update",
            &db_path,
            json!({
                "list": list_row_to_json(&list),
                "tasks": Vec::<serde_json::Value>::new(),
            }),
        ),
    }
}

pub(crate) fn run_list_delete(
    list_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    // `delete_list_with_conn` now returns the full
    // pre-delete `ListRow` so the `deleted` slot carries the canonical
    // entity shape — symmetric with `delete_calendar_event` and
    // `permanent_delete_task`. The previous stub `{id, name}` shape
    // forced JSON consumers to special-case lists when reconstructing
    // a deleted entity from a `delete` envelope.
    let deleted = delete_list_with_conn(&mut conn, list_id)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Deleted Lorvex list\nDB: {}\nList ID: {}\nName: {}",
            db_path.display(),
            deleted.id,
            deleted.name,
        )),
        // canonical CLI delete envelope shape
        // is `{action: "list.delete", db_path, deleted: <full row>}`.
        OutputFormat::Json => render_mutation_envelope(
            "list.delete",
            &db_path,
            json!({ "deleted": list_row_to_json(&deleted) }),
        ),
    }
}

/// Project a `ListRow` into the canonical JSON shape used by both
/// `render_list_detail` (read path) and the mutation envelope (write
/// path) so a JSON consumer sees identical keys regardless of which
/// command produced the row. Mirrors the payload built by the
/// repository's outbox writers.
fn list_row_to_json(list: &lorvex_store::repositories::list_repo::ListRow) -> serde_json::Value {
    json!({
        "id": list.id,
        "name": list.name,
        "color": list.color,
        "icon": list.icon,
        "description": list.description,
        "ai_notes": list.ai_notes,
        "created_at": list.created_at,
        "updated_at": list.updated_at,
        "version": list.version,
    })
}
