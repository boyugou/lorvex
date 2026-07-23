use super::*;

/// Batch-compute current streaks for all active habits in a single SQL query.
pub(super) fn compute_all_streaks(
    conn: &rusqlite::Connection,
    today: &str,
) -> AppResult<HashMap<String, i64>> {
    let mut habit_meta_stmt = conn
        .prepare_cached("SELECT id, frequency_type, target_count FROM habits WHERE archived = 0")
        .map_err(AppError::from)?;
    let habit_meta: HashMap<String, (String, i64)> = habit_meta_stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                (row.get::<_, String>(1)?, row.get::<_, i64>(2)?),
            ))
        })
        .map_err(AppError::from)?
        .collect::<Result<HashMap<_, _>, _>>()
        .map_err(AppError::from)?;

    let mut stmt = conn
        .prepare_cached(
            "SELECT hc.habit_id, hc.completed_date
             FROM habit_completions hc
             JOIN habits h ON h.id = hc.habit_id AND h.archived = 0
             ORDER BY hc.habit_id, hc.completed_date DESC",
        )
        .map_err(AppError::from)?;

    let rows: Vec<(String, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?;

    let today_date = parse_habit_completion_date(today)?;

    let mut streaks = HashMap::new();
    let mut current_habit: Option<String> = None;
    let mut dates: Vec<NaiveDate> = Vec::new();

    for (habit_id, date_str) in &rows {
        if current_habit.as_ref() != Some(habit_id) {
            if let Some(ref hid) = current_habit {
                let (freq, target) = habit_meta
                    .get(hid)
                    .map_or(("daily", 1), |(f, t)| (f.as_str(), *t));
                streaks.insert(
                    hid.clone(),
                    compute_streak_for_frequency(&dates, today_date, freq, target),
                );
            }
            current_habit = Some(habit_id.clone());
            dates.clear();
        }
        let completion_date = parse_habit_completion_date(date_str)?;
        if completion_date <= today_date {
            dates.push(completion_date);
        }
    }
    if let Some(ref hid) = current_habit {
        let (freq, target) = habit_meta
            .get(hid)
            .map_or(("daily", 1), |(f, t)| (f.as_str(), *t));
        streaks.insert(
            hid.clone(),
            compute_streak_for_frequency(&dates, today_date, freq, target),
        );
    }

    Ok(streaks)
}

pub(super) fn compute_current_streak(
    conn: &rusqlite::Connection,
    habit_id: &lorvex_domain::HabitId,
    frequency_type: &str,
    target_count: i64,
    today: &str,
) -> AppResult<i64> {
    let mut stmt = conn
        .prepare_cached(
            "SELECT completed_date FROM habit_completions
             WHERE habit_id = ?1
             ORDER BY completed_date DESC",
        )
        .map_err(AppError::from)?;
    let dates: Vec<NaiveDate> = stmt
        .query_map(params![habit_id.as_str()], |row| row.get::<_, String>(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?
        .into_iter()
        .map(|s| parse_habit_completion_date(&s))
        .collect::<Result<Vec<_>, _>>()?;

    let today_date = parse_habit_completion_date(today)?;
    let dates: Vec<NaiveDate> = dates
        .into_iter()
        .filter(|date| *date <= today_date)
        .collect();
    Ok(compute_streak_for_frequency(
        &dates,
        today_date,
        frequency_type,
        target_count,
    ))
}
