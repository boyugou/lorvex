use crate::contract::{ExportAllDataArgs, ImportDataArgs};
use crate::db::resolve_db_path;
use crate::error::McpError;
use crate::runtime::cancellation::check_cancelled;
use crate::runtime::change_tracking::write_import_session_audit_entry;
use crate::server::LorvexMcpServer;
use rmcp::{handler::server::wrapper::Parameters, tool, tool_router};
use serde_json::json;
use std::fs::File;
use std::io::{Read, Seek};
use std::path::Path;
use std::path::PathBuf;
use tokio_util::sync::CancellationToken;

fn parse_export_category(value: &str) -> Result<lorvex_store::ExportCategory, String> {
    match value {
        "tasks" => Ok(lorvex_store::ExportCategory::Tasks),
        "lists" => Ok(lorvex_store::ExportCategory::Lists),
        "calendar" => Ok(lorvex_store::ExportCategory::Calendar),
        "habits" => Ok(lorvex_store::ExportCategory::Habits),
        "daily_reviews" => Ok(lorvex_store::ExportCategory::DailyReviews),
        "memory" => Ok(lorvex_store::ExportCategory::Memory),
        "preferences" => Ok(lorvex_store::ExportCategory::Preferences),
        "focus" => Ok(lorvex_store::ExportCategory::Focus),
        "subscriptions" => Ok(lorvex_store::ExportCategory::Subscriptions),
        "audit" => Ok(lorvex_store::ExportCategory::Audit),
        other => Err(format!("Error: unknown export scope category `{other}`")),
    }
}

fn resolve_export_scope(
    scope_categories: Option<Vec<String>>,
) -> Result<lorvex_store::ExportScope, String> {
    let Some(categories) = scope_categories else {
        return Ok(lorvex_store::ExportScope::full());
    };
    if categories.is_empty() {
        return Ok(lorvex_store::ExportScope::full());
    }
    let parsed = categories
        .into_iter()
        .map(|category| parse_export_category(&category))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(lorvex_store::ExportScope::scoped(parsed))
}

fn path_has_zip_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
}

#[derive(Debug)]
struct ValidatedImportZip {
    file: File,
    estimated_size_bytes: u64,
}

fn check_zip_signature(file: &mut File) -> Result<bool, String> {
    // Match the `Error: <lowercase-first sentence>` convention every
    // other user-visible MCP error in this module follows.
    let mut header = [0_u8; 4];
    let read = file
        .read(&mut header)
        .map_err(|e| format!("Error: failed to inspect ZIP archive: {e}"))?;
    file.seek(std::io::SeekFrom::Start(0))
        .map_err(|e| format!("Error: failed to rewind ZIP archive: {e}"))?;
    if read < header.len() {
        return Ok(false);
    }
    Ok(matches!(
        header,
        [0x50, 0x4B, 0x03, 0x04] | [0x50, 0x4B, 0x05, 0x06] | [0x50, 0x4B, 0x07, 0x08]
    ))
}

