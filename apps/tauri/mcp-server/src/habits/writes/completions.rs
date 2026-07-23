use crate::contract::MAX_SHORT_TEXT_LENGTH;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::utc_now_iso;
use crate::system::vec_limits::validate_batch_ids;
use crate::tasks::validation::validate_optional_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{EDGE_HABIT_COMPLETION, OP_DELETE};
use lorvex_domain::HabitId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::HABIT_COMPLETION_RESPONSE;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::json;

use super::super::{load_habit_name_required, HabitCompletion};

#[derive(Debug, serde::Serialize)]
struct HabitCompletionState {
    habit_id: String,
    completed_date: String,
    value: i64,
    note: Option<String>,
    created_at: String,
    updated_at: String,
    version: String,
}

impl HabitCompletionState {
    fn public_completion(&self) -> HabitCompletion {
        HabitCompletion {
            habit_id: self.habit_id.clone(),
            completed_date: self.completed_date.clone(),
            value: self.value,
            note: self.note.clone(),
            created_at: self.created_at.clone(),
            updated_at: self.updated_at.clone(),
        }
    }
}

fn completion_mcp_error_to_store_error(error: McpError) -> StoreError {
    match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) => StoreError::Validation(message),
        McpError::NotFound(message) => StoreError::NotFound {
            entity: EDGE_HABIT_COMPLETION,
            id: message,
        },
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    }
}

/// Validate a date string is in YYYY-MM-DD format.
fn validate_ymd_date(date: &str) -> Result<(), McpError> {
    if lorvex_domain::time::parse_iso_date(date).is_err() {
        return Err(McpError::Validation(format!(
            "invalid date format '{date}', expected YYYY-MM-DD"
        )));
    }
    Ok(())
}

fn load_completion_state(
    conn: &Connection,
    habit_id: &str,
    completed_date: &str,
) -> Result<Option<HabitCompletionState>, McpError> {
    Ok(conn
        .query_row(
            "SELECT habit_id, completed_date, value, note, created_at, updated_at, version
             FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
            params![habit_id, completed_date],
            |row| {
                Ok(HabitCompletionState {
                    habit_id: row.get(0)?,
                    completed_date: row.get(1)?,
                    value: row.get(2)?,
                    note: row.get(3)?,
                    created_at: row.get(4)?,
                    updated_at: row.get(5)?,
                    version: row.get(6)?,
                })
            },
        )
        .optional()?)
}

pub(crate) fn complete_habit(
    conn: &Connection,
    habit_id: &HabitId,
    date: Option<&str>,
    note: Option<&str>,
) -> Result<String, McpError> {
    let habit_name = load_habit_name_required(conn, habit_id.as_str())?;
    validate_optional_string_length(note, "note", MAX_SHORT_TEXT_LENGTH)?;

    let now = utc_now_iso();
    let today_local = today_ymd_for_conn(conn)?;
    let completed_date = date.unwrap_or(&today_local);
    validate_ymd_date(completed_date)?;

    // Look up target_count to clamp the completion value (parity with Tauri app).
    let target_count: i64 = conn.query_row(
        "SELECT MAX(target_count, 1) FROM habits WHERE id = ?1",
        params![habit_id.as_str()],
        |row| row.get(0),
    )?;

    // Snapshot the full prior completion row before the upsert. This
    // must propagate database failures; otherwise the changelog can
    // silently lose audit state while the write still commits.
    let before_state = load_completion_state(conn, habit_id.as_str(), completed_date)?;
    let entity_id = format!("{}:{}", habit_id.as_str(), completed_date);
    let mutation = CompleteHabitMutation {
        habit_id: habit_id.as_str().to_string(),
        habit_name,
        completed_date: completed_date.to_string(),
        note: note.map(str::to_string),
        target_count,
        before_state,
        now,
    };
    let output = execute_mcp_mutation(conn, &mutation, "complete_habit", entity_id)?;
    let completion = output
        .get_extra(&HABIT_COMPLETION_RESPONSE)
        .cloned()
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: complete_habit response extra is present".to_string(),
            )
        })?;
    Ok(serde_json::to_string(&completion)?)
}

struct CompleteHabitMutation {
    habit_id: String,
    habit_name: String,
    completed_date: String,
    note: Option<String>,
    target_count: i64,
    before_state: Option<HabitCompletionState>,
    now: String,
}

impl Mutation for CompleteHabitMutation {
    fn entity_kind(&self) -> &'static str {
        EDGE_HABIT_COMPLETION
    }

    fn operation(&self) -> &'static str {
        "complete"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        self.before_state
            .as_ref()
            .map(serde_json::to_value)
            .transpose()
            .map_err(StoreError::from)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        conn.execute(
            "INSERT INTO habit_completions (habit_id, completed_date, value, note, version, created_at, updated_at)
             VALUES (?1, ?2, 1, ?3, ?4, ?5, ?5)
             ON CONFLICT(habit_id, completed_date) DO UPDATE SET value = MIN(value + 1, ?6), note = COALESCE(excluded.note, note), version = excluded.version, updated_at = excluded.updated_at",
            params![
                &self.habit_id,
                &self.completed_date,
                self.note.as_deref(),
                version,
                &self.now,
                self.target_count
            ],
        )?;

        let completion_state = load_completion_state(conn, &self.habit_id, &self.completed_date)
            .map_err(completion_mcp_error_to_store_error)?
            .ok_or_else(|| StoreError::NotFound {
                entity: EDGE_HABIT_COMPLETION,
                id: format!("{}:{}", self.habit_id, self.completed_date),
            })?;
        let after = serde_json::to_value(&completion_state)?;
        let mut output = MutationOutput::new(
            after,
            format!(
                "Completed habit '{}' for {}",
                self.habit_name, self.completed_date
            ),
        );
        output.set_extra(
            &HABIT_COMPLETION_RESPONSE,
            serde_json::to_value(completion_state.public_completion())?,
        );
        Ok(output)
    }
}

