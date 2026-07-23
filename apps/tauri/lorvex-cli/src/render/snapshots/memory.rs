//! Snapshot coverage for `render_memory_collection` and
//! `render_memory_detail`.

use lorvex_store::repositories::memory_repo;

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_memory_collection_text_empty() {
    let out = render_memory_collection(db_path(), &[], OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_memory_collection_text_multiple() {
    let entries = fixture_memory_entries();
    let out =
        render_memory_collection(db_path(), &entries, OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_memory_collection_json_multiple() {
    let entries = fixture_memory_entries();
    let out =
        render_memory_collection(db_path(), &entries, OutputFormat::Json).expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_memory_detail_text() {
    let entry = memory_repo::MemoryEntry {
        key: "preferences.tone".to_string(),
        content: "friendly".to_string(),
        version: "v1".to_string(),
        updated_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T10:00:00Z")
            .expect("canonical fixture"),
    };
    let out = render_memory_detail(db_path(), &entry, OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_memory_detail_json() {
    let entry = memory_repo::MemoryEntry {
        key: "preferences.tone".to_string(),
        content: "friendly".to_string(),
        version: "v1".to_string(),
        updated_at: lorvex_domain::time::SyncTimestamp::parse("2026-04-01T10:00:00Z")
            .expect("canonical fixture"),
    };
    let out = render_memory_detail(db_path(), &entry, OutputFormat::Json).expect("render json");
    snapshot_json!(out);
}
