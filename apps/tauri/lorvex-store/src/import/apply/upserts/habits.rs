//! Upserts for habit aggregate: parent `habits`, the `habit_weekdays`
//! materialization, the `habit_completions` edge, and the
//! `habit_reminder_policies` child.

use rusqlite::Connection;
use serde_json::Value;

use lorvex_domain::habits::WeekDay;

use super::super::helpers::{
    optional_string_field, required_bool_as_i64_field, required_i64_field, required_string_field,
    required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{import_lww_upsert, should_replace_versioned_composite, LwwUpsertSpec, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_habit(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "habit payload")?;
    let version = entry.version.as_str();
    let name = required_string_field(p, "name", "habit payload")?;
    let frequency_type = required_string_field(p, "frequency_type", "habit payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "habit payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "habit payload")?;
    let target_count = required_i64_field(p, "target_count", "habit payload")?;
    let archived = required_bool_as_i64_field(p, "archived", "habit payload")?;
    let icon = optional_string_field(p, "icon", "habit payload")?;
    let color = optional_string_field(p, "color", "habit payload")?;
    let cue = optional_string_field(p, "cue", "habit payload")?;

    // Typed cadence fields. An older export that predates a column omits it;
    // the schema DEFAULTs (per_period_target 1, day_of_month NULL) apply.
    // `weekdays` is an array of Monday-first ints (0=Mon … 6=Sun) carried
    // inside the habit payload.
    let weekdays = parse_weekdays_field(p, &id)?;
    let per_period_target = p
        .get("per_period_target")
        .and_then(Value::as_i64)
        .unwrap_or(1);
    let day_of_month = parse_day_of_month_field(p, &id)?;
    // Optional user-set milestone goal (nullable scalar, independent of
    // cadence). An older export that predates the column omits it → NULL.
    // Bound directly from the payload, not through the create-draft
    // validator (which does not carry it), mirroring `archived`.
    let milestone_target = parse_milestone_target_field(p, &id)?;

    // Bridge the typed cadence fields into the typed primitive at the
    // import seam, then re-render the validated cadence to its typed
    // columns — a malformed cadence fails at import instead of round-
    // tripping a corrupted shape.
    let frequency = lorvex_domain::habits::HabitCadence::from_fields(
        &lorvex_domain::habits::HabitFrequencyFields {
            frequency_type: frequency_type.clone(),
            weekdays: if weekdays.is_empty() {
                None
            } else {
                Some(weekdays)
            },
            per_period_target,
            day_of_month,
        },
    )
    .map_err(|error| {
        ImportError::InvalidPayload(format!("habit {id} failed cadence parse: {error}"))
    })?;
    let validated = lorvex_domain::habits::validate_habit_create_draft(
        lorvex_domain::habits::HabitCreateDraft {
            name: &name,
            icon: icon.as_deref(),
            color: color.as_deref(),
            cue: cue.as_deref(),
            frequency: Some(frequency),
            target_count: Some(target_count),
        },
    )
    .map_err(|error| {
        ImportError::InvalidPayload(format!("habit {id} failed validation: {error}"))
    })?;
    let cadence_fields = validated.frequency().to_fields();

    let result = import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "habits",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql: "INSERT INTO habits (id, name, icon, color, cue,
                 frequency_type, per_period_target, day_of_month, target_count, milestone_target,
                 archived, lookup_key, created_at, updated_at, version)
                VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15)",
            update_sql: "UPDATE habits SET name=?2, icon=?3, color=?4, cue=?5, frequency_type=?6,
                 per_period_target=?7, day_of_month=?8, target_count=?9, milestone_target=?10,
                 archived=?11, lookup_key=?12, created_at=?13, updated_at=?14, version=?15
                 WHERE id=?1",
        },
        rusqlite::params![
            id,
            validated.name(),
            validated.icon(),
            validated.color(),
            validated.cue(),
            &cadence_fields.frequency_type,
            cadence_fields.per_period_target,
            cadence_fields.day_of_month,
            validated.target_count(),
            milestone_target,
            archived,
            validated.lookup_key(),
            created_at,
            updated_at,
            version,
        ],
    )?;

    // Rebuild the `habit_weekdays` materialization from the validated
    // cadence, but only when the upsert actually landed (an older-version
    // row is skipped, and its current weekdays must be preserved). The set
    // is empty for every non-weekly cadence and for weekly-every-day.
    if result != UpsertResult::Skipped {
        rebuild_habit_weekdays(conn, &id, cadence_fields.weekdays.as_deref().unwrap_or(&[]))?;
    }

    Ok(result)
}

/// Delete-then-insert the `habit_weekdays` rows for one habit from a
/// weekday set. Device-local materialization: the rows carry no version.
fn rebuild_habit_weekdays(
    conn: &Connection,
    habit_id: &str,
    weekdays: &[WeekDay],
) -> Result<(), ImportError> {
    conn.execute("DELETE FROM habit_weekdays WHERE habit_id = ?1", [habit_id])?;
    for day in weekdays {
        conn.execute(
            "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?1, ?2)",
            rusqlite::params![habit_id, day.as_index()],
        )?;
    }
    Ok(())
}