pub(crate) fn uncomplete_habit(
    conn: &Connection,
    habit_id: &HabitId,
    date: Option<&str>,
) -> Result<String, McpError> {
    let habit_name = load_habit_name_required(conn, habit_id.as_str())?;

    let today_local = today_ymd_for_conn(conn)?;
    let completed_date = date.unwrap_or(&today_local);
    validate_ymd_date(completed_date)?;

    // Snapshot the full completion row before deleting. A database
    // failure here must abort before the DELETE so audit state and data
    // mutation cannot diverge.
    let previous_state = load_completion_state(conn, habit_id.as_str(), completed_date)?
        .ok_or_else(|| {
            McpError::NotFound(format!(
                "no completion found for habit '{habit_name}' on {completed_date}"
            ))
        })?;
    let entity_id = format!("{}:{}", habit_id.as_str(), completed_date);
    let mutation = UncompleteHabitMutation {
        habit_id: habit_id.as_str().to_string(),
        habit_name,
        completed_date: completed_date.to_string(),
        previous_state,
    };
    let output = execute_mcp_mutation(conn, &mutation, "uncomplete_habit", entity_id)?;
    Ok(serde_json::to_string(&output.after)?)
}

struct UncompleteHabitMutation {
    habit_id: String,
    habit_name: String,
    completed_date: String,
    previous_state: HabitCompletionState,
}

impl Mutation for UncompleteHabitMutation {
    fn entity_kind(&self) -> &'static str {
        EDGE_HABIT_COMPLETION
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        serde_json::to_value(&self.previous_state)
            .map(Some)
            .map_err(StoreError::from)
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let deleted = conn.execute(
            "DELETE FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
            params![&self.habit_id, &self.completed_date],
        )?;

        if deleted == 0 {
            return Err(StoreError::NotFound {
                entity: EDGE_HABIT_COMPLETION,
                id: format!("{}:{}", self.habit_id, self.completed_date),
            });
        }

        Ok(MutationOutput::new(
            json!({
                "deleted": true,
                "habit_id": self.habit_id,
                "habit_name": self.habit_name,
                "completed_date": self.completed_date,
                "previous": serde_json::to_value(&self.previous_state)?,
            }),
            format!(
                "Removed completion for habit '{}' on {}",
                self.habit_name, self.completed_date
            ),
        ))
    }
}

pub(crate) fn batch_complete_habit(
    conn: &Connection,
    habit_ids: &[String],
    date: Option<&str>,
) -> Result<String, McpError> {
    // #3029-H1: route through the canonical batch-id validator
    // (empty-list reject, duplicate detect, 500-id cap).
    // loop happily accepted `["habit-a", "habit-a"]` and called
    // `complete_habit` twice — `INSERT OR REPLACE` advanced the upsert
    // each call, silently double-counting the per-day value/note.
    // Mirror every other batch tool in the surface.
    validate_batch_ids(habit_ids, "batch_complete_habit")?;
    let today_local = today_ymd_for_conn(conn)?;
    let completed_date = date.unwrap_or(&today_local);
    validate_ymd_date(completed_date)?;

    // every MCP write tool runs under `with_conn`,
    // which wraps the closure in `BEGIN IMMEDIATE` + a `mcp_tool`
    // SAVEPOINT.
    // `results: [{habit_id, error}]` slot while the outer transaction
    // committed everything before the failure — so the response
    // claimed "5 of 7 succeeded" but the database actually held all
    // 7 completions or none, depending on the error path inside
    // `complete_habit`. Mirror the outer atomicity and propagate the
    // first per-id error so the savepoint rolls the whole batch back.
    // Callers retry with the failing id removed; the response shape
    // stays per-id so consumers can still narrate which completion
    // landed.
    let mut results: Vec<serde_json::Value> = Vec::with_capacity(habit_ids.len());
    for habit_id in habit_ids {
        let habit_id_typed = HabitId::from_trusted(habit_id.clone());
        let json_str = complete_habit(conn, &habit_id_typed, Some(completed_date), None)?;
        let completion: serde_json::Value =
            serde_json::from_str(&json_str).unwrap_or(serde_json::Value::Null);
        results.push(json!({ "habit_id": habit_id, "completion": completion }));
    }

    // #3033-M10: atomic semantics make `count == completed_count`
    // always true (the loop returns the first error and the outer
    // savepoint rolls the batch back), so the historical
    // `completed_count` field is dead weight that the assistant has
    // to reconcile against `count`. Drop it; callers that want the
    // batch length read it from `count`.
    Ok(serde_json::to_string(&json!({
        "results": results,
        "count": habit_ids.len(),
    }))?)
}
