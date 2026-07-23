use rusqlite::Connection;

use super::super::{should_replace_versioned_composite, UpsertResult};
use crate::import::apply::helpers::{
    required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_task_tag(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let task_id = required_string_field(p, "task_id", "task_tag payload")?;
    let tag_id = required_string_field(p, "tag_id", "task_tag payload")?;
    let version = entry.version.as_str();
    let created_at = required_sync_timestamp_field(p, "created_at", "task_tag payload")?;

    match should_replace_versioned_composite(
        conn,
        "task_tags",
        "task_id",
        &task_id,
        "tag_id",
        &tag_id,
        version,
    )? {
        None => {
            conn.prepare_cached(
                "INSERT INTO task_tags (task_id, tag_id, created_at, version)
                 VALUES (?1,?2,?3,?4)",
            )?
            .execute(rusqlite::params![task_id, tag_id, created_at, version])?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.prepare_cached(
                "UPDATE task_tags SET created_at=?3, version=?4
                 WHERE task_id=?1 AND tag_id=?2",
            )?
            .execute(rusqlite::params![task_id, tag_id, created_at, version])?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}

pub(in crate::import::apply::upserts) fn upsert_task_dependency(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let task_id = required_string_field(p, "task_id", "task_dependency payload")?;
    let depends_on = required_string_field(p, "depends_on_task_id", "task_dependency payload")?;
    let version = entry.version.as_str();
    let created_at = required_sync_timestamp_field(p, "created_at", "task_dependency payload")?;

    match should_replace_versioned_composite(
        conn,
        "task_dependencies",
        "task_id",
        &task_id,
        "depends_on_task_id",
        &depends_on,
        version,
    )? {
        None => {
            conn.prepare_cached(
                "INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
                 VALUES (?1,?2,?3,?4)",
            )?
            .execute(rusqlite::params![task_id, depends_on, created_at, version])?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.prepare_cached(
                "UPDATE task_dependencies SET created_at=?3, version=?4
                 WHERE task_id=?1 AND depends_on_task_id=?2",
            )?
            .execute(rusqlite::params![task_id, depends_on, created_at, version])?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}

pub(in crate::import::apply::upserts) fn upsert_task_calendar_event_link(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let task_id = required_string_field(p, "task_id", "task_calendar_event_link payload")?;
    let calendar_event_id =
        required_string_field(p, "calendar_event_id", "task_calendar_event_link payload")?;
    let version = entry.version.as_str();
    let created_at =
        required_sync_timestamp_field(p, "created_at", "task_calendar_event_link payload")?;
    let updated_at =
        required_sync_timestamp_field(p, "updated_at", "task_calendar_event_link payload")?;

    match should_replace_versioned_composite(
        conn,
        "task_calendar_event_links",
        "task_id",
        &task_id,
        "calendar_event_id",
        &calendar_event_id,
        version,
    )? {
        None => {
            conn.prepare_cached(
                "INSERT INTO task_calendar_event_links (task_id, calendar_event_id,
                 created_at, updated_at, version)
                 VALUES (?1,?2,?3,?4,?5)",
            )?
            .execute(rusqlite::params![
                task_id,
                calendar_event_id,
                created_at,
                updated_at,
                version,
            ])?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.prepare_cached(
                "UPDATE task_calendar_event_links SET created_at=?3, updated_at=?4, version=?5
                 WHERE task_id=?1 AND calendar_event_id=?2",
            )?
            .execute(rusqlite::params![
                task_id,
                calendar_event_id,
                created_at,
                updated_at,
                version,
            ])?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}
