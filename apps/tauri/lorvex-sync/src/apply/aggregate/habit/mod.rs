//! Apply handlers for the `habit` aggregate root.

use rusqlite::{named_params, params, Connection, OptionalExtension};

use lorvex_domain::habits::WeekDay;
use lorvex_domain::ids::HabitId;

use super::super::LwwTieBreak;
use super::helpers::{
    optional_bool_as_i64, optional_i64, optional_str, required_i64, required_str,
    tombstone_child_rows, tombstone_composite_edges,
};
use super::ApplyError;

pub(crate) fn apply_habit_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    // handler doesn't currently consume the apply
    // timestamp, but every aggregate-upsert signature carries it for
    // uniform dispatch + future timestamp-using fields. `_apply_ts`
    // keeps the parameter shape without the unused-variable warning.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: thread the typed `HabitId` through the
    // apply body. The dispatch table holds fn-pointer types shared
    // across every aggregate handler so the public signature stays
    // `&str`, but the function body operates on the typed id from
    // the very first line — SQL bind sites and error formatting
    // all flow through the typed id (zero-copy via the rusqlite
    // ToSql impl on the newtype).
    let habit_id = HabitId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let name = required_str(&val, "name", "habit")?;
    let icon = optional_str(&val, "icon", "habit")?;
    let color = optional_str(&val, "color", "habit")?;
    let cue = optional_str(&val, "cue", "habit")?;
    let frequency_type = required_str(&val, "frequency_type", "habit")?;
    let target_count = required_i64(&val, "target_count", "habit")?;
    // Optional user-set milestone goal (nullable scalar, independent of
    // cadence). A peer that predates the column omits it → NULL. Bound
    // directly from the payload, not through the create-draft validator
    // (which does not carry it), mirroring `archived`.
    let milestone_target = optional_milestone_target(&val, habit_id.as_str())?;

    // Typed cadence fields. A peer that predates a column omits it; the
    // schema DEFAULTs (per_period_target 1, day_of_month NULL) apply.
    // `weekdays` is an array of Monday-first ints (0=Mon … 6=Sun) carried
    // inside the habit payload so the applier can rebuild the
    // `habit_weekdays` child.
    let weekdays = parse_weekdays(&val, habit_id.as_str())?;
    let per_period_target = optional_i64(&val, "per_period_target", "habit")?.unwrap_or(1);
    let day_of_month = optional_day_of_month(&val, habit_id.as_str())?;

    // Bridge the typed cadence fields into the typed primitive at the
    // apply seam, run the create-draft validator, then re-render the
    // validated cadence back to its typed columns for the SQL bind (never
    // passing the raw payload values straight through).
    let frequency = lorvex_domain::habits::HabitCadence::from_fields(
        &lorvex_domain::habits::HabitFrequencyFields {
            frequency_type: frequency_type.to_string(),
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
        ApplyError::InvalidPayload(format!(
            "habit {} failed cadence parse: {error}",
            habit_id.as_str()
        ))
    })?;
    let validated = lorvex_domain::habits::validate_habit_create_draft(
        lorvex_domain::habits::HabitCreateDraft {
            name,
            icon,
            color,
            cue,
            frequency: Some(frequency),
            target_count: Some(target_count),
        },
    )
    .map_err(|error| {
        ApplyError::InvalidPayload(format!(
            "habit {} failed validation: {error}",
            habit_id.as_str()
        ))
    })?;
    // Render the validated cadence back to its typed columns for the SQL
    // bind list.
    let cadence_fields = validated.frequency().to_fields();
    // `archived` has SQL DEFAULT 0 and was added after the
    // original habit shape. An older peer that lacks the field is
    // treated as not-archived (the SQL default).
    let archived = optional_bool_as_i64(&val, "archived", "habit")?.unwrap_or(0);
    let position = match optional_i64(&val, "position", "habit")? {
        Some(position) => position,
        None => conn
            .prepare_cached("SELECT position FROM habits WHERE id = ?1")?
            .query_row([&habit_id], |row| row.get(0))
            .optional()?
            .unwrap_or(0),
    };
    let created_at = required_str(&val, "created_at", "habit")?;
    let updated_at = required_str(&val, "updated_at", "habit")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "habits",
        columns: &[
            "id",
            "name",
            "icon",
            "color",
            "cue",
            "frequency_type",
            "per_period_target",
            "day_of_month",
            "target_count",
            "milestone_target",
            "archived",
            "position",
            "lookup_key",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        // bind the typed `HabitId` directly via the rusqlite ToSql
        // impl on the newtype — no `.as_str()` allocation, and the
        // typed id is the only path that reaches the SQL layer.
        ":id": &habit_id,
        ":name": validated.name(),
        ":icon": validated.icon(),
        ":color": validated.color(),
        ":cue": validated.cue(),
        ":frequency_type": &cadence_fields.frequency_type,
        ":per_period_target": cadence_fields.per_period_target,
        ":day_of_month": cadence_fields.day_of_month,
        ":target_count": validated.target_count(),
        ":milestone_target": milestone_target,
        ":archived": archived,
        ":position": position,
        ":lookup_key": validated.lookup_key(),
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;

    // Rebuild the `habit_weekdays` materialization from the validated
    // cadence's weekday set, but only when the freshly-upserted row is the
    // live survivor. A version-rejected upsert (`changes() == 0`) must not
    // overwrite the current (newer) weekdays with a stale payload. Mirrors
    // the `calendar_event_attendees` rebuild in the calendar-event applier.
    // The set is empty for every non-weekly cadence and for
    // weekly-every-day, so those cadences clear the child rows.
    if conn.changes() > 0 {
        rebuild_habit_weekdays(
            conn,
            &habit_id,
            cadence_fields.weekdays.as_deref().unwrap_or(&[]),
        )?;
    }
    Ok(())
}