fn normalize_export_zip_path(output_path: Option<String>) -> Result<PathBuf, String> {
    // the MCP tool is an untrusted-input surface (prompt
    // injection via task notes etc.). A bare absolute path would let
    // an attacker instruct the assistant to clobber arbitrary .zip
    // files anywhere the app can write. Lock this down:
    //
    // - Default (no arg): timestamped file under <data_dir>/exports/.
    // - Explicit filename (bare "foo.zip"): placed under exports/.
    // - Anything with a path separator, `..`, NUL, absolute root:
    //   rejected.
    // - Refuse to overwrite an existing file — the caller can supply
    //   a different name or remove the existing export via the UI.
    let exports_dir = resolve_exports_dir().map_err(String::from)?;
    let resolved = if let Some(path) = output_path {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            // standardize on "must not be empty"
            // matching the rest of the MCP surface.
            return Err("Error: export path must not be empty".to_string());
        }
        if trimmed.contains('/')
            || trimmed.contains('\\')
            || trimmed.contains('\0')
            || trimmed == ".."
            || trimmed == "."
            || trimmed.starts_with("..")
        {
            return Err(
                "Error: export path must be a plain filename (no directories, no `..`). \
                 The archive is always written inside the Lorvex exports directory."
                    .to_string(),
            );
        }
        let filename = if path_has_zip_extension(Path::new(trimmed)) {
            trimmed.to_string()
        } else {
            format!("{trimmed}.zip")
        };
        exports_dir.join(filename)
    } else {
        let stamp = chrono::Utc::now().format("%Y%m%dT%H%M%SZ");
        exports_dir.join(format!("lorvex-export-v1-{stamp}.zip"))
    };

    // Defense-in-depth: confirm the fully-resolved path still lives
    // inside exports_dir. Guards against filename tricks (e.g. NTFS
    // alternate streams, Unicode path separators) that might slip
    // through the string check.
    if !resolved.starts_with(&exports_dir) {
        return Err(
            "Error: export path must resolve inside the Lorvex exports directory".to_string(),
        );
    }

    if resolved.exists() {
        return Err(format!(
            "Error: refusing to overwrite existing file at {}. \
             Pick a different filename.",
            resolved.display()
        ));
    }

    Ok(resolved)
}

fn validate_import_zip_path(zip_path: &Path, raw_path: &str) -> Result<ValidatedImportZip, String> {
    // every user-visible MCP error string in this module
    // opens with `Error: ` followed by a lowercase-first sentence so the
    // assistant-facing surface is uniform (the export-path validator
    // above already follows the convention).
    let mut file = match File::open(zip_path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(format!("Error: file not found: {raw_path}"));
        }
        Err(error) => {
            return Err(format!("Error: failed to read ZIP archive: {error}"));
        }
    };
    let metadata = file
        .metadata()
        .map_err(|e| format!("Error: failed to stat ZIP archive: {e}"))?;
    if !metadata.is_file() {
        return Err(format!("Error: zip archive is not a file: {raw_path}"));
    }
    if !path_has_zip_extension(zip_path) {
        return Err("Error: import_data requires a .zip archive".to_string());
    }
    if !check_zip_signature(&mut file)? {
        return Err("Error: import_data requires a valid ZIP archive".to_string());
    }
    Ok(ValidatedImportZip {
        file,
        estimated_size_bytes: metadata.len(),
    })
}

fn import_validated_zip_with_options(
    conn: &rusqlite::Connection,
    validated: ValidatedImportZip,
    dry_run: bool,
) -> Result<lorvex_store::ImportSummary, String> {
    lorvex_store::import_from_zip_file_with_options(
        conn,
        validated.file,
        validated.estimated_size_bytes,
        lorvex_store::ImportOptions { dry_run },
    )
    .map_err(|e| format!("Error: import failed: {e}"))
}

/// build the structured `after_json` payload for the
/// `import_data` audit row.
/// freeform `summary` blob; downstream diagnostics had to regex
/// across narrative prose to recover the numeric counts. The payload
/// surfaces every numeric field the import summary exposes — both
/// the post-commit aggregates (`entities_created`, `entities_updated`)
/// and the dry-run preview counts — plus the scope provenance so an
/// import session row is fully reconstructible from the audit log alone.
fn build_import_audit_after_json(
    summary: &lorvex_store::ImportSummary,
    dry_run: bool,
) -> serde_json::Value {
    serde_json::json!({
        "dry_run": dry_run,
        "entities_created": summary.entities_created,
        "entities_updated": summary.entities_updated,
        "entities_skipped": summary.entities_skipped,
        "tasks_to_create": summary.tasks_to_create,
        "tasks_to_update": summary.tasks_to_update,
        "tasks_to_skip": summary.tasks_to_skip,
        "lists_to_create": summary.lists_to_create,
        "habits_to_create": summary.habits_to_create,
        "preferences_to_change": summary.preferences_to_change,
        "memory_to_write": summary.memory_to_write,
        "estimated_size_bytes": summary.estimated_size_bytes,
        "schema_version": summary.schema_version,
        "source_device_id": summary.source_device_id,
        "export_timestamp": summary.export_timestamp,
    })
}

