//! Unscoped (full) export pipeline.
//!
//! [`export_to_zip_inner`] reads every syncable table directly from
//! the `Connection`, streams each section through `write_section`,
//! and writes the manifest. This is the path used when the caller has
//! not supplied an `ExportScope` filter.
//!
//! Folder layout:
//!
//! - `mod.rs` (this file) — temp-file ceremony, the section-by-section
//!   orchestrator, manifest assembly, fsync + atomic rename.
//! - `aggregate_roots.rs` — the 12 writers that land in
//!   `entities.jsonl` (lists, tasks, tags, habits, calendar events,
//!   calendar subscriptions, preferences, memories,
//!   memory revisions, daily reviews, current focus, focus
//!   schedules).
//! - `edges.rs` — the 4 sync-replicated edge tables (`edges.jsonl`).
//! - `children.rs` — the 5 child entity classes that hang off an
//!   aggregate root (`children.jsonl`).

mod aggregate_roots;
mod children;
mod edges;

use super::digest::write_section;
use crate::cancellation::check_export_cancelled;
use crate::export::{
    create_export_temp_file, write_audit_rows, write_payload_shadow_rows, write_provider_link_rows,
    write_tombstone_rows, ExportError, ExportManifest, FileDigest, TempFileGuard,
};
use crate::export_scope::{ExportDependencyMode, ExportScopeKind};
use crate::fs_durability::fsync_parent_dir;
use crate::CancellationToken;
use lorvex_domain::naming::{EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_AI_CHANGELOG};
use lorvex_domain::version::{
    APP_VERSION, EXPORT_FORMAT_VERSION, PAYLOAD_SCHEMA_VERSION, SCHEMA_VERSION,
};
use rusqlite::Connection;
use std::collections::BTreeMap;
use std::io::Write;
use std::path::Path;
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

