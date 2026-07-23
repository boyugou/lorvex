//! Upserts for `lists` and `tags` entities.

use rusqlite::Connection;

use lorvex_domain::validation::{MAX_LIST_DESCRIPTION_LENGTH, MAX_TITLE_LENGTH};

use super::super::helpers::{
    normalize_import_sync_timestamp, optional_i64_field, optional_string_field,
    required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{import_lww_upsert, LwwUpsertSpec, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_list(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "list payload")?;
    let version = entry.version.as_str();
    let name = required_string_field(p, "name", "list payload")?;
    // cap list name at the shared title length so a
    // hostile ZIP can't smuggle in a multi-MB list label.
    if name.chars().count() > MAX_TITLE_LENGTH {
        return Err(ImportError::InvalidPayload(format!(
            "list {id} name is too long ({} chars; max {})",
            name.chars().count(),
            MAX_TITLE_LENGTH
        )));
    }
    let created_at = required_sync_timestamp_field(p, "created_at", "list payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "list payload")?;
    let color = optional_string_field(p, "color", "list payload")?;
    let icon = optional_string_field(p, "icon", "list payload")?;
    let description = optional_string_field(p, "description", "list payload")?;
    if let Some(ref d) = description {
        // list descriptions render in list-picker
        // chrome and side-rail summaries; they are short metadata,
        // not free-form prose like task bodies. Cap at the dedicated
        // MAX_LIST_DESCRIPTION_LENGTH (1 KB) so an over-cap import
        // can't smuggle in a multi-page description that wedges every
        // UI surface that displays it.
        let count = d.chars().count();
        if count > MAX_LIST_DESCRIPTION_LENGTH {
            return Err(ImportError::InvalidPayload(format!(
                "list {id} description is too long ({count} chars; max {MAX_LIST_DESCRIPTION_LENGTH})"
            )));
        }
    }
    let ai_notes = optional_string_field(p, "ai_notes", "list payload")?;
    let (archived_at_present, archived_at) =
        optional_nullable_sync_timestamp_field(p, "archived_at", "list payload")?;
    let archived_at_present = i64::from(archived_at_present);
    let position = optional_i64_field(p, "position", "list payload")?;
    let position_present = i64::from(position.is_some());
    let position_value = position.unwrap_or(0);

    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "lists",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql: "INSERT INTO lists
                    (id, name, color, icon, description, ai_notes, created_at, updated_at,
                     version, archived_at, position)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?11, ?13)",
            update_sql: "UPDATE lists SET name=?2, color=?3, icon=?4, description=?5, ai_notes=?6,
                 created_at=?7, updated_at=?8, version=?9,
                 archived_at=CASE WHEN ?10 != 0 THEN ?11 ELSE archived_at END,
                 position=CASE WHEN ?12 != 0 THEN ?13 ELSE position END
                 WHERE id=?1",
        },
        rusqlite::params![
            id,
            name,
            color.as_deref(),
            icon.as_deref(),
            description.as_deref(),
            ai_notes.as_deref(),
            created_at,
            updated_at,
            version,
            archived_at_present,
            archived_at.as_deref(),
            position_present,
            position_value,
        ],
    )
}

fn optional_nullable_sync_timestamp_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<(bool, Option<String>), ImportError> {
    match payload.get(key) {
        None => Ok((false, None)),
        Some(serde_json::Value::Null) => Ok((true, None)),
        Some(serde_json::Value::String(value)) => Ok((
            true,
            Some(normalize_import_sync_timestamp(
                value.clone(),
                key,
                context,
            )?),
        )),
        Some(_) => Err(ImportError::InvalidPayload(format!(
            "{context}.{key} must be a string or null when present"
        ))),
    }
}

pub(in crate::import::apply::upserts) fn upsert_tag(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "tag payload")?;
    let version = entry.version.as_str();
    let display_name = required_string_field(p, "display_name", "tag payload")?;
    let lookup_key = required_string_field(p, "lookup_key", "tag payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "tag payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "tag payload")?;
    let color = optional_string_field(p, "color", "tag payload")?;

    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "tags",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql:
                "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            update_sql:
                "UPDATE tags SET display_name=?2, lookup_key=?3, color=?4, created_at=?5,
                 updated_at=?6, version=?7 WHERE id=?1",
        },
        rusqlite::params![
            id,
            display_name,
            lookup_key,
            color.as_deref(),
            created_at,
            updated_at,
            version,
        ],
    )
}
