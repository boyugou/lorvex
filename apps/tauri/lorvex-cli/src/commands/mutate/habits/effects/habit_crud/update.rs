//! `habits update` — patch a habit row (including archive/unarchive
//! toggles) and emit the upsert envelope.

use lorvex_domain::habits::HabitUpdateDraft;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_HABIT;
use lorvex_runtime::get_or_create_device_id;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::super::{
    active_habit_lookup_key_exists, habit_payload, load_habit_row, rebuild_habit_weekdays,
    HabitRow, HabitUpdateFields,
};
use crate::commands::shared::execute_cli_entity_mutation_map_store_error;
use crate::hlc_guard::lock_shared;

struct UpdateCliHabitMutation {
    id: String,
    before_json: Value,
    parts: lorvex_domain::habits::HabitUpdateParts,
    now: String,
}

impl Mutation for UpdateCliHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let mut set_clauses: Vec<&'static str> = vec!["updated_at = ?", "version = ?"];
        let mut values: Vec<Box<dyn rusqlite::types::ToSql>> =
            vec![Box::new(self.now.clone()), Box::new(version)];

        let parts = self.parts.clone();
        if let Some(name) = parts.name {
            set_clauses.push("name = ?");
            values.push(Box::new(name));
            let key = parts.lookup_key.clone().unwrap_or_default();
            set_clauses.push("lookup_key = ?");
            values.push(Box::new(key));
        }
        push_nullable_patch(&mut set_clauses, &mut values, "icon = ?", parts.icon);
        push_nullable_patch(&mut set_clauses, &mut values, "color = ?", parts.color);
        push_nullable_patch(&mut set_clauses, &mut values, "cue = ?", parts.cue);
        // Cadence replacement is atomic: when a new cadence is present,
        // rewrite every typed column and (after the UPDATE lands) rebuild
        // the `habit_weekdays` child from its weekday set.
        let cadence_fields = parts
            .frequency
            .as_ref()
            .map(lorvex_domain::habits::HabitCadence::to_fields);
        if let Some(fields) = &cadence_fields {
            set_clauses.push("frequency_type = ?");
            values.push(Box::new(fields.frequency_type.clone()));
            set_clauses.push("per_period_target = ?");
            values.push(Box::new(fields.per_period_target));
            set_clauses.push("day_of_month = ?");
            values.push(Box::new(fields.day_of_month));
        }
        if let Some(target_count) = parts.target_count {
            set_clauses.push("target_count = ?");
            values.push(Box::new(target_count));
        }
        if let Some(archived) = parts.archived.target_value() {
            set_clauses.push("archived = ?");
            values.push(Box::new(archived));
        }

        values.push(Box::new(self.id.clone()));
        let sql = format!("UPDATE habits SET {} WHERE id = ?", set_clauses.join(", "));
        let params: Vec<&dyn rusqlite::types::ToSql> =
            values.iter().map(std::convert::AsRef::as_ref).collect();
        let changed = conn.execute(&sql, params.as_slice())?;
        if changed == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_HABIT,
                id: self.id.clone(),
            });
        }
        if let Some(fields) = &cadence_fields {
            rebuild_habit_weekdays(conn, &self.id, fields.weekdays.as_deref().unwrap_or(&[]))?;
        }
        let habit_id = lorvex_domain::HabitId::from_trusted(self.id.clone());
        let after = lorvex_store::payload_loaders::load_habit_sync_payload(conn, &habit_id)?
            .ok_or_else(|| StoreError::NotFound {
                entity: ENTITY_HABIT,
                id: self.id.clone(),
            })?;
        let name = after
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or(self.id.as_str())
            .to_string();
        Ok(MutationOutput::new(
            after,
            format!("Updated habit '{name}'"),
        ))
    }
}

fn push_nullable_patch(
    set_clauses: &mut Vec<&'static str>,
    values: &mut Vec<Box<dyn rusqlite::types::ToSql>>,
    column: &'static str,
    patch: lorvex_domain::Patch<String>,
) {
    match patch {
        lorvex_domain::Patch::Unset => {}
        lorvex_domain::Patch::Clear => {
            set_clauses.push(column);
            values.push(Box::new(Option::<String>::None));
        }
        lorvex_domain::Patch::Set(v) => {
            set_clauses.push(column);
            values.push(Box::new(Some(v)));
        }
    }
}

pub(crate) fn update_habit_with_conn(
    conn: &mut Connection,
    habit_id: &lorvex_domain::HabitId,
    fields: HabitUpdateFields<'_>,
) -> Result<HabitRow, crate::error::CliError> {
    let habit_id_str = habit_id.as_str();
    let archive_action = lorvex_domain::habits::ArchiveAction::from_optional_bool(fields.archived);
    // The typed cadence is already assembled at the CLI boundary; a
    // `Some(cadence)` replaces the whole cadence atomically, `None` leaves
    // it alone.
    let frequency = fields.frequency;
    if fields.name.is_none()
        && fields.icon.is_unset()
        && fields.color.is_unset()
        && fields.cue.is_unset()
        && frequency.is_none()
        && fields.target_count.is_none()
        && !archive_action.is_present()
    {
        return Err(crate::error::CliError::Validation(
            "habit update requires at least one field".to_string(),
        ));
    }

    let validated = lorvex_domain::habits::validate_habit_update_draft(HabitUpdateDraft {
        name: fields.name,
        icon: fields.icon,
        color: fields.color,
        cue: fields.cue,
        frequency,
        target_count: fields.target_count,
        archived: archive_action,
    })?;

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    // keep the pre-update row for the audit trail
    // (was discarded as `_before`).
    let before = load_habit_row(&tx, habit_id)?;
    let before_payload = habit_payload(&tx, habit_id)?;
    let conflict_lookup_key = if let Some(key) = validated.lookup_key() {
        Some(key.to_string())
    } else if validated.archived() == lorvex_domain::habits::ArchiveAction::Unarchive
        && before.archived
    {
        Some(tx.query_row(
            "SELECT lookup_key FROM habits WHERE id = ?1",
            [habit_id_str],
            |row| row.get::<_, String>(0),
        )?)
    } else {
        None
    };
    if let Some(key) = conflict_lookup_key.as_deref() {
        if active_habit_lookup_key_exists(&tx, key, Some(habit_id_str))? {
            let name = validated.name().unwrap_or(&before.name);
            return Err(crate::error::CliError::Conflict(format!(
                "a habit named '{name}' already exists"
            )));
        }
    }

    let now = lorvex_domain::sync_timestamp_now();
    let mutation = UpdateCliHabitMutation {
        id: habit_id_str.to_string(),
        before_json: before_payload,
        parts: validated.into_parts(),
        now,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        habit_id_str,
        crate::error::CliError::from,
    )?;
    let habit = load_habit_row(&tx, habit_id)?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(habit)
}
