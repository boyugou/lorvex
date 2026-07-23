//! Export all data to a ZIP archive.
//!
//! The export format is a ZIP file containing JSONL data files, structured as:
//!
//! ```text
//! lorvex-export-v{format_version}.zip
//! +-- manifest.json
//! +-- entities.jsonl
//! +-- edges.jsonl
//! +-- children.jsonl
//! +-- audit.jsonl
//! +-- tombstones.jsonl
//! +-- payload_shadows.jsonl
//! +-- provider_links.jsonl     (local-only task↔provider event links)
//! ```
//!
//! See spec Section 22 (Export/Import Format).

mod archive;
mod dataset;
mod entrypoints;
mod error;
mod inventory;
mod jsonl;
mod row_writers;
mod sqlite_json;
mod temp_file;
mod types;
mod writers;

pub use entrypoints::{
    export_to_zip, export_to_zip_scoped, export_to_zip_scoped_with_cancellation,
    export_to_zip_with_cancellation,
};
pub use error::ExportError;
pub(crate) use types::ScopedExportInventory;
pub use types::{ExportManifest, FileDigest};

pub(crate) use dataset::{
    parse_json_records, parse_json_values, parse_versioned_records, scope_export_dataset,
    versioned_record_key, ExportDataset, JsonExportRecord, ScopedExportDataset,
    VersionedExportRecord,
};

pub(in crate::export) use inventory::build_scoped_inventory;
pub(in crate::export) use jsonl::{
    edge_entity_id, serialize_json_records, serialize_json_values, serialize_versioned_records,
    write_jsonl_edge_line, write_jsonl_entity_line,
};
pub(in crate::export) use row_writers::{
    write_audit_rows, write_payload_shadow_rows, write_provider_link_rows, write_tombstone_rows,
};
pub(in crate::export) use sqlite_json::{
    sqlite_bool_to_json, sqlite_column_value_to_json, sqlite_value_to_json,
};
pub(in crate::export) use temp_file::{create_export_temp_file, TempFileGuard};
pub(in crate::export) use writers::{
    run_versioned_writer, CalendarEventWriter, ColumnarEntityWriter, CurrentFocusWriter,
    DailyReviewWriter, EdgeWriter, FocusScheduleWriter, HabitWriter, TaskWriter,
};

#[cfg(test)]
mod tests;
