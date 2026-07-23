//! Public value types used by the import pipeline.
//!
//! [`ImportSummary`] carries the per-pass counts the importer reports
//! back to its caller (commit mode) and the dry-run preview shape spec'd
//! in #2368. [`ImportOptions`] flips between commit and dry-run.

use crate::export_scope::{
    ExportCategory, ExportDependencyMode, ExportScopeKind, ImportValidationFinding,
};

/// Summary of what was imported.
///
/// When `dry_run` is true, no database mutation occurred — the counts
/// describe what the commit path *would* do, and the per-entity-type
/// fields (`tasks_to_create`, `lists_to_create`, …) populate the
/// preview shape spec'd in issue #2368.
#[derive(Debug, Clone)]
pub struct ImportSummary {
    pub entities_created: u64,
    pub entities_updated: u64,
    pub entities_skipped: u64,
    pub scope_kind: ExportScopeKind,
    pub scope_categories: Vec<ExportCategory>,
    pub dependency_mode: ExportDependencyMode,
    pub validation_findings: Vec<ImportValidationFinding>,

    // ── #2368: dry-run preview fields ─────────────────────────────────
    /// True when this summary reflects a dry-run preview (no DB writes,
    /// no sync envelopes emitted). The commit path leaves this `false`.
    pub dry_run: bool,
    /// Per-entity-type "would create" counts. `tasks_to_skip` covers
    /// entries the import would drop because the local copy has a newer
    /// HLC version (version-aware upsert).
    pub tasks_to_create: u64,
    pub tasks_to_update: u64,
    pub tasks_to_skip: u64,
    pub lists_to_create: u64,
    pub habits_to_create: u64,
    /// Number of preference rows that would be created or overwritten.
    /// Import upserts preferences unconditionally; any row touched here
    /// is a preference the user should review.
    pub preferences_to_change: u64,
    /// Memory rows that would be created or updated (including
    /// `memory_revision` entries).
    pub memory_to_write: u64,
    /// Number of blob payloads whose restored bytes did not match the
    /// archive metadata. Current-format imports fail closed on section
    /// digest mismatches, so successful imports report zero until the
    /// blob layer grows recoverable mismatch accounting.
    pub blobs_hash_mismatch: u64,
    /// Size of the source ZIP archive on disk, in bytes.
    pub estimated_size_bytes: u64,
    pub schema_version: Option<u32>,
    pub source_device_id: Option<String>,
    pub export_timestamp: Option<String>,
}

impl Default for ImportSummary {
    fn default() -> Self {
        Self {
            entities_created: 0,
            entities_updated: 0,
            entities_skipped: 0,
            scope_kind: ExportScopeKind::Full,
            scope_categories: Vec::new(),
            dependency_mode: ExportDependencyMode::Closure,
            validation_findings: Vec::new(),
            dry_run: false,
            tasks_to_create: 0,
            tasks_to_update: 0,
            tasks_to_skip: 0,
            lists_to_create: 0,
            habits_to_create: 0,
            preferences_to_change: 0,
            memory_to_write: 0,
            blobs_hash_mismatch: 0,
            estimated_size_bytes: 0,
            schema_version: None,
            source_device_id: None,
            export_timestamp: None,
        }
    }
}

/// Options controlling import behavior.
///
/// The default (`ImportOptions::default()`) matches the historical
/// committing behavior of [`super::import_from_zip`]. Set `dry_run = true` to
/// run the full parse + validation pipeline without persisting
/// anything to the DB or blob directory — useful for producing a
/// preview summary before asking the user to confirm the commit.
#[derive(Debug, Clone, Copy, Default)]
pub struct ImportOptions {
    /// When true, parse + validate as usual, populate the preview
    /// counts on [`ImportSummary`], then roll back every SQLite change
    /// and skip blob-file persistence. No sync envelopes are emitted —
    /// the commit path would emit them; dry-run short-circuits before
    /// reaching that layer.
    pub dry_run: bool,
}
