use super::*;

/// Scan window (in days) for completion rows feeding
/// `current_streak`, `values_30d`, `completions_last_30`,
/// `completion_rate_30d`, and `recent_completion_dates`. Bounding the
/// scan to a year keeps each Habits-view render O(active-window)
/// instead of O(total history), while remaining generous enough that
/// realistic streaks plus the 30/90-day rolling stats are always
/// covered. Current-streak semantics cap at this window: a user with
/// an unbroken daily streak longer than `STREAK_WINDOW_DAYS` sees the
/// streak reported as `STREAK_WINDOW_DAYS`. Best-streak keeps
/// "all time" semantics via the cache below.
pub(super) const STREAK_WINDOW_DAYS: i64 = 365;
pub(super) const RECENT_COMPLETIONS_QUERY: &str = "\
    SELECT hc.habit_id, hc.completed_date, hc.value
    FROM habit_completions hc
    JOIN habits h ON h.id = hc.habit_id AND h.archived = 0
    WHERE hc.completed_date > ?1 AND hc.completed_date <= ?2
    ORDER BY hc.habit_id, hc.completed_date ASC";
pub(super) const BEST_STREAK_COMPLETION_DATES_QUERY: &str = "\
    SELECT completed_date FROM habit_completions
    WHERE habit_id = ?1
    ORDER BY completed_date ASC";

/// (current_streak, best_streak, total_completions, completions_last_30, completion_rate_30d, recent_dates)
type HabitStats = (i64, i64, i64, i64, f64, Vec<String>);

/// Return all active habits with rich statistics for the dedicated Habits view.
#[tauri::command]
pub fn get_habits_with_stats() -> Result<Vec<HabitWithStats>, String> {
    let result = (|| -> AppResult<Vec<HabitWithStats>> {
        let conn = get_read_conn()?;
        gather_habits_with_stats(&conn)
    })();

    result.map_err(String::from)
}