/// Delete-then-insert the `habit_weekdays` rows for one habit from a
/// weekday set. Device-local materialization: the rows carry no version
/// and are never synced independently. An empty set leaves the habit with
/// no weekday rows ("every day" for a weekly cadence).
fn rebuild_habit_weekdays(
    conn: &Connection,
    habit_id: &HabitId,
    weekdays: &[WeekDay],
) -> Result<(), ApplyError> {
    conn.prepare_cached("DELETE FROM habit_weekdays WHERE habit_id = ?1")?
        .execute([habit_id])?;
    let mut insert = conn.prepare_cached(
        "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?1, ?2)",
    )?;
    for day in weekdays {
        insert.execute(params![habit_id, day.as_index()])?;
    }
    Ok(())
}

/// Parse the payload `weekdays` array (Monday-first ints 0=Mon … 6=Sun)
/// into typed [`WeekDay`] values. Absent / null → empty. An out-of-range
/// or non-integer entry is a shape error for the whole envelope.
fn parse_weekdays(val: &serde_json::Value, habit_id: &str) -> Result<Vec<WeekDay>, ApplyError> {
    let field = match val.get("weekdays") {
        None | Some(serde_json::Value::Null) => return Ok(Vec::new()),
        Some(field) => field,
    };
    let arr = field.as_array().ok_or_else(|| {
        ApplyError::InvalidPayload(format!("habit {habit_id} weekdays must be an array"))
    })?;
    let mut out = Vec::with_capacity(arr.len());
    for entry in arr {
        let day = entry
            .as_i64()
            .and_then(WeekDay::from_index)
            .ok_or_else(|| {
                ApplyError::InvalidPayload(format!(
                    "habit {habit_id} weekdays entries must be integers 0..=6 (Mon-first)"
                ))
            })?;
        out.push(day);
    }
    Ok(out)
}

