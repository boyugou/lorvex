//! Snapshot coverage for `render_list_collection` and
//! `render_list_detail`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_list_collection_text_empty() {
    let out = render_list_collection(db_path(), &[], OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_list_collection_text_multiple() {
    let lists = fixture_list_with_counts();
    let out = render_list_collection(db_path(), &lists, OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_list_collection_json_multiple() {
    let lists = fixture_list_with_counts();
    let out = render_list_collection(db_path(), &lists, OutputFormat::Json).expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_list_detail_text_mixed() {
    let list = fixture_list_row();
    let out = render_list_detail(db_path(), &list, &fixture_tasks(), OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_list_detail_text_empty_tasks() {
    let list = fixture_list_row();
    let out = render_list_detail(db_path(), &list, &[], OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_list_detail_json_mixed() {
    let list = fixture_list_row();
    let out = render_list_detail(db_path(), &list, &fixture_tasks(), OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}