/// Core of [`get_habits_with_stats`] — extracted so tests can drive it
/// against an in-memory connection without the global pool.
pub(crate) fn gather_habits_with_stats(
    conn: &rusqlite::Connection,
) -> AppResult<Vec<HabitWithStats>> {
    let today = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let today_date = parse_habit_completion_date(&today)?;

    let mut stmt = conn.prepare_cached(
        "SELECT h.id, h.name, h.icon, h.color, h.cue, h.frequency_type,
                h.per_period_target, h.day_of_month,
                (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays
                   WHERE habit_id = h.id ORDER BY weekday)) AS weekdays,
                h.target_count, COALESCE(hc.value, 0) AS completions_today,
                h.archived, h.created_at, h.updated_at
         FROM habits h
         LEFT JOIN habit_completions hc ON h.id = hc.habit_id AND hc.completed_date = ?1
         WHERE h.archived = 0
         ORDER BY h.created_at ASC",
    )?;

    // Read raw rows first; the typed `HabitFrequencyType` parse is
    // applied outside the rusqlite closure so a future-variant write
    // from a foreign peer surfaces as a structured `AppError::Validation`
    // instead of being squashed into rusqlite's opaque
    // `FromSqlConversionFailure`.
    type RawHabitStatsRow = (
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
        i64,
        String,
        String,
    );
    let raw_rows: Vec<RawHabitStatsRow> = stmt
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
                row.get(11)?,
                row.get(12)?,
                row.get(13)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let habits: Vec<HabitWithStats> = raw_rows
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
                archived,
                created_at,
                updated_at,
            )| {
                Ok(HabitWithStats {
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
                    archived: archived != 0,
                    created_at,
                    updated_at,
                    current_streak: 0,
                    best_streak: 0,
                    total_completions: 0,
                    completions_last_30: 0,
                    completion_rate_30d: 0.0,
                    recent_completion_dates: Vec::new(),
                })
            },
        )
        .collect::<AppResult<Vec<_>>>()?;

    if habits.is_empty() {
        return Ok(habits);
    }

    // Per-habit cadence metadata reused by the best-streak and
    // expected-completions passes: the typed cadence (built from the
    // typed columns + weekday set), the bare rhythm tag (for the
    // wire-str streak helpers), and the per-day target.
    struct HabitMeta {
        cadence: lorvex_domain::HabitCadence,
        frequency_type: lorvex_domain::HabitFrequencyType,
        target: i64,
    }
    let habit_meta: HashMap<String, HabitMeta> = habits
        .iter()
        .map(|h| {
            let cadence = cadence_from_columns(
                h.frequency_type.as_wire_str(),
                &h.weekdays,
                h.per_period_target,
                h.day_of_month,
            )?;
            Ok((
                h.id.clone(),
                HabitMeta {
                    cadence,
                    frequency_type: h.frequency_type,
                    target: h.target_count,
                },
            ))
        })
        .collect::<AppResult<HashMap<_, _>>>()?;

    // Query 1 — SQL aggregate across every active habit's completions.
    // `total_completions = SUM(value)` is done by SQLite so we never
    // materialize per-row history in Rust. Returns one row per habit
    // that has at least one completion — O(habits) rows regardless of
    // history depth.
    let mut totals_stmt = conn.prepare_cached(
        "SELECT hc.habit_id, COALESCE(SUM(hc.value), 0) AS total_value
         FROM habit_completions hc
         JOIN habits h ON h.id = hc.habit_id AND h.archived = 0
         GROUP BY hc.habit_id",
    )?;
    let mut total_values: HashMap<String, i64> = HashMap::new();
    for row in totals_stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
    })? {
        let (habit_id, total) = row?;
        total_values.insert(habit_id, total);
    }

    // Query 2 — bounded window used for current_streak, recent dates,
    // and 30d aggregates. `PRIMARY KEY (habit_id, completed_date)`
    // lets SQLite serve this as an index range scan.
    let window_cutoff = today_date - chrono::Duration::days(STREAK_WINDOW_DAYS);
    let window_cutoff_str = window_cutoff.format("%Y-%m-%d").to_string();
    let mut recent_stmt = conn.prepare_cached(RECENT_COMPLETIONS_QUERY)?;

    let recent_rows: Vec<(String, String, i64)> = recent_stmt
        .query_map(params![window_cutoff_str, today], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let cutoff_30 = today_date - chrono::Duration::days(30);
    let cutoff_90 = today_date - chrono::Duration::days(90);

    let mut habit_window_dates: HashMap<String, Vec<NaiveDate>> = HashMap::new();
    let mut values_30d: HashMap<String, i64> = HashMap::new();
    for (habit_id, date_str, value) in &recent_rows {
        let parsed = parse_habit_completion_date(date_str)?;
        habit_window_dates
            .entry(habit_id.clone())
            .or_default()
            .push(parsed);
        if parsed > cutoff_30 {
            *values_30d.entry(habit_id.clone()).or_default() += *value;
        }
    }

    // Resolve all best_streak values via the cache. Misses trigger a
    // per-habit full-history scan (one query each), after which the
    // value is valid for BEST_STREAK_CACHE_TTL. This keeps the common
    // path O(habits) while preserving all-time semantics.
    let now = Instant::now();
    let mut best_streaks: HashMap<String, i64> = HashMap::new();
    let mut cache_misses: Vec<String> = Vec::new();
    {
        // Recover from poisoning: the cache is a pure memoization
        // table — its invariants (HashMap mapping habit_id to
        // (best_streak, computed_at)) can't be corrupted by a panic
        // in a holder. Worst case after recovery is one stale entry
        // that the TTL check below still rejects.
        //
        // the read and the
        // write site (further down) both recover identically. The
        // TTL gate is the canonical correctness fence — even a
        // sibling thread's stale insert stays bounded by
        // `BEST_STREAK_CACHE_TTL`, so the recovered cache cannot
        // serve a "permanently wrong" answer.
        let guard = best_streak_cache()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for habit in &habits {
            match guard.get(&habit.id) {
                Some((value, computed_at))
                    if now.duration_since(*computed_at) < BEST_STREAK_CACHE_TTL =>
                {
                    best_streaks.insert(habit.id.clone(), *value);
                }
                _ => cache_misses.push(habit.id.clone()),
            }
        }
    }

    if !cache_misses.is_empty() {
        let mut per_habit_stmt = conn.prepare_cached(BEST_STREAK_COMPLETION_DATES_QUERY)?;
        let mut updates: Vec<(String, i64)> = Vec::with_capacity(cache_misses.len());
        for habit_id in &cache_misses {
            record_best_streak_full_history_scan_for_test();
            let dates: Vec<NaiveDate> = per_habit_stmt
                .query_map(params![habit_id], |row| row.get::<_, String>(0))?
                .collect::<Result<Vec<_>, _>>()?
                .into_iter()
                .map(|s| parse_habit_completion_date(&s))
                .collect::<Result<Vec<_>, _>>()?;
            let (freq, target) = habit_meta
                .get(habit_id)
                .map_or((lorvex_domain::HabitFrequencyType::Daily, 1_i64), |m| {
                    (m.frequency_type, m.target)
                });
            let best = compute_best_streak(&dates, freq.as_wire_str(), target);
            updates.push((habit_id.clone(), best));
        }
        let mut guard = best_streak_cache()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for (habit_id, best) in updates {
            guard.insert(habit_id.clone(), (best, now));
            best_streaks.insert(habit_id, best);
        }
    }

    let mut stats: HashMap<String, HabitStats> = HashMap::new();
    for habit in &habits {
        let habit_id = &habit.id;
        let window_dates = habit_window_dates.get(habit_id);
        let empty: Vec<NaiveDate> = Vec::new();
        let dates_asc = window_dates.unwrap_or(&empty);
        let total = *total_values.get(habit_id).unwrap_or(&0);
        let last30 = *values_30d.get(habit_id).unwrap_or(&0);
        let recent: Vec<String> = dates_asc
            .iter()
            .filter(|&&d| d > cutoff_90)
            .map(|d| d.format("%Y-%m-%d").to_string())
            .collect();

        let meta = habit_meta.get(habit_id);
        let freq = meta.map_or(lorvex_domain::HabitFrequencyType::Daily, |m| {
            m.frequency_type
        });
        let target = meta.map_or(1_i64, |m| m.target);

        let best = best_streaks.get(habit_id).copied().unwrap_or(0);
        let dates_desc: Vec<NaiveDate> = dates_asc.iter().copied().rev().collect();
        let current =
            compute_streak_for_frequency(&dates_desc, today_date, freq.as_wire_str(), target);
        let default_cadence = lorvex_domain::HabitCadence::Daily;
        let cadence = meta.map_or(&default_cadence, |m| &m.cadence);
        let expected_30 = lorvex_domain::habit_expected_completions_in_days(cadence, target, 30);

        let completion_rate_30d = if expected_30 > 0.0 {
            (last30 as f64 / expected_30).clamp(0.0, 1.0)
        } else {
            0.0
        };

        stats.insert(
            habit_id.clone(),
            (current, best, total, last30, completion_rate_30d, recent),
        );
    }

    let results = habits
        .into_iter()
        .map(|mut h| {
            if let Some((current, best, total, last30, completion_rate_30d, recent)) =
                stats.remove(&h.id)
            {
                h.current_streak = current;
                h.best_streak = best;
                h.total_completions = total;
                h.completions_last_30 = last30;
                h.completion_rate_30d = completion_rate_30d;
                h.recent_completion_dates = recent;
            }
            h
        })
        .collect();

    Ok(results)
}
