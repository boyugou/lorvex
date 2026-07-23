use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde::Serialize;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::render::render_habit_complete_result;

pub(crate) mod effects;
use effects::{
    complete_habit_in_tx, complete_habit_with_conn, create_habit_with_conn,
    delete_habit_reminder_policy_with_conn, delete_habit_with_conn, uncomplete_habit_with_conn,
    update_habit_with_conn, upsert_habit_reminder_policy_with_conn, HabitCompletionRow,
    HabitUpdateFields,
};

pub(crate) fn run_habit_complete(
    habit_id: &str,
    date: Option<&str>,
    note: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let habit_id_typed = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
    let (habit_name, completion) =
        complete_habit_with_conn(&mut conn, &habit_id_typed, date, note)?;
    render_habit_complete_result(
        &db_path,
        habit_id,
        &habit_name,
        &completion.completed_date,
        completion.value,
        completion.note.as_deref(),
        format,
    )
}

#[derive(Debug, Clone, Serialize)]
struct HabitBatchCompleteResult {
    habit_id: String,
    habit_name: String,
    completion: HabitCompletionRow,
}

pub(crate) fn run_habit_batch_complete(
    habit_ids: &[String],
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    // pre-flight every habit_id BEFORE any
    // mutation. The eligibility check loads each row and rejects
    // missing or archived habits. Mirrors MCP's atomic-batch
    // discipline (-H7);
    // successes and failures into the same envelope, defeating
    // the all-or-nothing contract.
    // Resolve every habit's eligibility in one indexed scan rather
    // than one round trip per id. `WHERE id IN (?, ?, …)` reads each
    // id at most once even for the documented batch cap, and the
    // typed `.optional()?` on the per-id loop the previous shape
    // ran silently masked SQLITE_BUSY / SQLITE_CORRUPT as
    // "habit not found", misleading callers into thinking the id
    // was a typo when in fact the DB was contended.
    let mut ineligible: Vec<String> = Vec::new();
    if !habit_ids.is_empty() {
        let placeholders = lorvex_domain::sql_csv_placeholders(habit_ids.len());
        let sql = format!("SELECT id, archived FROM habits WHERE id IN ({placeholders})");
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(habit_ids.iter()), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })?;
        let mut by_id: std::collections::HashMap<String, i64> =
            std::collections::HashMap::with_capacity(habit_ids.len());
        for row in rows {
            let (id, archived) = row?;
            by_id.insert(id, archived);
        }
        for habit_id in habit_ids {
            let reason = match by_id.get(habit_id) {
                None => Some("habit not found".to_string()),
                Some(&archived) if archived != 0 => {
                    Some("habit is archived; unarchive first".to_string())
                }
                Some(_) => None,
            };
            if let Some(reason) = reason {
                ineligible.push(format!("{habit_id}: {reason}"));
            }
        }
    }
    if !ineligible.is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "batch complete rejects partial application: {} of {} habit(s) are not eligible: [{}]. \
             Re-call with the eligible subset.",
            ineligible.len(),
            habit_ids.len(),
            ineligible.join(", "),
        )));
    }

    // #3033-H2: drive every per-id completion through ONE outer
    // BEGIN IMMEDIATE transaction. The pre-flight gate already
    // proved every id is eligible, so the only mid-loop failures
    // are races (HLC contention, archive between pre-flight and
    // commit, disk-full) — those are exactly the cases that must
    // abort the entire batch atomically rather than committing
    // partial completions.
    // committed its own transaction so a mid-loop failure left
    // every prior id permanently completed despite the pre-flight's
    // "all-or-nothing" promise.
    let mut results = Vec::with_capacity(habit_ids.len());
    lorvex_store::transaction::with_immediate_transaction::<_, crate::error::CliError>(
        &conn,
        |conn| {
            for habit_id in habit_ids {
                let habit_id_typed = lorvex_domain::HabitId::from_trusted(habit_id.clone());
                let (habit_name, completion) =
                    complete_habit_in_tx(conn, &habit_id_typed, date, None)?;
                results.push(HabitBatchCompleteResult {
                    habit_id: habit_id.clone(),
                    habit_name,
                    completion,
                });
            }
            lorvex_runtime::bump_local_change_seq(conn)?;
            Ok(())
        },
    )?;

    let count = results.len();

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Batch completed Lorvex habits\nDB: {}\nCount: {}\nCompleted: {}\n",
                db_path.display(),
                count,
                count,
            );
            for result in &results {
                let _ = writeln!(
                    output,
                    "- {}: completed {} on {} (value {})",
                    result.habit_id,
                    result.habit_name,
                    result.completion.completed_date,
                    result.completion.value,
                );
            }
            Ok(output)
        }
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "habit.batch_complete",
            &db_path,
            json!({
                "results": results,
                "count": count,
            }),
        ),
    }
}

