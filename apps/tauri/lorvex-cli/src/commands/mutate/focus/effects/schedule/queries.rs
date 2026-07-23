use lorvex_domain::CalendarAiAccessMode;
use rusqlite::{Connection, OptionalExtension};

use crate::models::{FocusScheduleBlockView, FocusScheduleView};

use crate::commands::shared::effects as shared;

pub(crate) fn get_focus_schedule_with_conn(
    conn: &Connection,
    date: Option<&str>,
) -> Result<Option<FocusScheduleView>, crate::error::CliError> {
    let schedule_date = shared::resolve_date_or_today(conn, date)?;
    load_focus_schedule_view_for_date(conn, &schedule_date)
}

pub(super) fn read_calendar_ai_access_mode(
    conn: &Connection,
) -> Result<CalendarAiAccessMode, crate::error::CliError> {
    lorvex_store::device_state::read_calendar_ai_access_mode(conn).map_err(|error| match error {
        lorvex_store::device_state::DeviceStateReadError::Sql(error) => {
            crate::error::CliError::Sql(Box::new(error))
        }
        lorvex_store::device_state::DeviceStateReadError::Value(error) => {
            crate::error::CliError::Validation(error.to_string())
        }
    })
}

pub(super) fn load_focus_schedule_view_for_date(
    conn: &Connection,
    date: &str,
) -> Result<Option<FocusScheduleView>, crate::error::CliError> {
    type ScheduleRow = (
        String,
        Option<String>,
        Option<String>,
        String,
        String,
        String,
    );
    let row: Option<ScheduleRow> = conn
        .query_row(
            "SELECT date, rationale, timezone, version, created_at, updated_at \
             FROM focus_schedule WHERE date = ?1",
            [date],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                ))
            },
        )
        .optional()?;

    let Some((date, rationale, timezone, version, created_at, updated_at)) = row else {
        return Ok(None);
    };

    let blocks = load_focus_schedule_blocks(conn, &date)?;
    Ok(Some(FocusScheduleView {
        date,
        rationale,
        timezone,
        version,
        created_at,
        updated_at,
        blocks,
        task_ids_applied: None,
    }))
}

fn load_focus_schedule_blocks(
    conn: &Connection,
    date: &str,
) -> Result<Vec<FocusScheduleBlockView>, crate::error::CliError> {
    let mut stmt = conn.prepare(
        "SELECT block_type, start_time, end_time, task_id, event_id, title \
         FROM focus_schedule_blocks WHERE schedule_date = ?1 ORDER BY position ASC",
    )?;
    let rows = stmt
        .query_map([date], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    rows.into_iter()
        .enumerate()
        .map(
            |(index, (block_type, start_minutes, end_minutes, task_id, event_id, title))| {
                let start_time =
                    lorvex_domain::format_minutes_hhmm(start_minutes).ok_or_else(|| {
                        crate::error::CliError::Validation(format!(
                            "focus schedule block {index} has invalid start_time minutes: {start_minutes}"
                        ))
                    })?;
                let end_time = lorvex_domain::format_minutes_hhmm(end_minutes).ok_or_else(|| {
                    crate::error::CliError::Validation(format!(
                        "focus schedule block {index} has invalid end_time minutes: {end_minutes}"
                    ))
                })?;
                Ok(FocusScheduleBlockView {
                    block_type,
                    start_time,
                    end_time,
                    task_id,
                    event_id,
                    title,
                })
            },
        )
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup() -> Connection {
        lorvex_store::open_db_in_memory().expect("open in-memory db")
    }

    #[test]
    fn read_calendar_ai_access_mode_accepts_full_details() {
        let conn = setup();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            (
                lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                "\"full_details\"",
            ),
        )
        .expect("seed full-details access mode");

        let mode = read_calendar_ai_access_mode(&conn).expect("read access mode");

        assert_eq!(mode, CalendarAiAccessMode::FullDetails);
    }

    #[test]
    fn read_calendar_ai_access_mode_rejects_legacy_allow_deny_values() {
        for value in ["allow", "deny"] {
            let conn = setup();
            conn.execute(
                "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
                (
                    lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                    serde_json::to_string(value).expect("serialize legacy value"),
                ),
            )
            .expect("seed legacy access mode");

            let error = read_calendar_ai_access_mode(&conn)
                .expect_err("legacy access mode should be rejected")
                .to_string();

            assert!(error.contains(value), "unexpected error: {error}");
        }
    }
}
