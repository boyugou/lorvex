//! Snapshot coverage for `render_calendar_timeline` and
//! `render_calendar_event_detail`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_calendar_timeline_text_empty() {
    let out = render_calendar_timeline("Calendar", db_path(), &[], OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_calendar_timeline_text_multiple() {
    let items = vec![fixture_timeline_canonical(), fixture_timeline_all_day()];
    let out = render_calendar_timeline("Calendar", db_path(), &items, OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_calendar_timeline_json_multiple() {
    let items = vec![fixture_timeline_canonical(), fixture_timeline_all_day()];
    let out = render_calendar_timeline("Calendar", db_path(), &items, OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_calendar_event_detail_text() {
    let event = fixture_calendar_event_row();
    let out =
        render_calendar_event_detail(&event, db_path(), OutputFormat::Text).expect("render text");
    snapshot!(out);
}

#[test]
fn render_calendar_event_detail_json() {
    let event = fixture_calendar_event_row();
    let out =
        render_calendar_event_detail(&event, db_path(), OutputFormat::Json).expect("render json");
    snapshot_json!(out);
}
