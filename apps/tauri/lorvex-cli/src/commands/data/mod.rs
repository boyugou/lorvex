use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::{get_or_create_device_id, resolve_db_path};
use rusqlite::Connection;
use serde_json::json;
use std::fs::File;
use std::io::{Read, Seek};
use std::path::{Component, Path};

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;

/// reject relative paths and any path containing `..`
/// components. Mirrors the Tauri IPC twin in
/// `app/src-tauri/src/commands/data_snapshot/export.rs`; a CLI
/// invoked from a subprocess / compromised shell script must not
/// silently create directory trees outside the user's intended
/// target (e.g. `lorvex export '/../../tmp/evil/payload.zip'`).
fn reject_traversing_or_relative_path(path: &Path) -> Result<(), crate::error::CliError> {
    if !path.is_absolute() {
        return Err(crate::error::CliError::Validation(
            "Path must be absolute — pass a fully-qualified path".to_string(),
        ));
    }
    for component in path.components() {
        if matches!(component, Component::ParentDir) {
            return Err(crate::error::CliError::Validation(
                "Path must not contain '..' components".to_string(),
            ));
        }
    }
    Ok(())
}

struct ValidatedImportZip {
    file: File,
    estimated_size_bytes: u64,
}

fn path_has_zip_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
}

fn check_zip_signature(file: &mut File) -> Result<bool, crate::error::CliError> {
    let mut header = [0_u8; 4];
    let read = file.read(&mut header)?;
    file.seek(std::io::SeekFrom::Start(0))?;
    if read < header.len() {
        return Ok(false);
    }
    Ok(matches!(
        header,
        [0x50, 0x4B, 0x03, 0x04] | [0x50, 0x4B, 0x05, 0x06] | [0x50, 0x4B, 0x07, 0x08]
    ))
}

fn validate_import_zip_path(input: &Path) -> Result<ValidatedImportZip, crate::error::CliError> {
    reject_traversing_or_relative_path(input)?;
    let mut file = File::open(input)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(crate::error::CliError::Validation(format!(
            "ZIP archive is not a file: {}",
            input.display()
        )));
    }
    if !path_has_zip_extension(input) {
        return Err(crate::error::CliError::Validation(
            "Import requires a .zip archive".to_string(),
        ));
    }
    if !check_zip_signature(&mut file)? {
        return Err(crate::error::CliError::Validation(
            "Import requires a valid ZIP archive".to_string(),
        ));
    }
    Ok(ValidatedImportZip {
        file,
        estimated_size_bytes: metadata.len(),
    })
}

fn import_validated_zip(
    conn: &Connection,
    validated: ValidatedImportZip,
) -> Result<lorvex_store::ImportSummary, crate::error::CliError> {
    Ok(lorvex_store::import_from_zip_file_with_options(
        conn,
        validated.file,
        validated.estimated_size_bytes,
        lorvex_store::ImportOptions::default(),
    )?)
}

pub(crate) fn run_export(
    output_path: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let device_id = get_or_create_device_id(&conn)?;
    let output = Path::new(output_path);
    reject_traversing_or_relative_path(output)?;
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let manifest = lorvex_store::export_to_zip(&conn, output, &device_id).inspect_err(|_| {
        // Clean up temp file on failure.
        // same rationale as the Tauri app and MCP
        // export paths — the export error is the actionable signal;
        // a secondary remove_file failure is non-actionable and the
        // deterministic `.zip.tmp` slot is reaped on the next
        // successful export.
        let _ = std::fs::remove_file(output.with_extension("zip.tmp"));
    })?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Exported Lorvex snapshot\nDB: {}\nZIP: {}\nDevice ID: {}\nFormat version: {}",
            db_path.display(),
            output.display(),
            manifest.device_id,
            manifest.format_version,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "data.export",
            &db_path,
            json!({
                "output_path": output.display().to_string(),
                "manifest": manifest,
            }),
        ),
    }
}

pub(crate) fn run_import(
    input_path: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let input = Path::new(input_path);
    let validated = validate_import_zip_path(input)?;
    let summary = import_validated_zip(&conn, validated)?;
    lorvex_sync::snapshot_import::finalize_snapshot_import_with_deferred_reseed(
        &conn,
        "cli_import",
    )
    .map_err(|error| {
        crate::error::CliError::Internal(format!(
            "Snapshot import committed, but marking sync reseed required failed: {error}"
        ))
    })?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Imported Lorvex snapshot\nDB: {}\nZIP: {}\nEntities created: {}\nEntities updated: {}\nEntities skipped: {}",
            db_path.display(),
            input.display(),
            summary.entities_created,
            summary.entities_updated,
            summary.entities_skipped,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "data.import",
            &db_path,
            json!({
                "input_path": input.display().to_string(),
                "summary": {
                    "entities_created": summary.entities_created,
                    "entities_updated": summary.entities_updated,
                    "entities_skipped": summary.entities_skipped,
                },
            }),
        ),
    }
}

#[cfg(test)]
mod tests;