pub(crate) fn run_habit_uncomplete(
    habit_id: &str,
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
    let result = uncomplete_habit_with_conn(&mut conn, &habit_id, date)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Removed Lorvex habit completion\nDB: {}\nID: {}\nName: {}\nDate: {}\nPrevious value: {}\n",
            db_path.display(),
            result.habit_id,
            result.habit_name,
            result.completed_date,
            result.previous.value,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("habit.uncomplete", &db_path, json!({ "result": result }))
        }
    }
}

/// Assemble the typed [`HabitCadence`] from the CLI's cadence flags.
/// Returns `None` when no `--frequency-type` was given (leave cadence
/// alone on update; default to daily on create). Rejects an unknown
/// weekday token or a cadence-detail combination the domain refuses.
fn build_habit_cadence(
    frequency_type: Option<&str>,
    weekdays: &[String],
    per_period_target: Option<i64>,
    day_of_month: Option<i64>,
) -> Result<Option<lorvex_domain::habits::HabitCadence>, crate::error::CliError> {
    use lorvex_domain::habits::{HabitCadence, HabitFrequencyFields, WeekDay};
    let Some(frequency_type) = frequency_type else {
        return Ok(None);
    };
    let weekdays: Option<Vec<WeekDay>> = if weekdays.is_empty() {
        None
    } else {
        Some(
            weekdays
                .iter()
                .map(|day| {
                    WeekDay::parse(day).ok_or_else(|| {
                        crate::error::CliError::Validation(format!(
                            "invalid weekday '{day}'; expected mon/tue/wed/thu/fri/sat/sun"
                        ))
                    })
                })
                .collect::<Result<_, _>>()?,
        )
    };
    let fields = HabitFrequencyFields {
        frequency_type: frequency_type.to_string(),
        weekdays,
        per_period_target: per_period_target.unwrap_or(1),
        day_of_month,
    };
    Ok(Some(HabitCadence::from_fields(&fields)?))
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn run_habit_create(
    name: &str,
    icon: Option<&str>,
    color: Option<&str>,
    cue: Option<&str>,
    frequency_type: Option<&str>,
    weekdays: &[String],
    per_period_target: Option<i64>,
    day_of_month: Option<i64>,
    target_count: Option<i64>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let frequency = build_habit_cadence(frequency_type, weekdays, per_period_target, day_of_month)?;
    let habit = create_habit_with_conn(&mut conn, name, icon, color, cue, frequency, target_count)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Created Lorvex habit\nDB: {}\nID: {}\nName: {}\nFrequency: {}\nTarget count: {}\n",
            db_path.display(),
            habit.id,
            habit.name,
            habit.frequency_type,
            habit.target_count,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("habit.create", &db_path, json!({ "habit": habit }))
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn run_habit_update(
    habit_id: &str,
    name: Option<&str>,
    icon: lorvex_domain::Patch<&str>,
    color: lorvex_domain::Patch<&str>,
    cue: lorvex_domain::Patch<&str>,
    frequency_type: Option<&str>,
    weekdays: &[String],
    per_period_target: Option<i64>,
    day_of_month: Option<i64>,
    target_count: Option<i64>,
    archived: Option<bool>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let frequency = build_habit_cadence(frequency_type, weekdays, per_period_target, day_of_month)?;
    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
    let habit = update_habit_with_conn(
        &mut conn,
        &habit_id,
        HabitUpdateFields {
            name,
            icon,
            color,
            cue,
            frequency,
            target_count,
            archived,
        },
    )?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Updated Lorvex habit\nDB: {}\nID: {}\nName: {}\nFrequency: {}\nTarget count: {}\nArchived: {}\n",
            db_path.display(),
            habit.id,
            habit.name,
            habit.frequency_type,
            habit.target_count,
            habit.archived,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("habit.update", &db_path, json!({ "habit": habit }))
        }
    }
}

