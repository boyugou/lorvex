//! Shared habit reminder policy mutation operations.
//!
//! These are the canonical implementations for habit reminder policy CRUD.
//! Both MCP and Tauri delegate to these instead of maintaining independent SQL.

use lorvex_domain::validation::validate_time_format;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;

use lorvex_store::StoreError;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// A fully loaded habit reminder policy row (joined with the habit name).
///
/// `version` is included so callers that route through the
/// `lorvex_store::payload_loaders::habit_reminder_policy_payload`
/// primitive emit the canonical 7-field wire shape;
/// hand-rolled audit payload dropped `version`, drifting from every
/// other surface.
#[derive(Debug, Clone, Serialize)]
pub struct HabitReminderPolicyRow {
    pub id: String,
    pub habit_id: String,
    pub habit_name: String,
    pub reminder_time: String,
    pub enabled: bool,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

fn row_from_query(row: &rusqlite::Row<'_>) -> rusqlite::Result<HabitReminderPolicyRow> {
    Ok(HabitReminderPolicyRow {
        id: row.get(0)?,
        habit_id: row.get(1)?,
        habit_name: row.get(2)?,
        reminder_time: row.get(3)?,
        enabled: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
        version: row.get(7)?,
    })
}

const POLICY_SELECT: &str = "\
    SELECT p.id, p.habit_id, h.name, p.reminder_time, p.enabled, p.created_at, p.updated_at, \
           p.version \
    FROM habit_reminder_policies p JOIN habits h ON h.id = p.habit_id";

// ---------------------------------------------------------------------------
// Read helpers
// ---------------------------------------------------------------------------

/// Load a single habit reminder policy by ID. Returns `Ok(None)` if the
/// row does not exist; reserve `StoreError` for genuine query failures
/// so callers can distinguish "missing" from "broken".
pub fn load_policy_by_id(
    conn: &Connection,
    policy_id: &str,
) -> Result<Option<HabitReminderPolicyRow>, StoreError> {
    use rusqlite::OptionalExtension as _;
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    conn.prepare_cached(SQL.get_or_init(|| format!("{POLICY_SELECT} WHERE p.id = ?1")))?
        .query_row(params![policy_id], row_from_query)
        .optional()
        .map_err(StoreError::from)
}

/// Load all habit reminder policies, ordered by habit name then time.
pub fn list_all_policies(conn: &Connection) -> Result<Vec<HabitReminderPolicyRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("{POLICY_SELECT} ORDER BY h.name COLLATE NOCASE ASC, p.reminder_time ASC")
    });
    let mut stmt = conn.prepare(sql)?;
    let policies = stmt
        .query_map([], row_from_query)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(policies)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Returns the ID of an existing policy that would conflict (same habit +
/// same time), optionally excluding a specific policy ID (for updates).
fn load_conflicting_slot_id(
    conn: &Connection,
    habit_id: &lorvex_domain::HabitId,
    reminder_time: &str,
    excluding_id: Option<&str>,
) -> Result<Option<String>, StoreError> {
    excluding_id.map_or_else(
        || {
            conn.query_row(
                "SELECT id FROM habit_reminder_policies \
                 WHERE habit_id = ?1 AND reminder_time = ?2",
                params![habit_id, reminder_time],
                |row| row.get(0),
            )
            .optional()
            .map_err(StoreError::from)
        },
        |policy_id| {
            conn.query_row(
                "SELECT id FROM habit_reminder_policies \
                 WHERE habit_id = ?1 AND reminder_time = ?2 AND id != ?3",
                params![habit_id, reminder_time, policy_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(StoreError::from)
        },
    )
}

// ---------------------------------------------------------------------------
// Upsert
// ---------------------------------------------------------------------------

/// Parameters for upserting a habit reminder policy.
#[derive(Debug)]
pub struct UpsertHabitReminderPolicyParams<'a> {
    /// Optional existing policy ID. `None` or blank string means create new.
    pub policy_id: Option<&'a str>,
    pub habit_id: &'a str,
    pub reminder_time: &'a str,
    pub enabled: bool,
    pub version: &'a str,
    pub now: &'a str,
}

/// Create or update a habit reminder policy.
///
/// Validates:
/// - `habit_id` is non-empty and references an existing habit
/// - `reminder_time` is valid HH:MM (via domain `validate_time_format`)
/// - No conflicting slot at the same time for the same habit
/// - If updating, the existing slot belongs to the specified habit
///
/// Returns the fully loaded policy row on success.
pub fn upsert_habit_reminder_policy(
    conn: &Connection,
    params: &UpsertHabitReminderPolicyParams<'_>,
) -> Result<HabitReminderPolicyRow, StoreError> {
    let habit_id = params.habit_id.trim();
    if habit_id.is_empty() {
        return Err(StoreError::Validation(
            "habit_id must not be empty".to_string(),
        ));
    }

    // Validate time format using the canonical domain validator.
    validate_time_format(params.reminder_time).map_err(|e| {
        StoreError::Validation(format!(
            "invalid reminder_time '{}': {}",
            params.reminder_time, e
        ))
    })?;

    // Verify the habit exists.
    let habit_exists: Option<String> = conn
        .query_row(
            "SELECT id FROM habits WHERE id = ?1",
            params![habit_id],
            |row| row.get(0),
        )
        .optional()?;
    if habit_exists.is_none() {
        return Err(StoreError::NotFound {
            entity: "habit",
            id: habit_id.to_string(),
        });
    }

    let enabled_val: i64 = i64::from(params.enabled);

    let resolved_policy_id = if let Some(id) =
        params.policy_id.map(str::trim).filter(|v| !v.is_empty())
    {
        // --- UPDATE path ---
        let existing_habit_id: Option<String> = conn
            .query_row(
                "SELECT habit_id FROM habit_reminder_policies WHERE id = ?1",
                rusqlite::params![id],
                |row| row.get(0),
            )
            .optional()?;
        let Some(existing_habit_id) = existing_habit_id else {
            return Err(StoreError::NotFound {
                entity: "habit_reminder_policy",
                id: id.to_string(),
            });
        };
        if existing_habit_id != habit_id {
            return Err(StoreError::Validation(format!(
                "habit reminder slot '{id}' belongs to a different habit"
            )));
        }
        let typed_habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
        if load_conflicting_slot_id(conn, &typed_habit_id, params.reminder_time, Some(id))?
            .is_some()
        {
            return Err(StoreError::Validation(format!(
                "habit '{habit_id}' already has a reminder slot at {}",
                params.reminder_time
            )));
        }
        conn.prepare_cached(
            "UPDATE habit_reminder_policies \
             SET reminder_time = ?1, enabled = ?2, version = ?3, updated_at = ?4 \
             WHERE id = ?5",
        )?
        .execute(rusqlite::params![
            params.reminder_time,
            enabled_val,
            params.version,
            params.now,
            id
        ])?;
        id.to_string()
    } else {
        // --- INSERT path ---
        let typed_habit_id = lorvex_domain::HabitId::from_trusted(habit_id.to_string());
        if load_conflicting_slot_id(conn, &typed_habit_id, params.reminder_time, None)?.is_some() {
            return Err(StoreError::Validation(format!(
                "habit '{habit_id}' already has a reminder slot at {}",
                params.reminder_time
            )));
        }
        let id = lorvex_domain::entity_id::new_entity_id_string();
        conn.prepare_cached(
            "INSERT INTO habit_reminder_policies \
             (id, habit_id, reminder_time, enabled, version, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        )?
        .execute(rusqlite::params![
            id,
            habit_id,
            params.reminder_time,
            enabled_val,
            params.version,
            params.now
        ])?;
        id
    };

    // After upsert the row must exist; surface a typed error if the
    // row vanished between our INSERT/UPDATE and this re-read.
    load_policy_by_id(conn, &resolved_policy_id)?.ok_or_else(|| {
        StoreError::Validation(format!(
            "habit reminder policy '{resolved_policy_id}' not found after upsert"
        ))
    })
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

/// Result of deleting a habit reminder policy.
#[derive(Debug)]
pub struct DeleteHabitReminderPolicyResult {
    /// Whether a row was actually deleted.
    pub deleted: bool,
}

/// Delete a habit reminder policy by ID.
///
/// Returns whether a row was actually deleted.
pub fn delete_habit_reminder_policy(
    conn: &Connection,
    policy_id: &str,
) -> Result<DeleteHabitReminderPolicyResult, StoreError> {
    let deleted = conn
        .prepare_cached("DELETE FROM habit_reminder_policies WHERE id = ?1")?
        .execute(params![policy_id])?;
    Ok(DeleteHabitReminderPolicyResult {
        deleted: deleted > 0,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
