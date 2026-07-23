//! `habits` writer with the embedded `weekdays` cadence array.
//!
//! Reuses the canonical habit sync-payload projection + row mapper
//! (`crate::payload_loaders`) so the export payload is byte-identical to
//! the sync-envelope payload: typed cadence columns (`frequency_type`,
//! `per_period_target`, `day_of_month`) plus the `weekly`
//! weekday set materialized from the `habit_weekdays` child. `lookup_key`
//! is omitted — import re-derives it from the validated name — and the
//! `habit_weekdays` child is never exported as a standalone entity: it is
//! rebuilt from the parent payload's `weekdays` array on import.

use rusqlite::Connection;
use serde_json::Value;

use super::{ExtractedRow, VersionedTableWriter};
use crate::error::StoreError;
use crate::export::ExportError;
use crate::payload_loaders::{habit_payload_from_row, HABIT_SELECT_COLUMNS};
use lorvex_domain::naming::ENTITY_HABIT;

pub(in crate::export) struct HabitWriter {
    select_sql: String,
}

impl HabitWriter {
    pub(in crate::export) fn new() -> Self {
        Self {
            select_sql: format!("SELECT {HABIT_SELECT_COLUMNS} FROM habits"),
        }
    }
}

impl VersionedTableWriter for HabitWriter {
    fn entity_type(&self) -> &str {
        ENTITY_HABIT
    }

    fn select_sql(&self) -> &str {
        &self.select_sql
    }

    fn extract(
        &self,
        _conn: &Connection,
        row: &rusqlite::Row<'_>,
    ) -> Result<ExtractedRow, ExportError> {
        let payload = habit_payload_from_row(row)?;
        let entity_id = payload
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                ExportError::Store(StoreError::Serialization(
                    "habit export payload missing string `id`".to_string(),
                ))
            })?
            .to_string();
        let version = payload
            .get("version")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                ExportError::Store(StoreError::Serialization(
                    "habit export payload missing string `version`".to_string(),
                ))
            })?
            .to_string();
        Ok(ExtractedRow {
            entity_id,
            version,
            payload,
        })
    }
}
