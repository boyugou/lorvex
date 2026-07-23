//! TOCTOU-safe ZIP-decode pipeline that the public entry points
//! delegate into.
//!
//! [`import_from_zip_file_with_options`] takes an already-opened `File`
//! handle (#3053 M5) so the caller can hand the same descriptor through
//! from validation into the importer, foiling content-swap or
//! symlink-flip races. The function reads every JSONL section into
//! memory before opening the writer transaction so an I/O error during
//! decode cannot corrupt the rolling-back transaction's cursor state.

use rusqlite::Connection;

use crate::cancellation::check_import_cancelled;
use crate::projection::ProjectionRegistry;
use crate::transaction::with_immediate_transaction;
use crate::{CancellationToken, NeverCancelled};
use lorvex_domain::version::EXPORT_FORMAT_VERSION;

use super::apply::{
    apply_audit, apply_children, apply_edges, apply_entities, apply_payload_shadows,
    apply_provider_links, apply_tombstones,
};
use super::archive::{
    read_archive_file, read_manifest, validate_manifest_file_digests, verify_archive_file_digest,
};
use super::error::ImportError;
use super::scoped::{preflight_validate_scoped_import, ScopedImportArchiveContents};
use super::types::{ImportOptions, ImportSummary};

/// #3053 M5: TOCTOU-safe import path that takes an already-opened
/// `File` handle. The caller (e.g. Tauri, MCP, or CLI snapshot import)
/// opens the file during validation and hands the same descriptor
/// through to the importer, so a content-swap or symlink-flip between
/// the validation peek and the actual decode cannot fool the
/// integrity check. The convenience [`super::import_from_zip_with_options`]
/// wrapper is preserved for lower-risk callers and tests that do not
/// perform a separate pre-import validation pass.
pub fn import_from_zip_file_with_options(
    conn: &Connection,
    file: std::fs::File,
    estimated_size_bytes: u64,
    options: ImportOptions,
) -> Result<ImportSummary, ImportError> {
    import_from_zip_file_with_options_and_cancellation(
        conn,
        file,
        estimated_size_bytes,
        options,
        &NeverCancelled,
    )
}

