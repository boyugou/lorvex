use super::*;

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn adjust_habit_completion(habit_id: String, delta: i64) -> Result<HabitSummary, String> {
    // habit ids are UUIDv7 — shape-check before the
    // writer transaction.
    let habit_id = crate::commands::shared::validate_uuid_id(&habit_id, "habit_id")?;
    let conn = get_conn()?;
    let result = with_immediate_transaction(&conn, |conn| {
        let today = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
        let now = crate::commands::sync_timestamp_now();

        let (
            name,
            icon,
            color,
            cue,
            frequency_type_raw,
            per_period_target,
            day_of_month,
            weekdays_json,
            target_count,
        ): HabitRow = conn
            .query_row(
                "SELECT name, icon, color, cue, frequency_type, per_period_target, day_of_month,
                        (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays
                           WHERE habit_id = habits.id ORDER BY weekday)) AS weekdays,
                        target_count
                 FROM habits WHERE id = ?1",
                params![habit_id],
                |row| {
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
                    ))
                },
            )
            .map_err(AppError::from)?;
        let frequency_type = frequency_type_from_row(&frequency_type_raw)?;

        let existing = load_existing_completion_value(
            conn,
            &lorvex_domain::HabitId::from_trusted(habit_id.clone()),
            &today,
        )?;

        let current_value = existing.unwrap_or(0);
        let next_value = if delta == 0 {
            if current_value >= target_count.max(1) {
                0
            } else {
                target_count.max(1)
            }
        } else {
            (current_value + delta).clamp(0, target_count.max(1))
        };
        // keep `value`, `updated_at` and `version` in
        // a single UPDATE so any in-transaction read sees a row whose
        // version matches its value. The previous decrement path
        // updated only `value` + `updated_at` and relied on the
        // follow-up `stamp_entity_version` (run inside the outbox
        // enqueue) to bump `version`. If `stamp_entity_version`'s
        // freshly-generated HLC ever lex-compared lower than the
        // row's existing version (clock-back, debug-induced low HLC,
        // a rare same-physical-ms tiebreak), its LWW-gated UPDATE
        // would no-op and leave the row with new value against a
        // stale version. Doing both column writes in one statement
        // closes that window and matches the increment path's
        // contract.
        if next_value < current_value {
            if next_value > 0 {
                let version = crate::hlc::generate_version_result()?;
                conn.execute(
                    "UPDATE habit_completions
                     SET value = ?3, updated_at = ?4, version = ?5
                     WHERE habit_id = ?1 AND completed_date = ?2",
                    params![habit_id, today, next_value, now, version],
                )
                .map_err(AppError::from)?;
            } else {
                conn.execute(
                    "DELETE FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
                    params![habit_id, today],
                )
                .map_err(AppError::from)?;
            }
        } else if next_value > current_value {
            let version = crate::hlc::generate_version_result()?;
            conn.execute(
                "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?5)
                 ON CONFLICT(habit_id, completed_date) DO UPDATE SET value = ?3, version = excluded.version, updated_at = excluded.updated_at",
                params![habit_id, today, next_value, version, now],
            )
            .map_err(AppError::from)?;
        }
        let completions_today = next_value;

        // Completion value changed: drop the cached best-streak so the
        // next Habits-view open recomputes (issue #2291).
        if next_value != current_value {
            invalidate_best_streak_cache(&lorvex_domain::HabitId::from_trusted(habit_id.clone()));
        }

        // Only enqueue sync when an actual mutation occurred.
        if next_value != current_value {
            let payload = serde_json::json!({
                "habit_id": habit_id,
                "completed_date": today,
                "value": completions_today,
                "source": "manual",
                "created_at": now,
            });
            let entity_id = format!("{habit_id}:{today}");
            let sync_op = if next_value == 0 {
                OP_DELETE
            } else {
                OP_UPSERT
            };
            crate::commands::enqueue_to_outbox_typed(
                conn,
                EDGE_HABIT_COMPLETION,
                &entity_id,
                sync_op,
                &payload,
            )?;
        }

        let streak = compute_current_streak(
            conn,
            &lorvex_domain::HabitId::from_trusted(habit_id.clone()),
            frequency_type.as_wire_str(),
            target_count,
            &today,
        )?;

        Ok(HabitSummary {
            id: habit_id,
            name,
            icon,
            color,
            cue,
            frequency_type,
            weekdays: parse_weekdays_json(&weekdays_json),
            per_period_target,
            day_of_month,
            target_count,
            progress_kind: progress_kind_for(target_count),
            completions_today,
            current_streak: streak,
        })
    })?;

    event_bus::emit_data_changed(event_bus::Entity::Habit);
    Ok(result)
}
