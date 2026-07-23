//! Shared helper for LWW-gated hard DELETE statements.
//!
//! Local destructive writes must obey the same version rule as updates:
//! the caller's freshly minted HLC must be strictly newer than the row's
//! stored `version`, otherwise the delete loses to a concurrent/remote
//! write and must leave the row intact.

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::StoreError;

pub fn execute_lww_delete_by_id(
    conn: &Connection,
    table: &'static str,
    id_column: &'static str,
    entity: &'static str,
    id: &str,
    version: &str,
) -> Result<usize, StoreError> {
    let sql = format!(
        "DELETE FROM {table}
         WHERE {id_column} = ?1 AND ?2 > version
         RETURNING 1",
    );
    match conn
        .prepare_cached(&sql)?
        .query_row(params![id, version], |_row| Ok(()))
    {
        Ok(()) => Ok(1),
        Err(rusqlite::Error::QueryReturnedNoRows) => {
            let exists_sql = format!("SELECT 1 FROM {table} WHERE {id_column} = ?1 LIMIT 1");
            let exists: Option<i64> = conn
                .prepare_cached(&exists_sql)?
                .query_row(params![id], |row| row.get(0))
                .optional()?;
            if exists.is_some() {
                Err(StoreError::StaleVersion {
                    entity,
                    id: id.to_string(),
                })
            } else {
                Ok(0)
            }
        }
        Err(error) => Err(error.into()),
    }
}
