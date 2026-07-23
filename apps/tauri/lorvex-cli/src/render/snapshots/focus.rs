//! Snapshot coverage for `render_current_focus`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_current_focus_text_present() {
    let focus = fixture_current_focus();
    let out = render_current_focus(Some(&focus), "2026-04-27", db_path(), OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_current_focus_json_present() {
    let focus = fixture_current_focus();
    let out = render_current_focus(Some(&focus), "2026-04-27", db_path(), OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_current_focus_json_none() {
    // Only JSON branch is clock-independent when focus is None.
    let out = render_current_focus(None, "2026-04-27", db_path(), OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}