/// TOCTOU-safe import path with cooperative cancellation.
pub fn import_from_zip_file_with_options_and_cancellation(
    conn: &Connection,
    file: std::fs::File,
    estimated_size_bytes: u64,
    options: ImportOptions,
    cancellation: &dyn CancellationToken,
) -> Result<ImportSummary, ImportError> {
    check_import_cancelled(cancellation)?;
    let mut archive = zip::ZipArchive::new(file)?;
    check_import_cancelled(cancellation)?;

    // ── 1. Read manifest.json and check format_version ─────────────────
    let manifest = read_manifest(&mut archive)?;
    check_import_cancelled(cancellation)?;
    if manifest.format_version != EXPORT_FORMAT_VERSION {
        return Err(ImportError::IncompatibleVersion {
            expected: EXPORT_FORMAT_VERSION,
            found: manifest.format_version,
        });
    }
    if manifest.schema_version > lorvex_domain::version::SCHEMA_VERSION {
        return Err(ImportError::InvalidPayload(format!(
            "archive schema version {sv} is newer than this app's schema version {}; upgrade the app before importing",
            lorvex_domain::version::SCHEMA_VERSION,
            sv = manifest.schema_version,
        )));
    }
    if manifest.payload_schema_version > lorvex_domain::version::PAYLOAD_SCHEMA_VERSION {
        return Err(ImportError::InvalidPayload(format!(
            "archive payload schema version {pv} is newer than this app's payload version {}; upgrade the app before importing",
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            pv = manifest.payload_schema_version,
        )));
    }
    validate_manifest_file_digests(&manifest)?;
    check_import_cancelled(cancellation)?;

    // ── 2. Read all archive contents into memory BEFORE mutation ───────
    // Reading from the ZIP archive inside a transaction risks cursor state
    // corruption on I/O error (the archive's seek position could become
    // invalid, leaving the transaction unable to roll back cleanly).
    // Pre-reading also avoids holding the IMMEDIATE lock during I/O.
    let entities_str = read_archive_file(&mut archive, "entities.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "entities.jsonl", &entities_str)?;
    let edges_str = read_archive_file(&mut archive, "edges.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "edges.jsonl", &edges_str)?;
    let children_str = read_archive_file(&mut archive, "children.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "children.jsonl", &children_str)?;
    let audit_str = read_archive_file(&mut archive, "audit.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "audit.jsonl", &audit_str)?;
    let shadows_str = read_archive_file(&mut archive, "payload_shadows.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "payload_shadows.jsonl", &shadows_str)?;
    let tombstones_str = read_archive_file(&mut archive, "tombstones.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "tombstones.jsonl", &tombstones_str)?;
    let provider_links_str = read_archive_file(&mut archive, "provider_links.jsonl")?;
    check_import_cancelled(cancellation)?;
    verify_archive_file_digest(&manifest, "provider_links.jsonl", &provider_links_str)?;

    let validation_findings = preflight_validate_scoped_import(
        &manifest,
        ScopedImportArchiveContents {
            entities_jsonl: &entities_str,
            edges_jsonl: &edges_str,
            children_jsonl: &children_str,
            audit_jsonl: &audit_str,
            tombstones_jsonl: &tombstones_str,
            shadows_jsonl: &shadows_str,
            provider_links_jsonl: &provider_links_str,
        },
    )?;
    check_import_cancelled(cancellation)?;

    let has_validation_errors = validation_findings
        .iter()
        .any(|finding| finding.severity == crate::export_scope::ImportValidationSeverity::Error);
    if has_validation_errors {
        let error_codes: Vec<String> = validation_findings
            .iter()
            .filter(|finding| {
                finding.severity == crate::export_scope::ImportValidationSeverity::Error
            })
            .map(|finding| finding.code.clone())
            .collect();
        let summary = ImportSummary {
            scope_kind: manifest.scope_kind,
            scope_categories: manifest.scope_categories,
            dependency_mode: manifest.dependency_mode,
            validation_findings,
            dry_run: options.dry_run,
            estimated_size_bytes,
            schema_version: Some(manifest.schema_version),
            source_device_id: Some(manifest.device_id),
            export_timestamp: Some(manifest.created_at),
            ..Default::default()
        };
        if options.dry_run {
            // #2368: dry-run callers need structured validation errors as
            // preview diagnostics. Commit-mode imports must fail closed so
            // callers cannot run post-import sync/audit finalizers.
            return Ok(summary);
        }
        return Err(ImportError::InvalidPayload(format!(
            "scoped import validation failed: {}",
            error_codes.join(", ")
        )));
    }

    // ── 3. Within a transaction, suspend projections, apply all
    //       pre-read data, then rebuild + resume projections.
    //
    // maintenance mode MUST run inside the writer
    // transaction so DROP TRIGGER (and the matching CREATE TRIGGER on
    // exit) happen atomically with the bulk inserts. Outside the tx,
    // DROP TRIGGER would autocommit and expose a window where another
    // connection's write could land on `tasks` without firing the FTS
    // trigger; the rebuild that runs after exit only INSERTs from
    // base tables, never reconciling concurrent-deletion drift, so
    // FTS would keep tombstoning ghost rows until the next manual
    // repair. Holding the writer lock for the full window is the
    // only correct behavior.
    let txn_result: Result<ImportSummary, ImportError> =
        with_immediate_transaction(conn, |txn_conn| {
            check_import_cancelled(cancellation)?;
            let registry = ProjectionRegistry::default_projections();
            registry.enter_maintenance_mode(txn_conn)?;

            let mut summary = ImportSummary {
                scope_kind: manifest.scope_kind,
                scope_categories: manifest.scope_categories.clone(),
                dependency_mode: manifest.dependency_mode,
                validation_findings: validation_findings.clone(),
                dry_run: options.dry_run,
                estimated_size_bytes,
                schema_version: Some(manifest.schema_version),
                source_device_id: Some(manifest.device_id.clone()),
                export_timestamp: Some(manifest.created_at.clone()),
                ..Default::default()
            };

            check_import_cancelled(cancellation)?;
            apply_entities(txn_conn, &entities_str, &mut summary, cancellation)?;
            apply_edges(txn_conn, &edges_str, &mut summary, cancellation)?;
            apply_children(txn_conn, &children_str, &mut summary, cancellation)?;
            apply_audit(txn_conn, &audit_str, &mut summary, cancellation)?;
            apply_payload_shadows(txn_conn, &shadows_str, cancellation)?;
            apply_tombstones(txn_conn, &tombstones_str, cancellation)?;
            apply_provider_links(txn_conn, &provider_links_str, &mut summary, cancellation)?;
            check_import_cancelled(cancellation)?;

            if options.dry_run {
                // #2368: signal a rollback-with-success.
                // `with_immediate_transaction` rolls the whole thing
                // back on Err — including the DROP TRIGGER from
                // enter_maintenance_mode — so projections naturally
                // restore to their pre-import state. The outer match
                // pulls the summary back out as Ok.
                return Err(ImportError::DryRunRollback(Box::new(summary)));
            }

            registry.exit_maintenance_mode(txn_conn)?;
            Ok(summary)
        });

    let summary = match txn_result {
        Ok(summary) => summary,
        Err(ImportError::DryRunRollback(summary)) => *summary,
        Err(other) => return Err(other),
    };

    Ok(summary)
}
