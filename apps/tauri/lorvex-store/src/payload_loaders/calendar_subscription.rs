use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const CALENDAR_SUBSCRIPTION_SELECT_COLUMNS: &str =
    "id, name, url, color, enabled, created_at, updated_at, version";

pub struct CalendarSubscriptionPayload<'a> {
    pub id: &'a str,
    pub name: &'a str,
    pub url: &'a str,
    pub color: Option<&'a str>,
    pub enabled: bool,
    pub created_at: &'a str,
    pub updated_at: &'a str,
    pub version: &'a str,
}

pub fn calendar_subscription_payload(fields: CalendarSubscriptionPayload<'_>) -> Value {
    json!({
        "id": fields.id,
        "name": fields.name,
        "url": fields.url,
        "color": fields.color,
        "enabled": fields.enabled,
        "created_at": fields.created_at,
        "updated_at": fields.updated_at,
        "version": fields.version,
    })
}

pub fn calendar_subscription_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let id: String = row.get(0)?;
    let name: String = row.get(1)?;
    let url: String = row.get(2)?;
    let color: Option<String> = row.get(3)?;
    let created_at: String = row.get(5)?;
    let updated_at: String = row.get(6)?;
    let version: String = row.get(7)?;
    Ok(calendar_subscription_payload(CalendarSubscriptionPayload {
        id: &id,
        name: &name,
        url: &url,
        color: color.as_deref(),
        enabled: row.get(4)?,
        created_at: &created_at,
        updated_at: &updated_at,
        version: &version,
    }))
}

pub fn load_calendar_subscription_sync_payload(
    conn: &Connection,
    id: &str,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {CALENDAR_SUBSCRIPTION_SELECT_COLUMNS} \
             FROM calendar_subscriptions WHERE id = ?1"
        )
    });
    Ok(conn
        .query_row(sql, params![id], calendar_subscription_payload_from_row)
        .optional()?)
}
