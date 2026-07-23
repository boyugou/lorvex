//! Section 2 of the full-export pipeline: edges (`edges.jsonl`).
//!
//! Four edge tables make it across the wire — task↔tag, task→task
//! dependency, task↔calendar-event link, and habit↔completion-day.
//! Provider-event links live in section 7 because they're local-only
//! and don't sync to peers.

use std::collections::BTreeMap;

use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
};
use rusqlite::Connection;

use crate::export::{run_versioned_writer, EdgeWriter, ExportError};
use crate::CancellationToken;
use lorvex_sync_payload::payload_shadow::ShadowIndex;

pub(super) fn write_edges(
    conn: &Connection,
    sink: &mut dyn std::io::Write,
    edge_counts: &mut BTreeMap<String, u64>,
    shadow_index: &ShadowIndex,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_TAG,
            "task_tags",
            &["task_id", "tag_id", "created_at"],
        ),
        conn,
        sink,
        edge_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_DEPENDENCY,
            "task_dependencies",
            &["task_id", "depends_on_task_id", "created_at"],
        ),
        conn,
        sink,
        edge_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_CALENDAR_EVENT_LINK,
            "task_calendar_event_links",
            &["task_id", "calendar_event_id", "created_at", "updated_at"],
        ),
        conn,
        sink,
        edge_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_HABIT_COMPLETION,
            "habit_completions",
            &[
                "habit_id",
                "completed_date",
                "value",
                "note",
                "created_at",
                "updated_at",
            ],
        ),
        conn,
        sink,
        edge_counts,
        shadow_index,
        cancellation,
    )?;
    Ok(())
}