pub(crate) fn run_habit_delete(
    habit_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
    let deleted = delete_habit_with_conn(&mut conn, &habit_id)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Deleted Lorvex habit\nDB: {}\nID: {}\nName: {}\nCompletions destroyed: {}\nReminder policies destroyed: {}\n",
            db_path.display(),
            deleted.id,
            deleted.name,
            deleted.completions_destroyed,
            deleted.reminder_policies_destroyed,
        )),
        // canonical CLI delete envelope shape.
        OutputFormat::Json => {
            render_mutation_envelope("habit.delete", &db_path, json!({ "deleted": deleted }))
        }
    }
}

pub(crate) fn run_habit_reminder_upsert(
    policy_id: Option<&str>,
    habit_id: &str,
    reminder_time: &str,
    enabled: bool,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let policy_id_typed =
        policy_id.map(|s| lorvex_domain::HabitReminderPolicyId::from_trusted(s.to_string()));
    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
    let policy = upsert_habit_reminder_policy_with_conn(
        &mut conn,
        policy_id_typed.as_ref(),
        &habit_id,
        reminder_time,
        enabled,
    )?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Set Lorvex habit reminder policy\nDB: {}\nID: {}\nHabit: {}\nTime: {}\nEnabled: {}\n",
            db_path.display(),
            policy.id,
            policy.habit_name,
            policy.reminder_time,
            policy.enabled,
        )),
        // canonical mutation envelope. Verb chosen so
        // the create-or-update upsert sits next to the matching
        // `habit.reminder.delete` below.
        OutputFormat::Json => render_mutation_envelope(
            "habit.reminder.upsert",
            &db_path,
            json!({ "habit_reminder_policy": policy }),
        ),
    }
}

pub(crate) fn run_habit_reminder_delete(
    policy_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let policy_id = lorvex_domain::HabitReminderPolicyId::from_trusted(policy_id.to_string());
    let result = delete_habit_reminder_policy_with_conn(&mut conn, &policy_id)?;
    match format {
        OutputFormat::Text => {
            let status = if result.deleted {
                "deleted"
            } else {
                "not found"
            };
            Ok(format!(
                "Deleted Lorvex habit reminder policy\nDB: {}\nID: {}\nStatus: {}\n",
                db_path.display(),
                result.id,
                status,
            ))
        }
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "habit.reminder.delete",
            &db_path,
            json!({ "habit_reminder_policy_delete": result }),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_runtime::with_db_path_env_for_test;
    use tempfile::tempdir;

    #[test]
    fn habit_batch_complete_json_omits_legacy_completed_count() {
        let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("habits.sqlite");
        let mut conn = open_db_at_path(&db_path).expect("open temp db");
        let habit_a = create_habit_with_conn(
            &mut conn,
            "Hydrate",
            None,
            None,
            None,
            Some(lorvex_domain::habits::HabitCadence::Daily),
            Some(1),
        )
        .expect("create first habit");
        let habit_b = create_habit_with_conn(
            &mut conn,
            "Read",
            None,
            None,
            None,
            Some(lorvex_domain::habits::HabitCadence::Daily),
            Some(1),
        )
        .expect("create second habit");
        drop(conn);

        let path_string = db_path.display().to_string();
        with_db_path_env_for_test(Some(path_string.as_str()), || {
            let output = run_habit_batch_complete(
                &[habit_a.id.clone(), habit_b.id.clone()],
                Some("2026-04-24"),
                OutputFormat::Json,
            )
            .expect("batch complete habits");
            let value: serde_json::Value =
                serde_json::from_str(&output).expect("parse batch complete output");

            assert_eq!(value["count"], 2);
            assert!(
                value.get("completed_count").is_none(),
                "habit.batch_complete JSON must expose canonical count only: {output}"
            );
        });
    }
}
