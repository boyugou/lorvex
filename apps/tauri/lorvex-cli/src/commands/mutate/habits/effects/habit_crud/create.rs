//! `habits create` — insert a new habit row and emit the upsert envelope.

use lorvex_domain::habits::{HabitCadence, HabitCreateDraft, WeekDay};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_HABIT;
use lorvex_runtime::get_or_create_device_id;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::super::{
    active_habit_lookup_key_exists, load_habit_row, rebuild_habit_weekdays, HabitRow,
};
use crate::commands::shared::execute_cli_entity_mutation_map_store_error;
use crate::hlc_guard::lock_shared;

struct CreateCliHabitMutation {
    id: String,
    name: String,
    icon: Option<String>,
    color: Option<String>,
    cue: Option<String>,
    frequency_type: String,
    per_period_target: i64,
    day_of_month: Option<i64>,
    weekdays: Vec<WeekDay>,
    target_count: i64,
    lookup_key: String,
    now: String,
}

impl Mutation for CreateCliHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        conn.execute(
            "INSERT INTO habits (
                id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
                target_count, archived, created_at, updated_at, lookup_key, version
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, ?10, ?10, ?11, ?12)",
            rusqlite::params![
                &self.id,
                &self.name,
                self.icon.as_deref(),
                self.color.as_deref(),
                self.cue.as_deref(),
                &self.frequency_type,
                self.per_period_target,
                self.day_of_month,
                self.target_count,
                &self.now,
                &self.lookup_key,
                version
            ],
        )?;
        // Materialize the weekly weekday set into the `habit_weekdays`
        // child (empty for every non-weekly cadence / weekly-every-day).
        rebuild_habit_weekdays(conn, &self.id, &self.weekdays)?;
        let habit_id = lorvex_domain::HabitId::from_trusted(self.id.clone());
        let after = lorvex_store::payload_loaders::load_habit_sync_payload(conn, &habit_id)?
            .ok_or_else(|| StoreError::NotFound {
                entity: ENTITY_HABIT,
                id: self.id.clone(),
            })?;
        Ok(MutationOutput::new(
            after,
            format!("Created habit '{}'", self.name),
        ))
    }
}

pub(crate) fn create_habit_with_conn(
    conn: &mut Connection,
    name: &str,
    icon: Option<&str>,
    color: Option<&str>,
    cue: Option<&str>,
    frequency: Option<HabitCadence>,
    target_count: Option<i64>,
) -> Result<HabitRow, crate::error::CliError> {
    let validated = lorvex_domain::habits::validate_habit_create_draft(HabitCreateDraft {
        name,
        icon,
        color,
        cue,
        frequency,
        target_count,
    })?;
    // Render the validated cadence to its typed columns + weekday set.
    let cadence_fields = validated.frequency().to_fields();

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    if active_habit_lookup_key_exists(&tx, validated.lookup_key(), None)? {
        return Err(crate::error::CliError::Conflict(format!(
            "a habit named '{}' already exists",
            validated.name()
        )));
    }

    let habit_id = lorvex_domain::new_entity_id_string();
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = CreateCliHabitMutation {
        id: habit_id.clone(),
        name: validated.name().to_string(),
        icon: validated.icon().map(str::to_string),
        color: validated.color().map(str::to_string),
        cue: validated.cue().map(str::to_string),
        frequency_type: cadence_fields.frequency_type,
        per_period_target: cadence_fields.per_period_target,
        day_of_month: cadence_fields.day_of_month,
        weekdays: cadence_fields.weekdays.unwrap_or_default(),
        target_count: validated.target_count(),
        lookup_key: validated.lookup_key().to_string(),
        now,
    };
    let habit_id_typed = lorvex_domain::HabitId::from_trusted(habit_id);
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        habit_id_typed.as_str(),
        crate::error::CliError::from,
    )?;
    let habit = load_habit_row(&tx, &habit_id_typed)?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(habit)
}
