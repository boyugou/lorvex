//! Section 3 of the full-export pipeline: child rows
//! (`children.jsonl`).
//!
//! Three entity classes that hang off an aggregate root: task
//! reminders, task checklist items, and habit reminder policies. They land in their
//! own section so the apply pipeline can re-establish the
//! parent→child link order (children only become visible once the
//! parent row has been ingested).

use std::collections::BTreeMap;

use lorvex_domain::naming::{
    ENTITY_HABIT_REMINDER_POLICY, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use rusqlite::Connection;

use crate::export::{run_versioned_writer, ColumnarEntityWriter, ExportError};
use crate::CancellationToken;
use lorvex_sync_payload::payload_shadow::ShadowIndex;

pub(super) fn write_children(
    conn: &Connection,
    sink: &mut dyn std::io::Write,
    entity_counts: &mut BTreeMap<String, u64>,
    shadow_index: &ShadowIndex,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
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
        sink,
        entity_counts,
        shadow_index,
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
        sink,
        entity_counts,
        shadow_index,
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
        sink,
        entity_counts,
        shadow_index,
        cancellation,
    )?;
    Ok(())
}
