//! Generic scoped archive writer.
//!
//! `write_export_archive` consumes a pre-materialized
//! `ScopedExportDataset` and writes the ZIP, mirroring the section
//! layout of the unscoped path. Callers (currently only
//! `export_to_zip_scoped_inner`) own the dataset assembly so this
//! function performs no SQL of its own.

use super::super::{
    build_scoped_inventory, create_export_temp_file, serialize_json_records, serialize_json_values,
    serialize_versioned_records, ExportError, ExportManifest, FileDigest, ScopedExportDataset,
    TempFileGuard,
};
use super::digest::write_section;
use crate::cancellation::check_export_cancelled;
use crate::export_scope::ExportScope;
use crate::fs_durability::fsync_parent_dir;
use crate::CancellationToken;
use lorvex_domain::naming::{EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_AI_CHANGELOG};
use lorvex_domain::version::{
    APP_VERSION, EXPORT_FORMAT_VERSION, PAYLOAD_SCHEMA_VERSION, SCHEMA_VERSION,
};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::Path;
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

pub(in crate::export) fn write_export_archive(
    output_path: &Path,
    device_id: &str,
    scope: &ExportScope,
    dataset: &ScopedExportDataset,
    cancellation: &dyn CancellationToken,
) -> Result<ExportManifest, ExportError> {
    let temp_path = output_path.with_extension("zip.tmp");
    let file = create_export_temp_file(&temp_path)?;
    // RAII guard for the temp path. See the unscoped
    // exporter above for the same pattern.
    let mut temp_guard = TempFileGuard::new(&temp_path);
    let mut zip = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    check_export_cancelled(cancellation)?;

    let mut entity_counts = BTreeMap::new();
    let mut edge_counts = BTreeMap::new();
    let mut file_digests: BTreeMap<String, FileDigest> = BTreeMap::new();

    write_section(
        &mut zip,
        "entities.jsonl",
        options,
        &mut file_digests,
        |sink| {
            serialize_versioned_records(
                &dataset.entities,
                true,
                &mut entity_counts,
                sink,
                cancellation,
            )
        },
    )?;
    check_export_cancelled(cancellation)?;
    write_section(
        &mut zip,
        "edges.jsonl",
        options,
        &mut file_digests,
        |sink| {
            serialize_versioned_records(&dataset.edges, false, &mut edge_counts, sink, cancellation)
        },
    )?;
    check_export_cancelled(cancellation)?;
    write_section(
        &mut zip,
        "children.jsonl",
        options,
        &mut file_digests,
        |sink| {
            serialize_versioned_records(
                &dataset.children,
                true,
                &mut entity_counts,
                sink,
                cancellation,
            )
        },
    )?;
    check_export_cancelled(cancellation)?;

    write_section(
        &mut zip,
        "audit.jsonl",
        options,
        &mut file_digests,
        |sink| serialize_json_records(&dataset.audit, sink, cancellation),
    )?;
    if !dataset.audit.is_empty() {
        entity_counts.insert(ENTITY_AI_CHANGELOG.to_string(), dataset.audit.len() as u64);
    }
    check_export_cancelled(cancellation)?;

    write_section(
        &mut zip,
        "tombstones.jsonl",
        options,
        &mut file_digests,
        |sink| serialize_json_values(&dataset.tombstones, sink, cancellation),
    )?;
    check_export_cancelled(cancellation)?;

    write_section(
        &mut zip,
        "payload_shadows.jsonl",
        options,
        &mut file_digests,
        |sink| serialize_json_values(&dataset.shadows, sink, cancellation),
    )?;
    check_export_cancelled(cancellation)?;

    write_section(
        &mut zip,
        "provider_links.jsonl",
        options,
        &mut file_digests,
        |sink| serialize_json_records(&dataset.provider_links, sink, cancellation),
    )?;
    if !dataset.provider_links.is_empty() {
        edge_counts.insert(
            EDGE_TASK_PROVIDER_EVENT_LINK.to_string(),
            dataset.provider_links.len() as u64,
        );
    }
    check_export_cancelled(cancellation)?;

    let manifest = ExportManifest {
        format_version: EXPORT_FORMAT_VERSION,
        app_version: APP_VERSION.to_string(),
        schema_version: SCHEMA_VERSION,
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        created_at: lorvex_domain::sync_timestamp_now(),
        device_id: device_id.to_string(),
        scope_kind: scope.kind,
        scope_categories: scope.categories.clone(),
        dependency_mode: scope.dependency_mode,
        scoped_inventory: Some(build_scoped_inventory(dataset)?),
        entity_counts,
        edge_counts,
        file_digests,
    };

    check_export_cancelled(cancellation)?;
    zip.start_file("manifest.json", options)?;
    let manifest_json = serde_json::to_string_pretty(&manifest)?;
    zip.write_all(manifest_json.as_bytes())?;
    check_export_cancelled(cancellation)?;

    // see `export_to_zip_inner` — fsync before atomic
    // rename so a power cut between rename and the next filesystem
    // checkpoint cannot leave a torn or zero-length ZIP at the final
    // path.
    let zip_file = zip.finish()?;
    zip_file.sync_all().map_err(ExportError::Io)?;
    drop(zip_file);
    check_export_cancelled(cancellation)?;

    // see export_to_zip_inner — disarm guard after
    // successful rename; any earlier `?` triggers the guard's Drop
    // and removes the temp file.
    std::fs::rename(&temp_path, output_path).map_err(ExportError::Io)?;
    fsync_parent_dir(output_path).map_err(ExportError::Io)?;
    temp_guard.disarm();

    Ok(manifest)
}