/// Parse the optional `day_of_month` payload field. Absent / null → `None`;
/// a present value outside `1..=31` is a shape error for the envelope.
fn optional_day_of_month(
    val: &serde_json::Value,
    habit_id: &str,
) -> Result<Option<i64>, ApplyError> {
    match optional_i64(val, "day_of_month", "habit")? {
        None => Ok(None),
        Some(day) if (1..=31).contains(&day) => Ok(Some(day)),
        Some(_) => Err(ApplyError::InvalidPayload(format!(
            "habit {habit_id} day_of_month must be between 1 and 31"
        ))),
    }
}

/// Parse the optional `milestone_target` payload field. Absent / null →
/// `None`; a present value `<= 0` is a shape error for the envelope (the
/// schema pins the column to `> 0` when set).
fn optional_milestone_target(
    val: &serde_json::Value,
    habit_id: &str,
) -> Result<Option<i64>, ApplyError> {
    match optional_i64(val, "milestone_target", "habit")? {
        None => Ok(None),
        Some(target) if target > 0 => Ok(Some(target)),
        Some(_) => Err(ApplyError::InvalidPayload(format!(
            "habit {habit_id} milestone_target must be greater than 0"
        ))),
    }
}

/// Returns the shared [`super::LwwGatedDeleteOutcome`] so the
/// in-handler LWW gate's `Reject` arm surfaces as a typed outcome
/// rather than collapsing into `Ok(())`. A silent no-op DELETE that
/// returned `Ok(())` would let the dispatcher report `Applied` and
/// `apply_envelope` mint a tombstone over the surviving local row.
pub(crate) fn apply_habit_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    apply_ts: &str,
) -> Result<super::LwwGatedDeleteOutcome, ApplyError> {
    // Issue #3285 phase 3: parse to the typed `HabitId` once at the
    // handler entry. Every SQL bind, helper call, and cascade
    // composite-key formatter below threads the typed id; the
    // `&str` parameter is preserved only because the dispatch
    // table's fn-pointer type is shared across aggregate handlers.
    let habit_id = HabitId::from_trusted(entity_id.to_string());
    let habit_id_str = habit_id.as_str();
    // route through the shared `gate_then_cascade`
    // helper so the LWW gate fires BEFORE the cascade closure can
    // run. See [`super::task::apply_task_delete`] for the full
    // rationale;
    // applied here (habit_completions / habit_reminder_policies
    // were tombstoned even when a tainted local `version` would
    // make the byte-compare fallback refuse the parent delete).
    super::helpers::gate_then_cascade_into_outcome(
        conn,
        "SELECT version FROM habits WHERE id = ?1",
        "DELETE FROM habits WHERE id = :id",
        habit_id_str,
        version,
        LwwTieBreak::AllowEqual,
        |conn| {
            // habit_completions — composite `{habit_id}:{completed_date}`.
            // include each row's `version` so the
            // cascade tombstone is stamped at
            // `max(parent_version, row_version)`.
            //
            // Borrow `habit_id_str` / `version` / `apply_ts` straight
            // from the surrounding scope (the `FnOnce` closure
            // bound has no `'static` requirement) instead of
            // paying three `to_string()` allocations per
            // envelope.
            tombstone_composite_edges(
                conn,
                "SELECT completed_date, version FROM habit_completions WHERE habit_id = ?1",
                habit_id_str,
                lorvex_domain::naming::EDGE_HABIT_COMPLETION,
                |other| format!("{habit_id_str}:{other}"),
                version,
                apply_ts,
            )?;
            // habit_reminder_policies — single-column child PK.
            tombstone_child_rows(
                conn,
                "SELECT id, version FROM habit_reminder_policies WHERE habit_id = ?1",
                habit_id_str,
                lorvex_domain::naming::ENTITY_HABIT_REMINDER_POLICY,
                version,
                apply_ts,
            )?;
            Ok(())
        },
    )
}

#[cfg(test)]
mod tests;
