use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use lorvex_store::SyncStatusSnapshot;
use rusqlite::types::Value as SqlValue;

use crate::cli::OutputFormat;
use crate::models::PendingOutboxEntry;
use crate::render::{render_pending_outbox_entries, render_sync_status};

const PENDING_OUTBOX_LIMIT_DEFAULT: u32 = 100;
const PENDING_OUTBOX_LIMIT_CAP: u32 = 500;

pub(crate) fn run_sync_status(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let status = get_sync_status_with_conn(&conn)?;
    render_sync_status(&db_path, &status, format)
}

pub(crate) fn run_sync_outbox(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let limit = match limit {
        0 => PENDING_OUTBOX_LIMIT_DEFAULT,
        value => value.min(PENDING_OUTBOX_LIMIT_CAP),
    };
    let entries = get_pending_outbox_entries_with_conn(&conn, limit)?;
    render_pending_outbox_entries(&db_path, &entries, limit, format)
}

fn get_pending_outbox_entries_with_conn(
    conn: &rusqlite::Connection,
    limit: u32,
) -> Result<Vec<PendingOutboxEntry>, crate::error::CliError> {
    let mut stmt = conn.prepare(
        "
        SELECT
          id, entity_type, entity_id, operation, payload,
          created_at, device_id, synced_at, retry_count, last_retry_at
        FROM sync_outbox
        WHERE synced_at IS NULL
        ORDER BY created_at ASC, id ASC
        LIMIT ?
        ",
    )?;
    let rows = stmt.query_map([SqlValue::Integer(i64::from(limit))], |row| {
        let payload: String = row.get("payload")?;
        let payload = serde_json::from_str(&payload).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                4,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?;
        let entity_type_raw: String = row.get("entity_type")?;
        let entity_type =
            lorvex_domain::naming::EntityKind::parse(&entity_type_raw).ok_or_else(|| {
                rusqlite::Error::FromSqlConversionFailure(
                    1,
                    rusqlite::types::Type::Text,
                    Box::new(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("invalid sync_outbox.entity_type column value: {entity_type_raw}"),
                    )),
                )
            })?;
        Ok(PendingOutboxEntry {
            id: row.get("id")?,
            entity_type,
            entity_id: row.get("entity_id")?,
            operation: row.get("operation")?,
            payload,
            created_at: row.get("created_at")?,
            device_id: row.get("device_id")?,
            synced_at: row.get("synced_at")?,
            retry_count: row.get("retry_count")?,
            last_retry_at: row.get("last_retry_at")?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(crate::error::CliError::from)
}

fn get_sync_status_with_conn(
    conn: &rusqlite::Connection,
) -> Result<SyncStatusSnapshot, crate::error::CliError> {
    lorvex_store::load_sync_status_snapshot(conn).map_err(crate::error::CliError::from)
}

#[cfg(test)]
mod tests;
