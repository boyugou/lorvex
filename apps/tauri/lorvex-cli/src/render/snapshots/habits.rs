//! Snapshot coverage for `render_habit_collection`,
//! `render_habit_stats`, and `render_habit_complete_result`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;

#[test]
fn render_habit_collection_text_empty() {
    let out = render_habit_collection(db_path(), "2026-04-10", &[], OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_habit_collection_text_multiple() {
    let out = render_habit_collection(
        db_path(),
        "2026-04-10",
        &fixture_habits(),
        OutputFormat::Text,
    )
    .expect("render text");
    snapshot!(out);
}

#[test]
fn render_habit_collection_json_multiple() {
    let out = render_habit_collection(
        db_path(),
        "2026-04-10",
        &fixture_habits(),
        OutputFormat::Json,
    )
    .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_habit_stats_text() {
    let out = render_habit_stats(
        db_path(),
        "habit-alpha",
        "Read",
        120,
        1,
        28,
        30,
        OutputFormat::Text,
    )
    .expect("render text");
    snapshot!(out);
}

#[test]
fn render_habit_stats_json() {
    let out = render_habit_stats(
        db_path(),
        "habit-alpha",
        "Read",
        120,
        1,
        28,
        30,
        OutputFormat::Json,
    )
    .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_habit_complete_result_text() {
    let out = render_habit_complete_result(
        db_path(),
        "habit-alpha",
        "Read",
        "2026-04-10",
        1,
        None,
        OutputFormat::Text,
    )
    .expect("render text");
    snapshot!(out);
}

#[test]
fn render_habit_complete_result_json() {
    let out = render_habit_complete_result(
        db_path(),
        "habit-alpha",
        "Read",
        "2026-04-10",
        1,
        Some("Finished chapter 1"),
        OutputFormat::Json,
    )
    .expect("render json");
    snapshot_json!(out);
}
