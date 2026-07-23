//! Snapshot coverage for `render_tag_collection`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_tag_collection_text_empty() {
    let out = render_tag_collection(db_path(), &[], OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_tag_collection_text_multiple() {
    let tags = fixture_tags();
    let out = render_tag_collection(db_path(), &tags, OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_tag_collection_json_multiple() {
    let tags = fixture_tags();
    let out = render_tag_collection(db_path(), &tags, OutputFormat::Json).expect("render json");
    snapshot_json!(out);
}
