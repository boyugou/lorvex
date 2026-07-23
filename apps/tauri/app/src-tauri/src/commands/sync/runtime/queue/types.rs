use super::*;
use lorvex_domain::naming::EntityKind;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SyncOutboxEntry {
    pub id: String,
    pub entity_type: EntityKind,
    pub entity_id: String,
    pub operation: String,
    pub payload: String,
    pub created_at: String,
    pub device_id: String,
    pub synced_at: Option<String>,
    pub retry_count: i64,
    pub last_retry_at: Option<String>,
}

pub(super) fn outbox_entry_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncOutboxEntry> {
    // sync_outbox.id is INTEGER AUTOINCREMENT; convert to String for the record.
    let id: i64 = row.get(0)?;
    let entity_type_raw: String = row.get(1)?;
    let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            1,
            rusqlite::types::Type::Text,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("invalid sync_outbox.entity_type column value: {entity_type_raw}"),
            )),
        )
    })?;
    Ok(SyncOutboxEntry {
        id: id.to_string(),
        entity_type,
        entity_id: row.get(2)?,
        operation: row.get(3)?,
        payload: row.get(4)?,
        created_at: row.get(5)?,
        device_id: row.get(6)?,
        synced_at: row.get(7)?,
        retry_count: row.get(8)?,
        last_retry_at: row.get(9)?,
    })
}
