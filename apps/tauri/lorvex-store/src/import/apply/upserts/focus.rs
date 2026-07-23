//! Upserts for the "day-scoped" aggregates: `current_focus`, `focus_schedule`,
//! and `daily_reviews`. Each aggregate carries embedded child arrays that are
//! materialized into separate tables via the shared ops crate.

use rusqlite::Connection;

use super::super::helpers::{
    optional_i64_field, optional_string_field, required_i64_field, required_string_array_field,
    required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{should_replace_versioned, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_daily_review(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let date = required_string_field(p, "date", "daily_review payload")?;
    let version = entry.version.as_str();
    let summary = required_string_field(p, "summary", "daily_review payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "daily_review payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "daily_review payload")?;
    let mood = optional_i64_field(p, "mood", "daily_review payload")?.map(|v| v.clamp(1, 5));
    let energy_level =
        optional_i64_field(p, "energy_level", "daily_review payload")?.map(|v| v.clamp(1, 5));
    let wins = optional_string_field(p, "wins", "daily_review payload")?;
    let blockers = optional_string_field(p, "blockers", "daily_review payload")?;
    let learnings = optional_string_field(p, "learnings", "daily_review payload")?;
    let ai_synthesis = optional_string_field(p, "ai_synthesis", "daily_review payload")?;
    let timezone = optional_string_field(p, "timezone", "daily_review payload")?;

    let result = match should_replace_versioned(conn, "daily_reviews", "date", &date, version)? {
        None => {
            // No existing row — sync-mode upsert will INSERT.
            crate::repositories::daily_review_ops::sync_upsert_daily_review(
                conn,
                &date,
                &summary,
                mood,
                energy_level,
                wins.as_deref(),
                blockers.as_deref(),
                learnings.as_deref(),
                ai_synthesis.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                ">",
            )?;
            UpsertResult::Created
        }
        Some(true) => {
            // Existing row with older version — sync-mode upsert will UPDATE.
            crate::repositories::daily_review_ops::sync_upsert_daily_review(
                conn,
                &date,
                &summary,
                mood,
                energy_level,
                wins.as_deref(),
                blockers.as_deref(),
                learnings.as_deref(),
                ai_synthesis.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                ">=", // Already passed version check — ensure UPDATE succeeds.
            )?;
            UpsertResult::Updated
        }
        Some(false) => return Ok(UpsertResult::Skipped),
    };

    // Materialize embedded linked_task_ids and linked_list_ids via shared ops.
    materialize_daily_review_links(conn, &date, p)?;

    Ok(result)
}

pub(in crate::import::apply::upserts) fn upsert_current_focus(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let date = required_string_field(p, "date", "current_focus payload")?;
    let version = entry.version.as_str();
    let created_at = required_sync_timestamp_field(p, "created_at", "current_focus payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "current_focus payload")?;
    let briefing = optional_string_field(p, "briefing", "current_focus payload")?;
    let timezone = optional_string_field(p, "timezone", "current_focus payload")?;

    let result = match should_replace_versioned(conn, "current_focus", "date", &date, version)? {
        None => {
            // No existing row — sync-mode upsert will INSERT.
            crate::repositories::current_focus_items::sync_upsert_current_focus(
                conn,
                &date,
                briefing.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                ">",
            )?;
            UpsertResult::Created
        }
        Some(true) => {
            // Existing row with older version — sync-mode upsert will UPDATE.
            crate::repositories::current_focus_items::sync_upsert_current_focus(
                conn,
                &date,
                briefing.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                ">=", // Already passed version check — ensure UPDATE succeeds.
            )?;
            UpsertResult::Updated
        }
        Some(false) => return Ok(UpsertResult::Skipped),
    };

    // Materialize embedded task_ids into current_focus_items.
    materialize_current_focus_items(conn, &date, p)?;

    Ok(result)
}

pub(in crate::import::apply::upserts) fn upsert_focus_schedule(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let date = required_string_field(p, "date", "focus_schedule payload")?;
    let version = entry.version.as_str();
    let created_at = required_sync_timestamp_field(p, "created_at", "focus_schedule payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "focus_schedule payload")?;
    let rationale = optional_string_field(p, "rationale", "focus_schedule payload")?;
    let timezone = optional_string_field(p, "timezone", "focus_schedule payload")?;

    let result = match should_replace_versioned(conn, "focus_schedule", "date", &date, version)? {
        None => {
            // No existing row — sync-mode upsert will INSERT.
            crate::focus_schedule_blocks::sync_upsert_focus_schedule(
                conn,
                &date,
                rationale.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                crate::focus_schedule_blocks::SyncVersionCmp::Greater,
            )?;
            UpsertResult::Created
        }
        Some(true) => {
            // Existing row with older version — sync-mode upsert will UPDATE.
            // Already passed version check above, so the inner LWW gate
            // can accept equal-version writes for idempotent rehydrate.
            crate::focus_schedule_blocks::sync_upsert_focus_schedule(
                conn,
                &date,
                rationale.as_deref(),
                timezone.as_deref(),
                version,
                &created_at,
                &updated_at,
                crate::focus_schedule_blocks::SyncVersionCmp::GreaterOrEqual,
            )?;
            UpsertResult::Updated
        }
        Some(false) => return Ok(UpsertResult::Skipped),
    };

    // Materialize embedded blocks into focus_schedule_blocks.
    materialize_focus_schedule_blocks(conn, &date, p)?;

    Ok(result)
}

// ---------------------------------------------------------------------------
// Embedded-aggregate materialization helpers
// ---------------------------------------------------------------------------

/// Rebuild `current_focus_items` from the embedded `task_ids` array in the payload.
fn materialize_current_focus_items(
    conn: &Connection,
    date: &str,
    payload: &serde_json::Value,
) -> Result<(), ImportError> {
    let task_ids = required_string_array_field(payload, "task_ids", "current_focus payload")?;
    crate::repositories::current_focus_items::materialize_focus_items(conn, date, &task_ids)?;
    Ok(())
}

/// Rebuild `focus_schedule_blocks` from the embedded `blocks` array in the payload.
fn materialize_focus_schedule_blocks(
    conn: &Connection,
    date: &str,
    payload: &serde_json::Value,
) -> Result<(), ImportError> {
    let blocks = super::super::helpers::required_object_array_field(
        payload,
        "blocks",
        "focus_schedule payload",
    )?;
    let entries: Vec<crate::focus_schedule_blocks::ScheduleBlockEntry> = blocks
        .iter()
        .enumerate()
        .map(|(index, block)| {
            let context = format!("focus_schedule payload.blocks[{index}]");
            Ok(crate::focus_schedule_blocks::ScheduleBlockEntry {
                block_type: required_string_field(block, "block_type", &context)?,
                start_minutes: required_i64_field(block, "start_time", &context)?,
                end_minutes: required_i64_field(block, "end_time", &context)?,
                task_id: optional_string_field(block, "task_id", &context)?
                    .filter(|s| !s.is_empty()),
                event_id: optional_string_field(block, "event_id", &context)?
                    .filter(|s| !s.is_empty()),
                title: optional_string_field(block, "title", &context)?,
            })
        })
        .collect::<Result<_, ImportError>>()?;
    crate::focus_schedule_blocks::materialize_schedule_blocks(conn, date, &entries)?;
    Ok(())
}

/// Rebuild `daily_review_task_links` and `daily_review_list_links` from embedded arrays
/// via the shared ops in `daily_review_ops`.
fn materialize_daily_review_links(
    conn: &Connection,
    date: &str,
    payload: &serde_json::Value,
) -> Result<(), ImportError> {
    let task_ids = required_string_array_field(payload, "linked_task_ids", "daily_review payload")?;
    crate::repositories::daily_review_ops::materialize_review_task_links(conn, date, &task_ids)?;

    let list_ids = required_string_array_field(payload, "linked_list_ids", "daily_review payload")?;
    crate::repositories::daily_review_ops::materialize_review_list_links(conn, date, &list_ids)?;

    Ok(())
}
