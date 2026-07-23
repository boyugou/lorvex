use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{new_uuid, utc_now_iso};
use lorvex_domain::habits::{HabitCadence, HabitFrequencyFields, WeekDay};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_HABIT;
use lorvex_domain::Patch;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};

use super::super::{habit_from_row, load_habit_required, Habit, HABIT_SELECT_COLS};

/// Parse the optional weekday-token list (lowercase `mon`..`sun`) into typed
/// [`WeekDay`] values. Absent / empty → `None` ("every day" for a weekly
/// cadence). An unknown token is a client-facing validation error.
fn parse_weekday_tokens(tokens: Option<&[String]>) -> Result<Option<Vec<WeekDay>>, McpError> {
    let Some(tokens) = tokens else {
        return Ok(None);
    };
    if tokens.is_empty() {
        return Ok(None);
    }
    let mut out = Vec::with_capacity(tokens.len());
    for token in tokens {
        let day = WeekDay::parse(token).ok_or_else(|| {
            McpError::Validation(format!("invalid weekday '{token}' (expected mon..sun)"))
        })?;
        out.push(day);
    }
    Ok(Some(out))
}

/// Delete-then-insert the `habit_weekdays` rows for one habit from a weekday
/// set (Monday-first ints). Parent-owned materialization mirroring the sync
/// applier: an empty set leaves the habit with no weekday rows.
fn rebuild_habit_weekdays(
    conn: &Connection,
    habit_id: &str,
    weekdays: &[WeekDay],
) -> Result<(), StoreError> {
    conn.execute(
        "DELETE FROM habit_weekdays WHERE habit_id = ?1",
        params![habit_id],
    )?;
    for day in weekdays {
        conn.execute(
            "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?1, ?2)",
            params![habit_id, day.as_index()],
        )?;
    }
    Ok(())
}

/// Build the typed cadence from the flat MCP args. `frequency_type` selects
/// the rhythm; `weekdays` (weekly), `per_period_target` (times_per_week), and
/// `day_of_month` (monthly) supply the detail. `None` frequency_type leaves
/// the cadence unspecified (create defaults to daily; update leaves it alone).
fn build_cadence(
    frequency_type: Option<&str>,
    weekdays: Option<&[String]>,
    per_period_target: Option<i64>,
    day_of_month: Option<i64>,
) -> Result<Option<HabitCadence>, McpError> {
    let Some(frequency_type) = frequency_type else {
        return Ok(None);
    };
    let cadence = HabitCadence::from_fields(&HabitFrequencyFields {
        frequency_type: frequency_type.to_string(),
        weekdays: parse_weekday_tokens(weekdays)?,
        per_period_target: per_period_target.unwrap_or(1),
        day_of_month,
    })?;
    Ok(Some(cadence))
}

pub(crate) struct CreateHabitParams<'a> {
    pub name: &'a str,
    pub icon: Option<&'a str>,
    pub color: Option<&'a str>,
    pub cue: Option<&'a str>,
    pub frequency_type: Option<&'a str>,
    pub weekdays: Option<&'a [String]>,
    pub per_period_target: Option<i64>,
    pub day_of_month: Option<i64>,
    pub target_count: Option<i64>,
}

pub(crate) fn create_habit(
    conn: &Connection,
    params: CreateHabitParams<'_>,
) -> Result<String, McpError> {
    // Bridge the flat cadence args into the typed primitive at the MCP entry
    // seam; the typed `HabitCadence` enforces the per-cadence invariants.
    let frequency = build_cadence(
        params.frequency_type,
        params.weekdays,
        params.per_period_target,
        params.day_of_month,
    )?;
    let validated = lorvex_domain::habits::validate_habit_create_draft(
        lorvex_domain::habits::HabitCreateDraft {
            name: params.name,
            icon: params.icon,
            color: params.color,
            cue: params.cue,
            frequency,
            target_count: params.target_count,
        },
    )?;
    let cadence_fields = validated.frequency().to_fields();

    // dedup is enforced at the schema layer via
    // `idx_habits_lookup_key_active`. Pre-check with an indexed
    // O(1) lookup so we can surface a friendly Validation error;
    // the UNIQUE index is the canonical contract.
    let exists: bool = conn.query_row(
        "SELECT COUNT(*) FROM habits WHERE lookup_key = ?1 AND archived = 0",
        params![validated.lookup_key()],
        |row| row.get::<_, i64>(0),
    )? > 0;
    if exists {
        return Err(McpError::Validation(format!(
            "a habit named '{}' already exists",
            validated.name()
        )));
    }

    let id = new_uuid();
    let now = utc_now_iso();
    let mutation = CreateHabitMutation {
        id: id.clone(),
        name: validated.name().to_string(),
        icon: validated.icon().map(str::to_string),
        color: validated.color().map(str::to_string),
        cue: validated.cue().map(str::to_string),
        cadence_fields,
        target_count: validated.target_count(),
        lookup_key: validated.lookup_key().to_string(),
        now,
    };
    let output = execute_mcp_mutation(conn, &mutation, "create_habit", id)?;

    Ok(serde_json::to_string(&output.after)?)
}

