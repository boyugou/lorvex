//! Tombstone import application: JSONL parsing, last-writer-wins conflict
//! handling, payload-shadow redirect cleanup, and live-row deletion for
//! rows that lose to an imported tombstone.

use rusqlite::{Connection, OptionalExtension};

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::EntityKind;

use crate::cancellation::check_import_cancelled;
use crate::import::ImportError;
use crate::CancellationToken;

use super::helpers;
use super::helpers::{optional_string_field, required_string_field, required_sync_timestamp_field};

/// Apply tombstones from `tombstones.jsonl` content.
pub(in crate::import) fn apply_tombstones(
    conn: &Connection,
    content: &str,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry: serde_json::Value = serde_json::from_str(line)?;
        let redirect_entity_id =
            optional_string_field(&entry, "redirect_entity_id", "tombstone entry")?;
        let redirect_entity_type =
            optional_string_field(&entry, "redirect_entity_type", "tombstone entry")?;
        match (
            redirect_entity_id.as_deref(),
            redirect_entity_type.as_deref(),
        ) {
            (Some(_), None) => {
                return Err(helpers::invalid_payload(
                    "tombstone entry.redirect_entity_type must be a string when redirect_entity_id is present",
                ));
            }
            (None, Some(_)) => {
                return Err(helpers::invalid_payload(
                    "tombstone entry.redirect_entity_id must be a string when redirect_entity_type is present",
                ));
            }
            _ => {}
        }
        let entity_type = required_string_field(&entry, "entity_type", "tombstone entry")?;
        let entity_kind = parse_tombstone_entity_type(&entity_type)?;
        let redirect_entity_kind = redirect_entity_type
            .as_deref()
            .map(parse_tombstone_redirect_entity_type)
            .transpose()?;
        let entity_id = required_string_field(&entry, "entity_id", "tombstone entry")?;
        let version = required_string_field(&entry, "version", "tombstone entry")?;
        let deleted_at = required_sync_timestamp_field(&entry, "deleted_at", "tombstone entry")?;
        apply_import_tombstone(
            conn,
            entity_kind.as_str(),
            &entity_id,
            &version,
            &deleted_at,
            redirect_entity_id.as_deref(),
            redirect_entity_kind.map(|kind| kind.as_str()),
        )?;
    }
    Ok(())
}

fn parse_tombstone_entity_type(entity_type: &str) -> Result<EntityKind, ImportError> {
    EntityKind::parse(entity_type).ok_or_else(|| {
        helpers::invalid_payload(format!(
            "tombstones.jsonl entry uses unknown entity_type `{entity_type}`; upgrade Lorvex before importing this archive"
        ))
    })
}

fn parse_tombstone_redirect_entity_type(
    redirect_entity_type: &str,
) -> Result<EntityKind, ImportError> {
    EntityKind::parse(redirect_entity_type).ok_or_else(|| {
        helpers::invalid_payload(format!(
            "tombstones.jsonl entry uses unknown redirect_entity_type `{redirect_entity_type}`; upgrade Lorvex before importing this archive"
        ))
    })
}

