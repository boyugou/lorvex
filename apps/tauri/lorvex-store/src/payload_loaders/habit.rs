use rusqlite::{Connection, OptionalExtension, Row};
use serde_json::Value;

use lorvex_domain::habits::WeekDay;

use crate::error::StoreError;

/// Canonical habit sync-envelope SELECT. Emits the typed cadence columns
/// (`frequency_type`, `per_period_target`, `day_of_month`) and
/// materializes the `weekly` weekday set from the `habit_weekdays` child as
/// a Monday-first (0=Mon … 6=Sun) JSON integer array via a correlated
/// `json_group_array` subquery — the payload's `weekdays` field, mirroring
/// how the `ai_changelog` entity-id projection rebuilds its wire array.
/// `lookup_key` is intentionally omitted: peers re-derive it from the
/// validated name on apply. Every query using this projection reads
/// `FROM habits`, so the subquery's `habits.id` reference resolves.
pub const HABIT_SELECT_COLUMNS: &str = "id, name, icon, color, cue, frequency_type, \
    per_period_target, day_of_month, target_count, milestone_target, archived, created_at, \
    updated_at, position, version, (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays \
    WHERE habit_id = habits.id ORDER BY weekday)) AS weekdays";

#[derive(Debug, Clone)]
struct HabitPayloadRow {
    id: String,
    name: String,
    icon: Option<String>,
    color: Option<String>,
    cue: Option<String>,
    frequency_type: String,
    per_period_target: i64,
    day_of_month: Option<i64>,
    target_count: i64,
    milestone_target: Option<i64>,
    archived: bool,
    created_at: String,
    updated_at: String,
    position: i64,
    version: String,
    weekdays: Vec<WeekDay>,
}

impl HabitPayloadRow {
    fn from_row(row: &Row<'_>) -> rusqlite::Result<Self> {
        let weekdays_json: String = row.get(15)?;
        let weekdays = parse_weekdays_json(&weekdays_json).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                15,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?;
        Ok(Self {
            id: row.get(0)?,
            name: row.get(1)?,
            icon: row.get(2)?,
            color: row.get(3)?,
            cue: row.get(4)?,
            frequency_type: row.get(5)?,
            per_period_target: row.get(6)?,
            day_of_month: row.get(7)?,
            target_count: row.get(8)?,
            milestone_target: row.get(9)?,
            // `habits.archived` is registered in
            // `lorvex_domain::storage_schema::SQLITE_BOOL_COLUMNS` so the
            // wire shape is a JSON boolean — matching the generic pragma
            // reader's behavior in `lorvex_sync::outbox_enqueue::snapshot`.
            archived: row.get(10)?,
            created_at: row.get(11)?,
            updated_at: row.get(12)?,
            position: row.get(13)?,
            version: row.get(14)?,
            weekdays,
        })
    }

    fn sync_fields(&self) -> lorvex_domain::habits::HabitSyncFields<'_> {
        lorvex_domain::habits::HabitSyncFields {
            id: &self.id,
            name: &self.name,
            icon: self.icon.as_deref(),
            color: self.color.as_deref(),
            cue: self.cue.as_deref(),
            frequency_type: &self.frequency_type,
            weekdays: &self.weekdays,
            per_period_target: self.per_period_target,
            day_of_month: self.day_of_month,
            target_count: self.target_count,
            milestone_target: self.milestone_target,
            archived: self.archived,
            created_at: &self.created_at,
            updated_at: &self.updated_at,
            position: self.position,
            version: &self.version,
        }
    }

    fn payload(&self) -> Value {
        lorvex_domain::habits::habit_sync_payload(self.sync_fields())
    }
}

/// Parse the materialized `habit_weekdays` JSON array (Monday-first ints
/// 0=Mon … 6=Sun) into typed [`WeekDay`] values. Out-of-range entries are
/// dropped rather than failing the read — the schema CHECK already pins the
/// column to `0..=6`, so this only guards against malformed data.
fn parse_weekdays_json(raw: &str) -> Result<Vec<WeekDay>, serde_json::Error> {
    let indices: Vec<i64> = serde_json::from_str(raw)?;
    Ok(indices
        .into_iter()
        .filter_map(WeekDay::from_index)
        .collect())
}

pub fn habit_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(HabitPayloadRow::from_row(row)?.payload())
}

pub fn load_habit_sync_payload(
    conn: &Connection,
    habit_id: &lorvex_domain::HabitId,
) -> Result<Option<Value>, StoreError> {
    let sql = format!("SELECT {HABIT_SELECT_COLUMNS} FROM habits WHERE id = ?1");
    conn.query_row(&sql, [habit_id.as_str()], |row| {
        Ok(HabitPayloadRow::from_row(row)?.payload())
    })
    .optional()
    .map_err(StoreError::from)
}