struct CreateHabitMutation {
    id: String,
    name: String,
    icon: Option<String>,
    color: Option<String>,
    cue: Option<String>,
    cadence_fields: HabitFrequencyFields,
    target_count: i64,
    lookup_key: String,
    now: String,
}

impl Mutation for CreateHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        conn.execute(
            "INSERT INTO habits
                (id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
                 target_count, archived, created_at, updated_at, lookup_key, version)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, ?10, ?10, ?11, ?12)",
            params![
                &self.id,
                &self.name,
                self.icon.as_deref(),
                self.color.as_deref(),
                self.cue.as_deref(),
                &self.cadence_fields.frequency_type,
                self.cadence_fields.per_period_target,
                self.cadence_fields.day_of_month,
                self.target_count,
                &self.now,
                &self.lookup_key,
                version
            ],
        )?;

        // Materialize the `weekly` weekday set into the child table.
        rebuild_habit_weekdays(
            conn,
            &self.id,
            self.cadence_fields.weekdays.as_deref().unwrap_or(&[]),
        )?;

        let habit: Habit = conn.query_row(
            &format!("SELECT {HABIT_SELECT_COLS} FROM habits WHERE id = ?1"),
            params![&self.id],
            habit_from_row,
        )?;
        let after = serde_json::to_value(&habit)?;
        Ok(MutationOutput::new(
            after,
            format!("Created habit '{}'", habit.name),
        ))
    }
}

pub(crate) struct UpdateHabitParams<'a> {
    pub id: &'a str,
    pub name: Option<&'a str>,
    pub icon: lorvex_domain::Patch<&'a str>,
    pub color: lorvex_domain::Patch<&'a str>,
    pub cue: lorvex_domain::Patch<&'a str>,
    pub frequency_type: Option<&'a str>,
    pub weekdays: Option<&'a [String]>,
    pub per_period_target: Option<i64>,
    pub day_of_month: Option<i64>,
    pub target_count: Option<i64>,
    pub archived: Option<bool>,
}

pub(crate) fn update_habit(
    conn: &Connection,
    p: UpdateHabitParams<'_>,
) -> Result<String, McpError> {
    let id = p.id;
    // Setting `frequency_type` replaces the entire cadence atomically from
    // the supplied detail fields; leaving it unset leaves the cadence — and
    // its `habit_weekdays` child — untouched.
    let frequency_patch = build_cadence(
        p.frequency_type,
        p.weekdays,
        p.per_period_target,
        p.day_of_month,
    )?;
    let validated = lorvex_domain::habits::validate_habit_update_draft(
        lorvex_domain::habits::HabitUpdateDraft {
            name: p.name,
            icon: p.icon,
            color: p.color,
            cue: p.cue,
            frequency: frequency_patch,
            target_count: p.target_count,
            archived: lorvex_domain::habits::ArchiveAction::from_optional_bool(p.archived),
        },
    )?;

    // #2373: capture the pre-mutation row so the executor audit
    // persists a structured before-state snapshot alongside the
    // post-mutation `habit` row below.
    let before_habit = load_habit_required(conn, id)?;

    // dedup via the persisted `lookup_key` column.
    // Pre-check the indexed lookup; the partial UNIQUE index on
    // (`lookup_key`) WHERE archived = 0 is the canonical contract.
    let conflict_lookup_key = if let Some(key) = validated.lookup_key() {
        Some(key.to_string())
    } else if validated.archived() == lorvex_domain::habits::ArchiveAction::Unarchive
        && before_habit.archived
    {
        Some(conn.query_row(
            "SELECT lookup_key FROM habits WHERE id = ?1",
            params![id],
            |row| row.get::<_, String>(0),
        )?)
    } else {
        None
    };
    if let Some(key) = conflict_lookup_key.as_deref() {
        let conflict: bool = conn.query_row(
            "SELECT COUNT(*) FROM habits WHERE lookup_key = ?1 AND id != ?2 AND archived = 0",
            params![key, id],
            |row| row.get::<_, i64>(0),
        )? > 0;
        if conflict {
            let new_name = validated.name().unwrap_or(&before_habit.name);
            return Err(McpError::Validation(format!(
                "a habit named '{new_name}' already exists"
            )));
        }
    }

    let mutation = UpdateHabitMutation {
        id: id.to_string(),
        before_habit,
        parts: validated.into_parts(),
        now: utc_now_iso(),
    };
    let output = execute_mcp_mutation(conn, &mutation, "update_habit", id.to_string())?;

    Ok(serde_json::to_string(&output.after)?)
}

