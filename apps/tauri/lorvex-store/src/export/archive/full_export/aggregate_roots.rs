//! Section 1 of the full-export pipeline: aggregate roots
//! (`entities.jsonl`).
//!
//! Each entity class lands here through `run_versioned_writer` so the
//! per-row payload is tagged with the canonical schema + payload
//! version stamps the apply pipeline expects on import. The writers
//! are constructed inline (vs. hoisted into module-level constants)
//! because `ColumnarEntityWriter::new` borrows the column slice and a
//! `&'static str` slice is shorter to type out at the call site than
//! to maintain a parallel constant list.

use std::collections::BTreeMap;

use lorvex_domain::naming::{
    ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_LIST, ENTITY_MEMORY, ENTITY_MEMORY_REVISION,
    ENTITY_PREFERENCE, ENTITY_TAG,
};
use rusqlite::Connection;

use crate::export::{
    run_versioned_writer, CalendarEventWriter, ColumnarEntityWriter, CurrentFocusWriter,
    DailyReviewWriter, ExportError, FocusScheduleWriter, HabitWriter, TaskWriter,
};
use crate::CancellationToken;
use lorvex_sync_payload::payload_shadow::ShadowIndex;

pub(super) fn write_aggregate_roots(
    conn: &Connection,
    sink: &mut dyn std::io::Write,
    entity_counts: &mut BTreeMap<String, u64>,
    shadow_index: &ShadowIndex,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_LIST,
            "lists",
            "id",
            &[
                "id",
                "name",
                "color",
                "icon",
                "description",
                "ai_notes",
                "created_at",
                "updated_at",
                "archived_at",
                "position",
            ],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &TaskWriter,
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_TAG,
            "tags",
            "id",
            &[
                "id",
                "display_name",
                "lookup_key",
                "color",
                "created_at",
                "updated_at",
            ],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &HabitWriter::new(),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &CalendarEventWriter,
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_CALENDAR_SUBSCRIPTION,
            "calendar_subscriptions",
            "id",
            &[
                "id",
                "name",
                "url",
                "color",
                "enabled",
                "created_at",
                "updated_at",
            ],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_PREFERENCE,
            "preferences",
            "key",
            &["key", "value", "updated_at"],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_MEMORY,
            "memories",
            "key",
            &["key", "content", "updated_at"],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_MEMORY_REVISION,
            "memory_revisions",
            "id",
            &[
                "id",
                "memory_key",
                "content",
                "operation",
                "source_revision_id",
                "actor",
                "created_at",
            ],
        ),
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &DailyReviewWriter,
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &CurrentFocusWriter,
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &FocusScheduleWriter,
        conn,
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    Ok(())
}
