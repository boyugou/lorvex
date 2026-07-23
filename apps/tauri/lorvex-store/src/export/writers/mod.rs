//! Per-entity writers for versioned tables.
//!
//! The shared pipeline ([`run_versioned_writer`]) owns the six-step
//! contract that every versioned-table export goes through:
//!
//! 1. Prepare the writer's `SELECT` statement.
//! 2. Iterate rows.
//! 3. Per row, ask the writer to extract `(entity_id, version, payload)`.
//! 4. Merge the writer's pre-shadow payload with the shadow store.
//! 5. Emit the appropriate JSONL line shape (entity vs edge).
//! 6. Bump the per-entity-type count.
//!
//! Each per-entity writer is a small, pure(-ish) [`VersionedTableWriter`]
//! impl that owns just its SQL and its row→payload reshape; no IO,
//! transactions, or counter mutation lives in the writer impls. This
//! makes per-entity behavior trivially unit-testable while keeping the
//! shared pipeline single-source.

use std::collections::BTreeMap;
use std::io::Write;

use rusqlite::Connection;
use serde_json::Value;

use super::{write_jsonl_edge_line, write_jsonl_entity_line, ExportError};
use crate::cancellation::check_export_cancelled;
use crate::CancellationToken;
use lorvex_sync_payload::payload_shadow::{merge_payload_with_shadow_indexed, ShadowIndex};

mod calendar_event;
mod columnar;
mod current_focus;
mod daily_review;
mod edge;
mod focus_schedule;
mod habit;
mod task;

pub(in crate::export) use calendar_event::CalendarEventWriter;
pub(in crate::export) use columnar::ColumnarEntityWriter;
pub(in crate::export) use current_focus::CurrentFocusWriter;
pub(in crate::export) use daily_review::DailyReviewWriter;
pub(in crate::export) use edge::EdgeWriter;
pub(in crate::export) use focus_schedule::FocusScheduleWriter;
pub(in crate::export) use habit::HabitWriter;
pub(in crate::export) use task::TaskWriter;

/// JSONL line shape emitted by the shared pipeline.
///
/// Edges intentionally omit the top-level `entity_id` field — their id
/// is encoded inside the payload's composite-key columns and would
/// duplicate that information on the wire.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum LineFormat {
    Entity,
    Edge,
}

/// Pre-shadow row produced by a [`VersionedTableWriter`].
pub(super) struct ExtractedRow {
    pub entity_id: String,
    pub version: String,
    pub payload: Value,
}

/// Per-entity-type writer protocol.
///
/// Implementors describe **what** to read out of SQLite (a SELECT, plus
/// a row→payload reshape). The shared pipeline owns **how** to stream
/// the result — shadow-merge, JSONL framing, counter bump, error
/// translation.
pub(super) trait VersionedTableWriter {
    /// Canonical entity_type / edge_type that goes on the wire.
    fn entity_type(&self) -> &str;

    /// SQL `SELECT` statement that yields exactly the rows this writer
    /// should emit. Called once per export pass; long-lived statements
    /// are amortized through `prepare_cached` if the writer wants to
    /// fire ancillary queries inside [`Self::extract`].
    fn select_sql(&self) -> &str;

    /// JSONL line shape. Defaults to entity (the common case).
    fn line_format(&self) -> LineFormat {
        LineFormat::Entity
    }

    /// Project a single SQLite row into an [`ExtractedRow`]. May open
    /// auxiliary cached statements against `conn` to gather embedded
    /// children (checklist items, attendees, …).
    fn extract(
        &self,
        conn: &Connection,
        row: &rusqlite::Row<'_>,
    ) -> Result<ExtractedRow, ExportError>;
}

/// Drive a [`VersionedTableWriter`] through the shared 6-step pipeline.
pub(super) fn run_versioned_writer<W: VersionedTableWriter>(
    writer: &W,
    conn: &Connection,
    buf: &mut dyn Write,
    counts: &mut BTreeMap<String, u64>,
    shadow_index: &ShadowIndex,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    let entity_type = writer.entity_type();
    let line_format = writer.line_format();

    let mut stmt = conn.prepare(writer.select_sql())?;
    let mut count = 0u64;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        check_export_cancelled(cancellation)?;
        let extracted = writer.extract(conn, row)?;
        let payload = merge_payload_with_shadow_indexed(
            conn,
            shadow_index,
            entity_type,
            &extracted.entity_id,
            &extracted.payload,
        )
        .map_err(ExportError::from)?;
        match line_format {
            LineFormat::Entity => write_jsonl_entity_line(
                &mut *buf,
                entity_type,
                &extracted.entity_id,
                &extracted.version,
                &payload,
            )?,
            LineFormat::Edge => {
                write_jsonl_edge_line(&mut *buf, entity_type, &extracted.version, &payload)?;
            }
        }
        count += 1;
    }

    if count > 0 {
        counts.insert(entity_type.to_string(), count);
    }
    Ok(())
}