struct UpdateHabitMutation {
    id: String,
    before_habit: Habit,
    parts: lorvex_domain::habits::HabitUpdateParts,
    now: String,
}

impl Mutation for UpdateHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(Some(serde_json::to_value(&self.before_habit)?))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let mut set_clauses: Vec<&'static str> = vec!["updated_at = ?", "version = ?"];
        let mut values: Vec<Box<dyn rusqlite::types::ToSql>> =
            vec![Box::new(self.now.clone()), Box::new(version)];

        let parts = self.parts.clone();
        if let Some(n) = parts.name {
            set_clauses.push("name = ?");
            values.push(Box::new(n));
            // Keep the persisted `lookup_key` in sync with every rename.
            let key = parts.lookup_key.clone().unwrap_or_default();
            set_clauses.push("lookup_key = ?");
            values.push(Box::new(key));
        }
        push_nullable_patch(&mut set_clauses, &mut values, "icon = ?", parts.icon);
        push_nullable_patch(&mut set_clauses, &mut values, "color = ?", parts.color);
        push_nullable_patch(&mut set_clauses, &mut values, "cue = ?", parts.cue);
        // A cadence replacement rewrites the typed columns AND, after the
        // UPDATE lands, rebuilds the `habit_weekdays` child. Capture the
        // weekday set here so the rebuild runs only when cadence changed.
        let weekdays_to_rebuild: Option<Vec<WeekDay>> = if let Some(cadence) = &parts.frequency {
            let fields = cadence.to_fields();
            set_clauses.push("frequency_type = ?");
            values.push(Box::new(fields.frequency_type));
            set_clauses.push("per_period_target = ?");
            values.push(Box::new(fields.per_period_target));
            set_clauses.push("day_of_month = ?");
            values.push(Box::new(fields.day_of_month));
            Some(fields.weekdays.unwrap_or_default())
        } else {
            None
        };
        if let Some(tc) = parts.target_count {
            set_clauses.push("target_count = ?");
            values.push(Box::new(tc));
        }
        if let Some(a) = parts.archived.target_value() {
            set_clauses.push("archived = ?");
            values.push(Box::new(a));
        }

        values.push(Box::new(self.id.clone()));
        let sql = format!("UPDATE habits SET {} WHERE id = ?", set_clauses.join(", "));
        let params: Vec<&dyn rusqlite::types::ToSql> = values.iter().map(AsRef::as_ref).collect();
        let changed = conn.execute(&sql, params.as_slice())?;
        if changed == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_HABIT,
                id: self.id.clone(),
            });
        }

        if let Some(weekdays) = weekdays_to_rebuild {
            rebuild_habit_weekdays(conn, &self.id, &weekdays)?;
        }

        let habit: Habit = conn.query_row(
            &format!("SELECT {HABIT_SELECT_COLS} FROM habits WHERE id = ?1"),
            params![&self.id],
            habit_from_row,
        )?;
        let after = serde_json::to_value(&habit)?;
        Ok(MutationOutput::new(
            after,
            format!("Updated habit '{}'", habit.name),
        ))
    }
}

fn push_nullable_patch(
    set_clauses: &mut Vec<&'static str>,
    values: &mut Vec<Box<dyn rusqlite::types::ToSql>>,
    column: &'static str,
    patch: Patch<String>,
) {
    match patch {
        Patch::Unset => {}
        Patch::Clear => {
            set_clauses.push(column);
            values.push(Box::new(Option::<String>::None));
        }
        Patch::Set(v) => {
            set_clauses.push(column);
            values.push(Box::new(Some(v)));
        }
    }
}
