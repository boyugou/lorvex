//! ZIP emission for the diagnostic bundle. Owns the per-entry
//! Deflate write loop and the JSONL serializer that turns row
//! collections into newline-delimited JSON for the archive.

use std::io::Write;
use std::path::Path;

use serde::Serialize;
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

use crate::error::{AppError, AppResult};

/// Write each provided blob to its named entry. Uses Deflate
/// compression (same as the data-snapshot exporter) — diagnostic JSONL
/// is highly compressible so this is worth the CPU.
pub(super) fn write_bundle_zip(
    dest: &Path,
    system_info: &str,
    error_logs: &str,
    changelog: &str,
    conflict_log: &str,
) -> AppResult<()> {
    let file = std::fs::File::create(dest).map_err(|e| {
        AppError::Validation(format!(
            "Failed to create bundle at {}: {}",
            dest.display(),
            e
        ))
    })?;
    let mut zip = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    let mut write_entry = |name: &str, body: &str| -> AppResult<()> {
        zip.start_file(name, options)
            .map_err(|e| AppError::Validation(format!("zip start_file({name}): {e}")))?;
        zip.write_all(body.as_bytes())
            .map_err(|e| AppError::Validation(format!("zip write_all({name}): {e}")))?;
        Ok(())
    };

    write_entry("system_info.json", system_info)?;
    write_entry("error_logs.jsonl", error_logs)?;
    write_entry("ai_changelog_recent.jsonl", changelog)?;
    write_entry("sync_conflict_log.jsonl", conflict_log)?;
    write_entry(
        "README.txt",
        concat!(
            "Lorvex diagnostic bundle\n",
            "========================\n\n",
            "This ZIP contains local diagnostic signals intended to accompany a\n",
            "bug report. It deliberately excludes task bodies, checklist items,\n",
            "AI notes, and any other user-authored content.\n\n",
            "Contents:\n",
            "  - system_info.json           app + schema versions, OS/arch, runtime paths\n",
            "  - error_logs.jsonl           last 30 days of redacted error_log rows\n",
            "  - ai_changelog_recent.jsonl  last 30 days of AI changelog rows\n",
            "  - sync_conflict_log.jsonl    local sync conflict log (up to 1000 rows)\n\n",
            "Free-form text fields are passed through the redact_diagnostic_text\n",
            "scrubber at either write time (error_logs) or export time\n",
            "(ai_changelog.summary) so bearer tokens, API keys, and absolute\n",
            "filesystem paths are replaced with placeholders.\n",
        ),
    )?;

    zip.finish()
        .map_err(|e| AppError::Validation(format!("zip finish: {e}")))?;
    Ok(())
}

pub(super) fn rows_to_jsonl<T: Serialize>(rows: &[T]) -> AppResult<String> {
    let mut out = String::new();
    for row in rows {
        let line = serde_json::to_string(row).map_err(AppError::from)?;
        out.push_str(&line);
        out.push('\n');
    }
    Ok(out)
}
