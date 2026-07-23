use serde_json::Value;

use super::cadence::WeekDay;

/// Stable JSON shape used for habit sync upsert and delete payloads.
///
/// Cadence rides as typed fields, not a JSON-in-TEXT blob: `frequency_type`
/// + `per_period_target` + `day_of_month` mirror the `habits` columns, and
/// `weekdays` (Monday-first 0=Mon … 6=Sun) carries the
/// `weekly` set INSIDE the habit payload so the applier can rebuild the
/// `habit_weekdays` child. Carrying the fields through a borrowed struct
/// keeps tombstones from silently degrading to display-only habit
/// snapshots while staying lighter-weight than a trait abstraction over
/// the CLI / MCP / Tauri adapters.
#[derive(Debug, Clone, Copy)]
pub struct HabitSyncFields<'a> {
    pub id: &'a str,
    pub name: &'a str,
    pub icon: Option<&'a str>,
    pub color: Option<&'a str>,
    pub cue: Option<&'a str>,
    pub frequency_type: &'a str,
    /// The `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Always an
    /// array in the emitted payload (empty when the cadence pins no
    /// specific days).
    pub weekdays: &'a [WeekDay],
    pub per_period_target: i64,
    pub day_of_month: Option<i64>,
    pub target_count: i64,
    /// Optional user-set milestone goal on the habit's progress metric.
    /// `None` leaves it unset (built-in milestone ladder applies);
    /// positive when set. Carried as a nullable scalar independent of
    /// cadence, mirroring `target_count`.
    pub milestone_target: Option<i64>,
    pub archived: bool,
    pub created_at: &'a str,
    pub updated_at: &'a str,
    /// Synced manual display order (ascending). Defaults to 0 until the habit
    /// is explicitly reordered.
    pub position: i64,
    pub version: &'a str,
}

pub fn habit_sync_payload(fields: HabitSyncFields<'_>) -> Value {
    let weekdays: Vec<i64> = fields.weekdays.iter().map(|day| day.as_index()).collect();
    serde_json::json!({
        "id": fields.id,
        "name": fields.name,
        "icon": fields.icon,
        "color": fields.color,
        "cue": fields.cue,
        "frequency_type": fields.frequency_type,
        "weekdays": weekdays,
        "per_period_target": fields.per_period_target,
        "day_of_month": fields.day_of_month,
        "target_count": fields.target_count,
        "milestone_target": fields.milestone_target,
        "archived": fields.archived,
        "created_at": fields.created_at,
        "updated_at": fields.updated_at,
        "position": fields.position,
        "version": fields.version,
    })
}