fn apply_import_tombstone(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
    deleted_at: &str,
    redirect_entity_id: Option<&str>,
    redirect_entity_type: Option<&str>,
) -> Result<(), ImportError> {
    Hlc::parse(version).map_err(|error| {
        helpers::invalid_payload(format!(
            "incoming tombstone {entity_type}:{entity_id} must use a valid HLC version: {error}"
        ))
    })?;
    let existing_version = effective_tombstone_version(conn, entity_type, entity_id)?;
    let should_write = match existing_version.as_deref() {
        None => true,
        Some(existing) => helpers::incoming_hlc_replaces_existing(
            existing,
            version,
            &format!("sync_tombstones {entity_type}:{entity_id}"),
        )?,
    };

    let updated = if should_write {
        if existing_version.is_some() {
            conn.prepare_cached(
                "UPDATE sync_tombstones SET
                    version = ?3,
                    deleted_at = ?4,
                    redirect_entity_id = ?5,
                    redirect_entity_type = ?6
                 WHERE entity_type = ?1 AND entity_id = ?2",
            )?
            .execute(rusqlite::params![
                entity_type,
                entity_id,
                version,
                deleted_at,
                redirect_entity_id,
                redirect_entity_type,
            ])?
        } else {
            conn.prepare_cached(
                "INSERT INTO sync_tombstones
                    (entity_type, entity_id, version, deleted_at,
                     redirect_entity_id, redirect_entity_type)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?
            .execute(rusqlite::params![
                entity_type,
                entity_id,
                version,
                deleted_at,
                redirect_entity_id,
                redirect_entity_type,
            ])?
        }
    } else {
        0
    };

    if updated > 0 {
        if let Some(redirect_id) = redirect_entity_id {
            let redirect_type = redirect_entity_type
                .ok_or_else(|| helpers::invalid_payload(
                    "tombstone entry.redirect_entity_type must be present when redirect_entity_id is present",
                ))?;
            lorvex_sync_payload::payload_shadow::merge_shadow_into_redirect(
                conn,
                entity_type,
                entity_id,
                redirect_type,
                redirect_id,
            )?;
        } else {
            lorvex_sync_payload::payload_shadow::remove_shadow(conn, entity_type, entity_id)?;
        }
    }
    if let Some(effective_version) = effective_tombstone_version(conn, entity_type, entity_id)? {
        delete_live_row_losing_to_import_tombstone(
            conn,
            entity_type,
            entity_id,
            &effective_version,
        )?;
    }

    Ok(())
}

fn effective_tombstone_version(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<String>, ImportError> {
    Ok(conn
        .prepare_cached(
            "SELECT version FROM sync_tombstones
             WHERE entity_type = ?1 AND entity_id = ?2
             LIMIT 1",
        )?
        .query_row(rusqlite::params![entity_type, entity_id], |row| row.get(0))
        .optional()?)
}

fn delete_live_row_losing_to_import_tombstone(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    tombstone_version: &str,
) -> Result<(), ImportError> {
    let Some(kind) = EntityKind::parse(entity_type) else {
        return Ok(());
    };
    let tombstone_hlc = Hlc::parse(tombstone_version).map_err(|error| {
        helpers::invalid_payload(format!(
            "tombstone {entity_type}:{entity_id} has invalid HLC version: {error}"
        ))
    })?;

    let Some(row) = live_row_version(conn, kind, entity_id)? else {
        return Ok(());
    };
    let live_hlc = Hlc::parse(&row.version).map_err(|error| {
        helpers::invalid_payload(format!(
            "local {} row `{}` has invalid HLC version: {error}",
            kind.table_name().unwrap_or("<unknown>"),
            entity_id
        ))
    })?;
    if live_hlc <= tombstone_hlc {
        delete_live_row_by_locator(conn, &row)?;
    }
    Ok(())
}

struct LiveRowLocator {
    table: &'static str,
    pk_columns: Vec<&'static str>,
    pk_values: Vec<String>,
    version: String,
}

fn live_row_version(
    conn: &Connection,
    kind: EntityKind,
    entity_id: &str,
) -> Result<Option<LiveRowLocator>, ImportError> {
    if let Some((table, pk_column)) = kind.table_pk() {
        lorvex_domain::assert_safe_sql_identifier(table);
        lorvex_domain::assert_safe_sql_identifier(pk_column);
        let sql = format!("SELECT version FROM {table} WHERE {pk_column} = ?1");
        let version: Option<String> = conn
            .query_row(&sql, [entity_id], |row| row.get(0))
            .optional()?;
        return Ok(version.map(|version| LiveRowLocator {
            table,
            pk_columns: vec![pk_column],
            pk_values: vec![entity_id.to_string()],
            version,
        }));
    }

    let Some((table, left_column, right_column)) = composite_tombstone_table(kind) else {
        return Ok(None);
    };
    let (left, right) = split_import_composite_entity_id(entity_id)?;
    let sql =
        format!("SELECT version FROM {table} WHERE {left_column} = ?1 AND {right_column} = ?2");
    let version: Option<String> = conn
        .query_row(&sql, rusqlite::params![left, right], |row| row.get(0))
        .optional()?;
    Ok(version.map(|version| LiveRowLocator {
        table,
        pk_columns: vec![left_column, right_column],
        pk_values: vec![left.to_string(), right.to_string()],
        version,
    }))
}

const fn composite_tombstone_table(
    kind: EntityKind,
) -> Option<(&'static str, &'static str, &'static str)> {
    match kind {
        EntityKind::TaskTag => Some(("task_tags", "task_id", "tag_id")),
        EntityKind::TaskDependency => Some(("task_dependencies", "task_id", "depends_on_task_id")),
        EntityKind::TaskCalendarEventLink => {
            Some(("task_calendar_event_links", "task_id", "calendar_event_id"))
        }
        EntityKind::HabitCompletion => Some(("habit_completions", "habit_id", "completed_date")),
        _ => None,
    }
}

fn split_import_composite_entity_id(entity_id: &str) -> Result<(&str, &str), ImportError> {
    let Some((left, right)) = entity_id.split_once(':') else {
        return Err(helpers::invalid_payload(format!(
            "composite tombstone entity_id `{entity_id}` must contain one ':' separator"
        )));
    };
    if left.is_empty() || right.is_empty() || right.contains(':') {
        return Err(helpers::invalid_payload(format!(
            "composite tombstone entity_id `{entity_id}` must contain exactly two non-empty parts"
        )));
    }
    Ok((left, right))
}

fn delete_live_row_by_locator(conn: &Connection, row: &LiveRowLocator) -> Result<(), ImportError> {
    lorvex_domain::assert_safe_sql_identifier(row.table);
    for column in &row.pk_columns {
        lorvex_domain::assert_safe_sql_identifier(column);
    }

    let predicates = row
        .pk_columns
        .iter()
        .enumerate()
        .map(|(index, column)| format!("{column} = ?{}", index + 1))
        .collect::<Vec<_>>()
        .join(" AND ");
    let sql = format!("DELETE FROM {} WHERE {}", row.table, predicates);

    match row.pk_values.as_slice() {
        [one] => {
            conn.execute(&sql, [one.as_str()])?;
        }
        [one, two] => {
            conn.execute(&sql, rusqlite::params![one, two])?;
        }
        _ => unreachable!("live row locators are simple or two-column composite keys"),
    }
    Ok(())
}