/// Resolve the exports directory under the data directory. Creates it if needed.
fn resolve_exports_dir() -> Result<PathBuf, McpError> {
    let db = resolve_db_path();
    let parent = db.parent().ok_or_else(|| {
        McpError::Internal("Cannot resolve exports dir: db_path has no parent".to_string())
    })?;
    let exports_dir = parent.join("exports");
    std::fs::create_dir_all(&exports_dir)
        .map_err(|e| McpError::Internal(format!("Failed to create exports directory: {e}")))?;
    Ok(exports_dir)
}

#[tool_router(router = import_export_tool_router, vis = "pub(crate)")]
impl LorvexMcpServer {
    #[tool(
        name = "export_all_data",
        description = "Export user data to a ZIP archive (lorvex-store format). Omit scope_categories for a full backup/migration export, or pass explicit categories for a scoped export. The archive is ALWAYS written inside the Lorvex exports directory — if `output_path` is provided, it must be a plain filename (no `/`, no `\\`, no `..`); absolute/relative paths are rejected. The tool refuses to overwrite existing files. Returns the file path plus manifest scope and entity counts."
    )]
    pub(crate) async fn export_all_data(
        &self,
        Parameters(ExportAllDataArgs {
            output_path,
            scope_categories,
        }): Parameters<ExportAllDataArgs>,
        ct: CancellationToken,
    ) -> Result<String, String> {
        // #2133: export is a long operation — a multi-table dump.
        // SQLite's own iteration inside `export_to_zip_scoped` isn't
        // interruptible from outside the connection thread (that
        // requires `progress_handler`, tracked separately), but we can
        // at least short-circuit *before* we acquire the writer lock
        // and *before* we hand control to the store crate. That covers
        // the common case where the user cancels while the tool is
        // queued behind another slow handler.
        //
        // #2177: the archive serialization dominates wall time on
        // large libraries and must not block the tokio reactor.
        // Dispatch the writer path onto the blocking pool.
        check_cancelled(&ct).map_err(String::from)?;
        let device_id = self
            .with_conn_typed_async(|conn| {
                crate::runtime::change_tracking::get_or_create_sync_device_id(conn)
            })
            .await?;

        let output = match output_path {
            Some(p) => normalize_export_zip_path(Some(p))?,
            None => normalize_export_zip_path(None)?,
        };
        let scope = resolve_export_scope(scope_categories)?;

        check_cancelled(&ct).map_err(String::from)?;
        let output_for_closure = output.clone();
        // #3324 B3: snapshot the watchdog token so the closure (which
        // runs on the blocking pool, where task-local context does not
        // propagate) can short-circuit the JSON-serialization tail
        // when the watchdog has already fired. The export's own
        // `.zip.tmp → .zip` rename inside `export_to_zip_scoped` is
        // not interruptible from this layer, but skipping the
        // serialization avoids returning a result the client has
        // already given up on.
        let watchdog = crate::runtime::tool_timeout::current_watchdog_token();
        self.with_writer_no_savepoint_async(move |conn| {
            let manifest =
                lorvex_store::export_to_zip_scoped(conn, &output_for_closure, &device_id, &scope)
                    .map_err(|e| {
                    // Clean up temp file on failure (store writes to .zip.tmp, renames on success).
                    // same rationale as the Tauri/CLI export
                    // paths — the export error carries the actionable
                    // signal; a secondary cleanup failure is reaped by the
                    // next successful export reusing the deterministic
                    // `.zip.tmp` slot.
                    let _ = std::fs::remove_file(output_for_closure.with_extension("zip.tmp"));
                    McpError::Internal(format!("Export failed: {e}"))
                })?;

            // #3324 B3: post-sub-call watchdog check. The on-disk
            // archive has already been written (the rename is atomic
            // inside `export_to_zip_scoped`), so this only avoids
            // returning a successful payload to a client that has
            // already retried under the same idempotency key.
            if let Some(token) = watchdog.as_ref() {
                if token.is_cancelled() {
                    return Err(String::from(McpError::CancelledByClient));
                }
            }

            serde_json::to_string(&json!({
                "export_path": output_for_closure.to_string_lossy(),
                "format_version": manifest.format_version,
                "scope_kind": manifest.scope_kind,
                "scope_categories": manifest.scope_categories,
                "dependency_mode": manifest.dependency_mode,
                "entity_counts": manifest.entity_counts,
                "edge_counts": manifest.edge_counts,
            }))
            .map_err(|e| format!("Error: {e}"))
        })
        .await
    }

    #[tool(
        name = "import_data",
        description = "Import data from a lorvex-store ZIP archive (produced by export_all_data). Set dry_run=true to get a preview summary (per-entity-type would-change counts, manifest provenance, validation findings) WITHOUT writing anything — do this first, show the user, then call again with dry_run=false to commit. Full archives restore all entities; scoped archives return structured validation_findings before applying invalid partial data. Provide the absolute file path to the ZIP archive."
    )]
    pub(crate) async fn import_data(
        &self,
        Parameters(ImportDataArgs { file_path, dry_run }): Parameters<ImportDataArgs>,
        ct: CancellationToken,
    ) -> Result<String, String> {
        // #2133: validate-then-acquire; check the cancellation token
        // in between so we don't take the writer lock when the caller
        // already cancelled. The main `import_from_zip` body runs
        // inside a single transaction managed by the store crate; we
        // can't interrupt that safely without schema-level progress
        // hooks, so we only guard the entry point.
        //
        // #2177: archive unpack + multi-table restore is long and
        // fully blocking from SQLite's side. Route the writer path
        // onto the tokio blocking pool so other tool calls and the
        // orphan watchdog stay responsive while the import runs.
        check_cancelled(&ct).map_err(String::from)?;
        let zip_path = PathBuf::from(&file_path);
        let validated_zip = validate_import_zip_path(&zip_path, &file_path)?;
        check_cancelled(&ct).map_err(String::from)?;

        // The store import pipeline manages its own transaction internally,
        // so we use with_writer_no_savepoint (no nested savepoint wrapper).
        //
        // #3324 B3: snapshot the watchdog token so the closure can
        // skip the post-import audit-log write when the watchdog has
        // already fired. The store-managed import COMMIT is not
        // interruptible from this layer, but suppressing the audit
        // row stops the assistant from seeing a duplicate
        // `import` / `import_preview` ai_changelog entry every time
        // the client retries under the same idempotency key.
        let watchdog = crate::runtime::tool_timeout::current_watchdog_token();
        self.with_writer_no_savepoint_async(move |conn| {
            let summary = import_validated_zip_with_options(conn, validated_zip, dry_run)?;

            if !dry_run {
                lorvex_sync::snapshot_import::finalize_snapshot_import_with_deferred_reseed(
                    conn,
                    "mcp_import_data",
                )
                .map_err(|error| {
                    format!(
                        "Error: import committed, but marking sync reseed required failed: {error}"
                    )
                })?;
            } else {
                // #3324 B3: dry-run imports are fully rolled back data previews.
                // If the watchdog fired, skip the local-only preview audit row so
                // retries do not duplicate preview chatter. Committed imports do
                // not take this branch: their shared sync finalization and audit
                // representation must be attempted before returning cancellation.
                if let Some(token) = watchdog.as_ref() {
                    if token.is_cancelled() {
                        return Err(String::from(McpError::CancelledByClient));
                    }
                }
            }

            let summary_text = if dry_run {
                format!(
                    "Import preview (dry_run): would create {}, update {}, skip {}; tasks {}/{}/{}, lists +{}, habits +{}, preferences Δ{}, memory Δ{}; archive {} bytes",
                    summary.entities_created,
                    summary.entities_updated,
                    summary.entities_skipped,
                    summary.tasks_to_create,
                    summary.tasks_to_update,
                    summary.tasks_to_skip,
                    summary.lists_to_create,
                    summary.habits_to_create,
                    summary.preferences_to_change,
                    summary.memory_to_write,
                    summary.estimated_size_bytes,
                )
            } else {
                format!(
                    "Imported ZIP archive: {} created, {} updated, {} skipped",
                    summary.entities_created,
                    summary.entities_updated,
                    summary.entities_skipped,
                )
            };
            // CLAUDE.md core rule: every MCP write must log to ai_changelog.
            // Import already committed its own transaction so we can't roll
            // back the data import on audit failure, but we MUST surface
            // the failure durably. The previous "best-effort
            // eprintln!" pattern meant the assistant could truthfully say
            // "you didn't import anything" the next day because the
            // changelog row was silently missing. Now we persist to
            // error_logs and include an audit_warning field in the tool
            // response so the assistant knows something went wrong.
            //
            // #2368: dry-run still logs to ai_changelog, but under the
            // `import_preview` operation so the audit trail distinguishes
            // "assistant previewed an import" from "assistant committed
            // an import". The preview itself is a write to the audit
            // table even though the import data was rolled back.
            let audit_operation = if dry_run { "import_preview" } else { "import" };
            // classify against the dedicated
            // ENTITY_IMPORT_SESSION entity type (non-syncable) and
            // thread the structured numeric counts through
            // `after_json` so the audit row is machine-readable.
            // import as a single-task mutation, and the numeric
            // summary fields lived only inside the freeform
            // `summary_text` blob — diagnostics couldn't aggregate
            // across import sessions without re-parsing prose.
            let after_json_payload = build_import_audit_after_json(&summary, dry_run);
            // ENTITY_IMPORT_SESSION is intentionally local-only. The shared
            // snapshot import finalizer already bumped `local_change_seq` for
            // committed imports, and dry-run previews must not bump it at all.
            // Use a local audit writer instead of the primary MCP mutation
            // funnel, which would enqueue/bump even for non-syncable markers.
            let audit_warning = if let Err(e) = write_import_session_audit_entry(
                conn,
                audit_operation,
                summary_text,
                after_json_payload,
                dry_run,
            ) {
                let message = format!("import_data audit logging failed: {e}");
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "mcp.import_data",
                    &message,
                    None,
                    None,
                );
                Some(message)
            } else {
                None
            };

            if !dry_run {
                if let Some(token) = watchdog.as_ref() {
                    if token.is_cancelled() {
                        return Err(String::from(McpError::CancelledByClient));
                    }
                }
            }

            serde_json::to_string(&json!({
                "dry_run": summary.dry_run,
                "entities_created": summary.entities_created,
                "entities_updated": summary.entities_updated,
                "entities_skipped": summary.entities_skipped,
                "scope_kind": summary.scope_kind,
                "scope_categories": summary.scope_categories,
                "dependency_mode": summary.dependency_mode,
                "validation_findings": summary.validation_findings,
                "tasks_to_create": summary.tasks_to_create,
                "tasks_to_update": summary.tasks_to_update,
                "tasks_to_skip": summary.tasks_to_skip,
                "lists_to_create": summary.lists_to_create,
                "habits_to_create": summary.habits_to_create,
                "preferences_to_change": summary.preferences_to_change,
                "memory_to_write": summary.memory_to_write,
                "estimated_size_bytes": summary.estimated_size_bytes,
                "schema_version": summary.schema_version,
                "source_device_id": summary.source_device_id,
                "export_timestamp": summary.export_timestamp,
                "audit_warning": audit_warning,
            })).map_err(|e| format!("Error: {e}"))
        })
        .await
    }
}

#[cfg(test)]
mod tests;
