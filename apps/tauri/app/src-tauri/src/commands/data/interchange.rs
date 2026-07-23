//! `lorvex-interchange` export/import Tauri commands — the lean, schema-shaped
//! whole-database migration format. For moving a store to a fresh install (a
//! new or non-syncable device); carries current-state user data only.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::Serialize;

use crate::db::get_conn;

/// Resolve (creating if needed) the exports directory under the data dir.
fn resolve_exports_dir() -> Result<PathBuf, String> {
    let db = crate::db::db_path();
    let parent = db
        .parent()
        .ok_or("Cannot resolve exports dir: db_path has no parent")?;
    let dir = parent.join("exports");
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create exports directory: {e}"))?;
    Ok(dir)
}

#[derive(Debug, Serialize)]
pub struct InterchangeExportResult {
    pub export_path: String,
    pub row_counts: BTreeMap<String, u64>,
}

#[derive(Debug, Serialize)]
pub struct InterchangeImportResult {
    pub row_counts: BTreeMap<String, u64>,
}

/// Export the store to a `lorvex-interchange` ZIP. Writes into the data dir's
/// `exports/` folder (or `output_path` when given) and returns the path. With
/// `list_ids` non-empty, exports only the FK-closure of those lists (partial).
#[tauri::command]
pub fn export_interchange(
    output_path: Option<String>,
    list_ids: Option<Vec<String>>,
) -> Result<InterchangeExportResult, String> {
    let conn = get_conn()?;
    let seeds: Vec<lorvex_store::interchange::Seed> = list_ids
        .unwrap_or_default()
        .into_iter()
        .map(|id| lorvex_store::interchange::Seed {
            table: "lists".to_string(),
            id,
        })
        .collect();
    let (archive, manifest) =
        lorvex_store::interchange::export_archive(&conn, env!("CARGO_PKG_VERSION"), &seeds)
            .map_err(|e| {
                lorvex_domain::diagnostics::redact_diagnostic_text(&format!(
                    "interchange export failed: {e}"
                ))
            })?;

    let path = match output_path {
        Some(p) => {
            crate::commands::shared::reject_traversing_or_relative_path(
                std::path::Path::new(&p),
                "Interchange export path",
            )?;
            PathBuf::from(p)
        }
        None => {
            let name = if seeds.is_empty() {
                "lorvex-migration.zip"
            } else {
                "lorvex-partial.zip"
            };
            resolve_exports_dir()?.join(name)
        }
    };
    std::fs::write(&path, &archive).map_err(|e| format!("Failed to write export: {e}"))?;

    Ok(InterchangeExportResult {
        export_path: path.to_string_lossy().into_owned(),
        row_counts: manifest.row_counts,
    })
}

/// Import a `lorvex-interchange` ZIP at `input_path` into the current store.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn import_interchange(input_path: String) -> Result<InterchangeImportResult, String> {
    crate::commands::shared::reject_traversing_or_relative_path(
        std::path::Path::new(&input_path),
        "Interchange import path",
    )?;
    let archive =
        std::fs::read(&input_path).map_err(|e| format!("Failed to read import file: {e}"))?;
    let conn = get_conn()?;
    let summary = lorvex_store::interchange::import_archive(&conn, &archive).map_err(|e| {
        lorvex_domain::diagnostics::redact_diagnostic_text(&format!(
            "interchange import failed: {e}"
        ))
    })?;
    Ok(InterchangeImportResult {
        row_counts: summary.row_counts,
    })
}
