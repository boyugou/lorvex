use super::*;

/// Get today's habits with their completion status — designed for the Today view.
#[tauri::command]
pub fn get_todays_habits() -> Result<Vec<HabitSummary>, String> {
    let result = (|| -> AppResult<Vec<HabitSummary>> {
        let conn = get_read_conn()?;
        let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)?;

        let mut stmt = conn.prepare_cached(
            "SELECT h.id, h.name, h.icon, h.color, h.cue, h.frequency_type,
                    h.per_period_target, h.day_of_month,
                    (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays
                       WHERE habit_id = h.id ORDER BY weekday)) AS weekdays,
                    h.target_count, COALESCE(hc.value, 0) as completions_today
             FROM habits h
             LEFT JOIN habit_completions hc ON h.id = hc.habit_id AND hc.completed_date = ?1
             WHERE h.archived = 0
             ORDER BY h.created_at ASC",
        )?;

        // Read the raw row first; the typed `HabitFrequencyType` parse
        // happens outside the rusqlite closure so the schema-CHECK
        // violation surface (foreign peer wrote a future variant) flows
        // back as an `AppError::Validation` instead of being squashed
        // into an opaque `rusqlite::Error::FromSqlConversionFailure`.
        type RawHabitRow = (
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
            String,
            i64,
            Option<i64>,
            String,
            i64,
            i64,
        );
        let raw_rows: Vec<RawHabitRow> = stmt
            .query_map(params![today], |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;

        let habits: Vec<HabitSummary> = raw_rows
            .into_iter()
            .map(
                |(
                    id,
                    name,
                    icon,
                    color,
                    cue,
                    freq_type_raw,
                    per_period_target,
                    day_of_month,
                    weekdays_json,
                    target_count,
                    completions_today,
                )| {
                    Ok(HabitSummary {
                        id,
                        name,
                        icon,
                        color,
                        cue,
                        frequency_type: frequency_type_from_row(&freq_type_raw)?,
                        weekdays: parse_weekdays_json(&weekdays_json),
                        per_period_target,
                        day_of_month,
                        target_count,
                        progress_kind: progress_kind_for(target_count),
                        completions_today,
                        current_streak: 0,
                    })
                },
            )
            .collect::<AppResult<Vec<_>>>()?;

        let streaks = compute_all_streaks(&conn, &today)?;

        let results = habits
            .into_iter()
            .map(|mut h| {
                h.current_streak = streaks.get(&h.id).copied().unwrap_or(0);
                h
            })
            .collect();
        Ok(results)
    })();

    result.map_err(String::from)
}