pub(in crate::export) fn export_to_zip_inner(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
    cancellation: &dyn CancellationToken,
) -> Result<ExportManifest, ExportError> {
    // Write to a temp file first, then rename on success. This ensures:
    // - An existing file at output_path is never truncated until export succeeds
    // - A partial/corrupt ZIP is never left at the output path on failure
    let temp_path = output_path.with_extension("zip.tmp");
    let file = create_export_temp_file(&temp_path)?;
    // arm a RAII guard so every early-return `?` cleans
    // up the temp file. Only a successful rename disarms.
    let mut temp_guard = TempFileGuard::new(&temp_path);
    let mut zip = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    check_export_cancelled(cancellation)?;

    let mut entity_counts: BTreeMap<String, u64> = BTreeMap::new();
    let mut edge_counts: BTreeMap<String, u64> = BTreeMap::new();
    let mut file_digests: BTreeMap<String, FileDigest> = BTreeMap::new();

    // Build the shadow-index once per export and thread it through every
    // writer.
    // entity-and-edge writers that ran in one export, that was 17×
    // `SELECT entity_type, entity_id FROM sync_payload_shadow` per
    // export call, each rebuild allocating two `String`s per shadow
    // row.
    let shadow_index = lorvex_sync_payload::payload_shadow::ShadowIndex::build(conn)?;
    check_export_cancelled(cancellation)?;

    // ── 1. entities.jsonl ──────────────────────────────────────────────
    write_section(
        &mut zip,
        "entities.jsonl",
        options,
        &mut file_digests,
        |sink| {
            aggregate_roots::write_aggregate_roots(
                conn,
                sink,
                &mut entity_counts,
                &shadow_index,
                cancellation,
            )
        },
    )?;
    check_export_cancelled(cancellation)?;

    // ── 2. edges.jsonl ─────────────────────────────────────────────────
    write_section(
        &mut zip,
        "edges.jsonl",
        options,
        &mut file_digests,
        |sink| edges::write_edges(conn, sink, &mut edge_counts, &shadow_index, cancellation),
    )?;
    check_export_cancelled(cancellation)?;

    // ── 3. children.jsonl ──────────────────────────────────────────────
    write_section(
        &mut zip,
        "children.jsonl",
        options,
        &mut file_digests,
        |sink| {
            children::write_children(conn, sink, &mut entity_counts, &shadow_index, cancellation)
        },
    )?;
    check_export_cancelled(cancellation)?;

    // ── 4. audit.jsonl (canonical ai_changelog entries only) ────────────
    let mut audit_count: u64 = 0;
    write_section(
        &mut zip,
        "audit.jsonl",
        options,
        &mut file_digests,
        |sink| {
            audit_count = write_audit_rows(conn, sink, cancellation)?;
            Ok(())
        },
    )?;
    if audit_count > 0 {
        entity_counts.insert(ENTITY_AI_CHANGELOG.to_string(), audit_count);
    }
    check_export_cancelled(cancellation)?;

    // ── 5. tombstones.jsonl ────────────────────────────────────────────
    write_section(
        &mut zip,
        "tombstones.jsonl",
        options,
        &mut file_digests,
        |sink| write_tombstone_rows(conn, sink, cancellation),
    )?;
    check_export_cancelled(cancellation)?;

    // ── 6. payload_shadows.jsonl ───────────────────────────────────────
    write_section(
        &mut zip,
        "payload_shadows.jsonl",
        options,
        &mut file_digests,
        |sink| write_payload_shadow_rows(conn, sink, cancellation),
    )?;
    check_export_cancelled(cancellation)?;

    // ── 7. provider_links.jsonl (local-only task↔provider event links) ─
    let mut provider_links_count: u64 = 0;
    write_section(
        &mut zip,
        "provider_links.jsonl",
        options,
        &mut file_digests,
        |sink| {
            provider_links_count = write_provider_link_rows(conn, sink, cancellation)?;
            Ok(())
        },
    )?;
    if provider_links_count > 0 {
        edge_counts.insert(
            EDGE_TASK_PROVIDER_EVENT_LINK.to_string(),
            provider_links_count,
        );
    }
    check_export_cancelled(cancellation)?;

    // ── 8. manifest.json ───────────────────────────────────────────────
    // Each JSONL section was hashed inline by its
    // `SectionDigestWriter`; the `file_digests` map is already populated
    // with sha256 + uncompressed-byte counts.
    let manifest = ExportManifest {
        format_version: EXPORT_FORMAT_VERSION,
        app_version: APP_VERSION.to_string(),
        schema_version: SCHEMA_VERSION,
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        created_at: lorvex_domain::sync_timestamp_now(),
        device_id: device_id.to_string(),
        scope_kind: ExportScopeKind::Full,
        scope_categories: Vec::new(),
        dependency_mode: ExportDependencyMode::Closure,
        scoped_inventory: None,
        entity_counts,
        edge_counts,
        file_digests,
    };

    check_export_cancelled(cancellation)?;
    zip.start_file("manifest.json", options)?;
    let manifest_json = serde_json::to_string_pretty(&manifest)?;
    zip.write_all(manifest_json.as_bytes())?;
    check_export_cancelled(cancellation)?;

    // fsync before atomic rename. `zip.finish()` flushes
    // ZIP-side buffers but the kernel page cache still holds the
    // bytes; on macOS APFS, `rename(temp, final)` is atomic in the
    // directory metadata but the contents of `temp` may not be on
    // stable storage when the rename returns. A power cut between
    // the rename and the next checkpoint produces a zero-length or
    // torn ZIP at the final path — exactly the corruption mode that
    //'s atomic-rename was meant to prevent. Recover the
    // inner `File` from `ZipWriter::finish` so we can call
    // `sync_all()` before letting the file drop.
    let zip_file = zip.finish()?;
    zip_file.sync_all().map_err(ExportError::Io)?;
    drop(zip_file);
    check_export_cancelled(cancellation)?;

    // Atomic rename: only appears at output_path after complete success.
    // disarm the guard AFTER a successful rename so the
    // renamed-to final file is preserved. If rename fails, the guard's
    // Drop runs and removes `temp_path`.
    std::fs::rename(&temp_path, output_path).map_err(ExportError::Io)?;
    fsync_parent_dir(output_path).map_err(ExportError::Io)?;
    temp_guard.disarm();

    Ok(manifest)
}