/// Parse the payload `weekdays` array (Monday-first ints 0=Mon … 6=Sun).
/// Absent / null → empty. An out-of-range or non-integer entry is a shape
/// error for the whole payload.
fn parse_weekdays_field(p: &Value, id: &str) -> Result<Vec<WeekDay>, ImportError> {
    let field = match p.get("weekdays") {
        None | Some(Value::Null) => return Ok(Vec::new()),
        Some(field) => field,
    };
    let arr = field.as_array().ok_or_else(|| {
        ImportError::InvalidPayload(format!("habit {id} weekdays must be an array"))
    })?;
    let mut out = Vec::with_capacity(arr.len());
    for entry in arr {
        let day = entry
            .as_i64()
            .and_then(WeekDay::from_index)
            .ok_or_else(|| {
                ImportError::InvalidPayload(format!(
                    "habit {id} weekdays entries must be integers 0..=6 (Mon-first)"
                ))
            })?;
        out.push(day);
    }
    Ok(out)
}

/// Parse the optional `day_of_month` payload field. Absent / null → `None`;
/// a present value outside `1..=31` is a shape error.
fn parse_day_of_month_field(p: &Value, id: &str) -> Result<Option<i64>, ImportError> {
    match p.get("day_of_month") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => {
            let day = value
                .as_i64()
                .filter(|d| (1..=31).contains(d))
                .ok_or_else(|| {
                    ImportError::InvalidPayload(format!(
                        "habit {id} day_of_month must be an integer between 1 and 31"
                    ))
                })?;
            Ok(Some(day))
        }
    }
}

/// Parse the optional `milestone_target` payload field. Absent / null →
/// `None`; a present value `<= 0` is a shape error (the schema pins the
/// column to `> 0` when set).
fn parse_milestone_target_field(p: &Value, id: &str) -> Result<Option<i64>, ImportError> {
    match p.get("milestone_target") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => {
            let target = value.as_i64().filter(|t| *t > 0).ok_or_else(|| {
                ImportError::InvalidPayload(format!(
                    "habit {id} milestone_target must be an integer greater than 0"
                ))
            })?;
            Ok(Some(target))
        }
    }
}

pub(in crate::import::apply::upserts) fn upsert_habit_completion(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let habit_id = required_string_field(p, "habit_id", "habit_completion payload")?;
    let completed_date = required_string_field(p, "completed_date", "habit_completion payload")?;
    let version = entry.version.as_str();
    let value = required_i64_field(p, "value", "habit_completion payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "habit_completion payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "habit_completion payload")?;
    let note = optional_string_field(p, "note", "habit_completion payload")?;

    match should_replace_versioned_composite(
        conn,
        "habit_completions",
        "habit_id",
        &habit_id,
        "completed_date",
        &completed_date,
        version,
    )? {
        None => {
            conn.execute(
                "INSERT INTO habit_completions (habit_id, completed_date, value, note,
                 created_at, updated_at, version)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                rusqlite::params![
                    habit_id,
                    completed_date,
                    value,
                    note.as_deref(),
                    created_at,
                    updated_at,
                    version,
                ],
            )?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.execute(
                "UPDATE habit_completions SET value=?3, note=?4, created_at=?5,
                 updated_at=?6, version=?7
                 WHERE habit_id=?1 AND completed_date=?2",
                rusqlite::params![
                    habit_id,
                    completed_date,
                    value,
                    note.as_deref(),
                    created_at,
                    updated_at,
                    version,
                ],
            )?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}

pub(in crate::import::apply::upserts) fn upsert_habit_reminder_policy(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "habit_reminder_policy payload")?;
    let version = entry.version.as_str();
    let habit_id = required_string_field(p, "habit_id", "habit_reminder_policy payload")?;
    let reminder_time = required_string_field(p, "reminder_time", "habit_reminder_policy payload")?;
    let created_at =
        required_sync_timestamp_field(p, "created_at", "habit_reminder_policy payload")?;
    let updated_at =
        required_sync_timestamp_field(p, "updated_at", "habit_reminder_policy payload")?;
    let enabled = required_bool_as_i64_field(p, "enabled", "habit_reminder_policy payload")?;
    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "habit_reminder_policies",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql: "INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled,
                 created_at, updated_at, version)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
            update_sql:
                "UPDATE habit_reminder_policies SET habit_id=?2, reminder_time=?3, enabled=?4,
                 created_at=?5, updated_at=?6, version=?7 WHERE id=?1",
        },
        rusqlite::params![
            id,
            habit_id,
            reminder_time,
            enabled,
            created_at,
            updated_at,
            version,
        ],
    )
}
