//! Walk the SQLite store and assemble an [`ExportDataset`].
//!
//! Each table is rendered through a `VersionedTableWriter` (or a
//! non-versioned helper) into a JSONL buffer, then [`super::parse`] turns
//! those buffers back into typed records. The shape of the returned
//! dataset mirrors the on-disk archive layout so the same data can be
//! either streamed to a ZIP or filtered by
//! [`super::scope::scope_export_dataset`].

use super::super::{
    run_versioned_writer, write_audit_rows, write_payload_shadow_rows, write_provider_link_rows,
    write_tombstone_rows, CalendarEventWriter, ColumnarEntityWriter, CurrentFocusWriter,
    DailyReviewWriter, EdgeWriter, ExportError, FocusScheduleWriter, HabitWriter, TaskWriter,
};
use super::parse::{parse_json_records, parse_json_values, parse_versioned_records};
use super::ExportDataset;
use crate::cancellation::check_export_cancelled;
use crate::CancellationToken;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
    ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_HABIT_REMINDER_POLICY, ENTITY_LIST, ENTITY_MEMORY,
    ENTITY_MEMORY_REVISION, ENTITY_PREFERENCE, ENTITY_TAG, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER,
};
use rusqlite::Connection;
use std::collections::BTreeMap;

pub(crate) fn collect_export_dataset(
    conn: &Connection,
    cancellation: &dyn CancellationToken,
) -> Result<ExportDataset, ExportError> {
    let mut entity_counts = BTreeMap::new();
    let mut edge_counts = BTreeMap::new();
    let mut entities_buf = Vec::new();
    let mut edges_buf = Vec::new();
    let mut children_buf = Vec::new();
    let mut audit_buf = Vec::new();
    let mut tombstones_buf = Vec::new();
    let mut shadows_buf = Vec::new();
    // see archive.rs for the rationale; one ShadowIndex per
    // dataset collect-pass instead of rebuilding per writer.
    let shadow_index = lorvex_sync_payload::payload_shadow::ShadowIndex::build(conn)?;
    check_export_cancelled(cancellation)?;

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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &TaskWriter,
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &HabitWriter::new(),
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &CalendarEventWriter,
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
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
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &DailyReviewWriter,
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &CurrentFocusWriter,
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &FocusScheduleWriter,
        conn,
        &mut entities_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;

    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_TAG,
            "task_tags",
            &["task_id", "tag_id", "created_at"],
        ),
        conn,
        &mut edges_buf,
        &mut edge_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_DEPENDENCY,
            "task_dependencies",
            &["task_id", "depends_on_task_id", "created_at"],
        ),
        conn,
        &mut edges_buf,
        &mut edge_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &EdgeWriter::new(
            EDGE_TASK_CALENDAR_EVENT_LINK,
            "task_calendar_event_links",
            &["task_id", "calendar_event_id", "created_at", "updated_at"],
        ),
        conn,
        &mut edges_buf,
        &mut edge_counts,
        &shadow_index,
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
        &mut edges_buf,
        &mut edge_counts,
        &shadow_index,
        cancellation,
    )?;

    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_TASK_REMINDER,
            "task_reminders",
            "id",
            &[
                "id",
                "task_id",
                "reminder_at",
                "dismissed_at",
                "cancelled_at",
                "created_at",
                // local wall-clock anchor columns.
                "original_local_time",
                "original_tz",
            ],
        ),
        conn,
        &mut children_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_TASK_CHECKLIST_ITEM,
            "task_checklist_items",
            "id",
            &[
                "id",
                "task_id",
                "position",
                "text",
                "completed_at",
                "created_at",
                "updated_at",
            ],
        ),
        conn,
        &mut children_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;
    run_versioned_writer(
        &ColumnarEntityWriter::new(
            ENTITY_HABIT_REMINDER_POLICY,
            "habit_reminder_policies",
            "id",
            &[
                "id",
                "habit_id",
                "reminder_time",
                "enabled",
                "created_at",
                "updated_at",
            ],
        ),
        conn,
        &mut children_buf,
        &mut entity_counts,
        &shadow_index,
        cancellation,
    )?;

    write_audit_rows(conn, &mut audit_buf, cancellation)?;
    write_tombstone_rows(conn, &mut tombstones_buf, cancellation)?;
    write_payload_shadow_rows(conn, &mut shadows_buf, cancellation)?;

    let mut provider_links_buf: Vec<u8> = Vec::new();
    write_provider_link_rows(conn, &mut provider_links_buf, cancellation)?;
    check_export_cancelled(cancellation)?;

    Ok(ExportDataset {
        entities: parse_versioned_records(&entities_buf, true)?,
        edges: parse_versioned_records(&edges_buf, false)?,
        children: parse_versioned_records(&children_buf, true)?,
        audit: parse_json_records(&audit_buf)?,
        tombstones: parse_json_values(&tombstones_buf)?,
        shadows: parse_json_values(&shadows_buf)?,
        provider_links: parse_json_records(&provider_links_buf)?,
    })
}
