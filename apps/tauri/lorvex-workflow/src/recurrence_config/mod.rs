//! Shared recurrence config transition planner.
//!
//! All write surfaces that create or modify recurrence must route through
//! this planner. It is the single semantic owner of the invariant:
//!
//! ```text
//! recurrence IS NULL
//! OR (due_date IS NOT NULL AND recurrence_group_id IS NOT NULL
//!     AND canonical_occurrence_date IS NOT NULL)
//! ```
//!
//! The planner classifies each recurrence change into one of four transitions
//! and outputs the exact column actions needed. Surfaces apply these actions
//! into their SQL UPDATE/INSERT — they do NOT invent recurrence logic locally.

/// What kind of recurrence config change is happening.
pub enum RecurrenceTransition {
    /// Recurrence is being turned on (NULL → non-NULL rule).
    Enable,
    /// Recurrence rule is being changed (non-NULL → different non-NULL).
    UpdateRule,
    /// Recurrence is being turned off (non-NULL → NULL).
    Disable,
    /// No recurrence change in this update.
    NoChange,
}

/// Column-level actions the planner emits for the caller to apply.
pub struct RecurrenceColumnActions {
    /// New recurrence_group_id to set (None = don't touch).
    pub set_recurrence_group_id: Option<String>,
    /// New canonical_occurrence_date to set. `Patch::Unset` = don't touch,
    /// `Patch::Clear` = explicit NULL, `Patch::Set(v)` = new value.
    pub set_canonical_occurrence_date: lorvex_domain::Patch<String>,
    /// New due_date to set (None = don't touch).
    pub set_due_date: Option<String>,
    /// Whether to clear recurrence_group_id (on Disable).
    pub clear_recurrence_group_id: bool,
    /// Whether to clear canonical_occurrence_date (on Disable).
    pub clear_canonical_occurrence_date: bool,
    /// Whether to clear recurrence_exceptions (on UpdateRule or Disable — old
    /// EXDATE dates may not be valid occurrences of the new rule).
    pub clear_recurrence_exceptions: bool,
}

/// Current recurrence state of a task (read from DB before applying transition).
pub struct RecurrenceState {
    pub recurrence: Option<String>,
    pub recurrence_group_id: Option<String>,
    pub canonical_occurrence_date: Option<String>,
    pub due_date: Option<String>,
    pub due_time: Option<String>,
}

/// Plan the recurrence config transition given old state and the new recurrence value.
///
/// `new_recurrence`: the recurrence value being written (Some(rule) or Some(None)/None to clear).
/// `today`: timezone-aware today string for fallback when due_date is missing.
///
/// Returns the transition type and all column actions to apply.
pub fn plan_recurrence_transition(
    old: &RecurrenceState,
    new_recurrence: Option<&str>,
    today: &str,
) -> (RecurrenceTransition, RecurrenceColumnActions) {
    let old_has_recurrence = old.recurrence.as_deref().is_some_and(|r| !r.is_empty());
    let new_has_recurrence = new_recurrence.is_some_and(|r| !r.is_empty());

    if !old_has_recurrence && new_has_recurrence {
        // Enable: NULL → non-NULL
        let anchor = old.due_date.clone().unwrap_or_else(|| today.to_string());
        let actions = RecurrenceColumnActions {
            set_recurrence_group_id: Some(lorvex_domain::new_entity_id_string()),
            set_canonical_occurrence_date: lorvex_domain::Patch::Set(anchor.clone()),
            set_due_date: old.due_date.is_none().then_some(anchor),
            clear_recurrence_group_id: false,
            clear_canonical_occurrence_date: false,
            clear_recurrence_exceptions: false,
        };
        (RecurrenceTransition::Enable, actions)
    } else if old_has_recurrence && new_has_recurrence {
        // UpdateRule: change the rule, keep series identity and anchor.
        // Clear exceptions — old EXDATE dates may not be valid occurrences of the new rule.
        let actions = RecurrenceColumnActions {
            set_recurrence_group_id: None,
            set_canonical_occurrence_date: lorvex_domain::Patch::Unset,
            set_due_date: None,
            clear_recurrence_group_id: false,
            clear_canonical_occurrence_date: false,
            clear_recurrence_exceptions: true,
        };
        (RecurrenceTransition::UpdateRule, actions)
    } else if old_has_recurrence && !new_has_recurrence {
        // Disable: end the active series
        let actions = RecurrenceColumnActions {
            set_recurrence_group_id: None,
            set_canonical_occurrence_date: lorvex_domain::Patch::Unset,
            set_due_date: None,
            clear_recurrence_group_id: true,
            clear_canonical_occurrence_date: true,
            clear_recurrence_exceptions: true,
        };
        (RecurrenceTransition::Disable, actions)
    } else {
        // NoChange: both NULL
        let actions = RecurrenceColumnActions {
            set_recurrence_group_id: None,
            set_canonical_occurrence_date: lorvex_domain::Patch::Unset,
            set_due_date: None,
            clear_recurrence_group_id: false,
            clear_canonical_occurrence_date: false,
            clear_recurrence_exceptions: false,
        };
        (RecurrenceTransition::NoChange, actions)
    }
}

/// Plan column actions for duplicating a recurring task.
///
/// Creates a new independent series with the source's current due_date as anchor.
pub fn plan_duplicate_recurrence(source: &RecurrenceState) -> RecurrenceColumnActions {
    let has_recurrence = source.recurrence.as_deref().is_some_and(|r| !r.is_empty());
    if !has_recurrence {
        return RecurrenceColumnActions {
            set_recurrence_group_id: None,
            set_canonical_occurrence_date: lorvex_domain::Patch::Unset,
            set_due_date: None,
            clear_recurrence_group_id: false,
            clear_canonical_occurrence_date: false,
            clear_recurrence_exceptions: false,
        };
    }

    let canonical_anchor = match source.due_date.clone() {
        Some(date) => lorvex_domain::Patch::Set(date),
        None => lorvex_domain::Patch::Clear,
    };
    RecurrenceColumnActions {
        set_recurrence_group_id: Some(lorvex_domain::new_entity_id_string()),
        set_canonical_occurrence_date: canonical_anchor,
        set_due_date: None, // keep source due_date as-is
        clear_recurrence_group_id: false,
        clear_canonical_occurrence_date: false,
        clear_recurrence_exceptions: true, // new series starts fresh
    }
}

// ---------------------------------------------------------------------------
// DB-backed load + apply — the single execution path for all surfaces
// ---------------------------------------------------------------------------

use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

/// Load the current recurrence state of a task from the database.
fn load_recurrence_state(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<RecurrenceState, rusqlite::Error> {
    conn.query_row(
        "SELECT recurrence, recurrence_group_id, canonical_occurrence_date, due_date, due_time FROM tasks WHERE id = ?1",
        params![task_id],
        |row| Ok(RecurrenceState {
            recurrence: row.get(0)?,
            recurrence_group_id: row.get(1)?,
            canonical_occurrence_date: row.get(2)?,
            due_date: row.get(3)?,
            due_time: row.get(4)?,
        }),
    )
}

/// Combined due-date/due-time patch carried with recurrence config writes.
///
/// Each field is a [`lorvex_domain::Patch<String>`] with the canonical
/// three-state semantics (`Unset` / `Clear` / `Set`). The wrapper
/// exists only to keep the (due_date, due_time) pair grouped at call
/// sites — there is no extra invariant beyond what `Patch` already
/// encodes.
pub struct DueAtPatch {
    pub due_date: lorvex_domain::Patch<String>,
    pub due_time: lorvex_domain::Patch<String>,
}

impl DueAtPatch {
    pub const fn new(
        due_date: lorvex_domain::Patch<String>,
        due_time: lorvex_domain::Patch<String>,
    ) -> Self {
        Self { due_date, due_time }
    }

    pub const fn not_present() -> Self {
        Self {
            due_date: lorvex_domain::Patch::Unset,
            due_time: lorvex_domain::Patch::Unset,
        }
    }
}

/// Error from the shared recurrence owner (domain error, not DB error).
#[derive(Debug)]
pub enum RecurrenceChangeError {
    /// Clearing due_date on a task that will remain recurring.
    ClearDueDateOnRecurring,
    /// The effective patch leaves due_time set while due_date is absent.
    DueTimeWithoutDueDate,
    /// Database error.
    Db(rusqlite::Error),
    /// rollback-side failure from
    /// `with_immediate_transaction` — the closure's primary error
    /// already propagated; this variant carries the secondary
    /// rollback-failed message so it doesn't get swallowed.
    TransactionWrap(String),
    /// the LWW gate `version_param > tasks.version`
    /// rejected the UPDATE because a peer envelope landed between
    /// the boundary's HLC mint and our write. Caller must re-stamp
    /// HLC and retry. Mirrors `StoreError::StaleVersion`.
    StaleVersion { task_id: String },
}

impl std::fmt::Display for RecurrenceChangeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ClearDueDateOnRecurring => write!(f, "recurring tasks must have a due_date"),
            Self::DueTimeWithoutDueDate => write!(
                f,
                "due_time without due_date is invalid: a clock time requires a calendar day"
            ),
            Self::Db(e) => write!(f, "{e}"),
            Self::TransactionWrap(msg) => write!(f, "transaction wrapper failure: {msg}"),
            Self::StaleVersion { task_id } => write!(
                f,
                "stale version on task {task_id}: peer envelope landed between HLC mint \
                 and recurrence_config UPDATE — re-stamp HLC and retry"
            ),
        }
    }
}

impl std::error::Error for RecurrenceChangeError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Db(e) => Some(e),
            _ => None,
        }
    }
}

impl From<rusqlite::Error> for RecurrenceChangeError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Db(e)
    }
}

impl From<lorvex_store::StoreError> for RecurrenceChangeError {
    fn from(e: lorvex_store::StoreError) -> Self {
        match e {
            lorvex_store::StoreError::Sql(err) => Self::Db(err),
            other => Self::TransactionWrap(other.to_string()),
        }
    }
}

/// required by `with_immediate_transaction`'s
/// `E: From<String>` bound so the helper can lift any rollback-side
/// failure (a stringified message constructed inside the transaction
/// wrapper) into this error type. The Db variant doesn't fit a raw
/// string, so route it through a dedicated `TransactionWrap` arm.
impl From<String> for RecurrenceChangeError {
    fn from(message: String) -> Self {
        Self::TransactionWrap(message)
    }
}

/// Atomically apply a recurrence patch with an LWW-gated UPDATE.
///
/// Single shared owner for the combined `{recurrence, due_date,
/// recurrence_group_id, canonical_occurrence_date}` patch semantics —
/// all surfaces delegate here, with no surface-local recurrence /
/// due_date logic.
///
/// Atomicity: the `load_recurrence_state` SELECT → plan → UPDATE
/// sequence is a read-then-write window in which a concurrent peer
/// write would otherwise be overwritten by stale planned state. The
/// function self-wraps via `with_immediate_transaction` when invoked
/// on an autocommit connection (`conn.is_autocommit()`), so every
/// caller — direct or transitive — runs the load-plan-write under a
/// single immediate transaction. Callers that already hold a tx
/// (Tauri commands wrap with `with_immediate_transaction`, MCP uses
/// `with_savepoint*`, the CLI lifecycle layer wraps too) hit the
/// no-op branch.
///
/// Returns a domain error (not a DB CHECK violation) for invalid
/// combinations like clearing due_date on a task that remains
/// recurring.
///
/// Threads `(version, now)` through the planner so the single
/// emitted UPDATE writes the planner's column actions, the new
/// recurrence value, AND advances `tasks.version` / `tasks.updated_at`
/// — gated on `?N > tasks.version` so a peer envelope landing
/// concurrently cannot be silently clobbered. The three callers
/// (Tauri update, MCP update_task, MCP set_recurrence) all delegate
/// here so the LWW guard lives in one place; an open-coded re-stamp
/// UPDATE per caller without the guard would silently lose the
/// peer's recurrence-clear or rule-change envelope whenever a caller
/// forgot to compensate.
///
/// Returns `RecurrenceChangeError::StaleVersion` when the LWW gate
/// rejects the UPDATE. Boundary callers must re-stamp HLC and retry,
/// matching how `apply_task_update` surfaces stale-version losses.
pub fn apply_recurrence_change(
    conn: &Connection,
    task_id: &TaskId,
    recurrence_patch: lorvex_domain::Patch<String>,
    due_patch: DueAtPatch,
    today: &str,
    version: &str,
    now: &str,
) -> Result<RecurrenceTransition, RecurrenceChangeError> {
    if conn.is_autocommit() {
        return lorvex_store::transaction::with_immediate_transaction::<_, RecurrenceChangeError>(
            conn,
            |c| {
                apply_recurrence_change_inner(
                    c,
                    task_id,
                    recurrence_patch,
                    due_patch,
                    today,
                    version,
                    now,
                )
            },
        );
    }
    apply_recurrence_change_inner(
        conn,
        task_id,
        recurrence_patch,
        due_patch,
        today,
        version,
        now,
    )
}

fn apply_recurrence_change_inner(
    conn: &Connection,
    task_id: &TaskId,
    recurrence_patch: lorvex_domain::Patch<String>,
    due_patch: DueAtPatch,
    today: &str,
    version: &str,
    now: &str,
) -> Result<RecurrenceTransition, RecurrenceChangeError> {
    use lorvex_domain::Patch;
    let mut old = load_recurrence_state(conn, task_id)?;

    // Apply due_date patch to the effective state.
    match &due_patch.due_date {
        Patch::Set(new_due) => {
            old.due_date = Some(new_due.clone());
        }
        Patch::Clear => {
            old.due_date = None;
        }
        Patch::Unset => {}
    }
    match &due_patch.due_time {
        Patch::Set(new_time) => {
            old.due_time = Some(new_time.clone());
        }
        Patch::Clear => {
            old.due_time = None;
        }
        Patch::Unset => {}
    }

    // Determine the effective new_recurrence for the planner.
    let new_recurrence: Option<&str> = match &recurrence_patch {
        Patch::Set(rule) => Some(rule.as_str()),
        Patch::Clear => None,
        Patch::Unset => {
            // Not changing recurrence — use current DB value for validation.
            old.recurrence.as_deref()
        }
    };

    // Only plan recurrence transitions when recurrence is actually being changed.
    let (transition, actions) = if recurrence_patch.is_unset() {
        (
            RecurrenceTransition::NoChange,
            RecurrenceColumnActions {
                set_recurrence_group_id: None,
                set_canonical_occurrence_date: Patch::Unset,
                set_due_date: None,
                clear_recurrence_group_id: false,
                clear_canonical_occurrence_date: false,
                clear_recurrence_exceptions: false,
            },
        )
    } else {
        plan_recurrence_transition(&old, new_recurrence, today)
    };
    let final_due_date = actions.set_due_date.as_ref().or(old.due_date.as_ref());
    let final_due_time = old.due_time.as_ref();

    // Domain validation: recurring task must have due_date.
    let effective_recurring = new_recurrence.is_some_and(|r| !r.is_empty());
    if effective_recurring && final_due_date.is_none() {
        return Err(RecurrenceChangeError::ClearDueDateOnRecurring);
    }
    lorvex_domain::time::DueAt::from_optional_str_pair(
        final_due_date.map(String::as_str),
        final_due_time.map(String::as_str),
    )
    .map_err(|_| RecurrenceChangeError::DueTimeWithoutDueDate)?;

    let mut set_clauses: Vec<&str> = Vec::new();
    let mut values: Vec<&dyn rusqlite::types::ToSql> = Vec::new();

    // Write recurrence column only if it's in the patch.
    match &recurrence_patch {
        Patch::Set(rule) => {
            set_clauses.push("recurrence = ?");
            values.push(rule);
        }
        Patch::Clear => {
            set_clauses.push("recurrence = NULL");
        }
        Patch::Unset => {} // don't touch recurrence column
    }

    // Apply planner actions for supplementary fields.
    if let Some(ref gid) = actions.set_recurrence_group_id {
        set_clauses.push("recurrence_group_id = ?");
        values.push(gid);
    }
    if actions.clear_recurrence_group_id {
        set_clauses.push("recurrence_group_id = NULL");
    }
    match &actions.set_canonical_occurrence_date {
        lorvex_domain::Patch::Set(date) => {
            set_clauses.push("canonical_occurrence_date = ?");
            values.push(date);
        }
        lorvex_domain::Patch::Clear => {
            set_clauses.push("canonical_occurrence_date = NULL");
        }
        lorvex_domain::Patch::Unset => {}
    }
    if actions.clear_canonical_occurrence_date {
        set_clauses.push("canonical_occurrence_date = NULL");
    }
    // `clear_recurrence_exceptions` is handled after the UPDATE via
    // the `task_recurrence_exceptions` child table. The flag
    // is still part of the planner's output so callers can express
    // intent at the action layer; the actual rewrite happens
    // alongside the version bump below.
    if let Some(ref due) = actions.set_due_date {
        set_clauses.push("due_date = ?");
        values.push(due);
    }
    // If the caller explicitly set or cleared due_date and the planner didn't
    // already handle it, include it in the UPDATE.
    if actions.set_due_date.is_none() {
        match &due_patch.due_date {
            Patch::Set(val) => {
                set_clauses.push("due_date = ?");
                values.push(val);
            }
            Patch::Clear => {
                set_clauses.push("due_date = NULL");
            }
            Patch::Unset => {}
        }
    }
    match &due_patch.due_time {
        Patch::Set(val) => {
            set_clauses.push("due_time = ?");
            values.push(val);
        }
        Patch::Clear => {
            set_clauses.push("due_time = NULL");
        }
        Patch::Unset => {}
    }

    // Emit ONE atomic LWW-gated UPDATE that writes every column the
    // planner produced + the new recurrence value + `version` +
    // `updated_at`, gated on `version_param > version`. Threading
    // `(version, now)` here makes the planner the single owner of
    // the recurrence write. Skipping version/updated_at would force
    // every caller to emit a separate re-stamp UPDATE that often
    // missed the LWW gate.
    //
    // We always emit the UPDATE — even when `set_clauses` is empty
    // (`Patch::Unset` recurrence + `Patch::Unset` due_date +
    // a no-op planner) — because the boundary caller asked for a
    // version bump on this row and the audit changelog / outbox
    // shape relies on the row's `version` column matching the
    // outbox envelope. The bare `version + updated_at` UPDATE is
    // cheap.
    set_clauses.push("version = ?");
    values.push(&version);
    set_clauses.push("updated_at = ?");
    values.push(&now);
    values.push(&task_id);
    values.push(&version);
    let sql = format!(
        "UPDATE tasks SET {} WHERE id = ? AND ? > version",
        set_clauses.join(", ")
    );
    let rows = conn.execute(&sql, values.as_slice())?;
    if rows != 0 && actions.clear_recurrence_exceptions {
        // EXDATE list lives in `task_recurrence_exceptions`.
        // Drop every row for this task; the planner already gates
        // this branch behind the rule-change actions that reset the
        // exception set.
        lorvex_store::recurrence_exceptions::replace_task_exceptions(conn, task_id.as_str(), &[])?;
    }
    if rows == 0 {
        // Distinguish "row missing" (the recurrence helper read it
        // moments ago, so this should be impossible inside the
        // transaction) from "LWW gate refused us". The latter is
        // the typical case when a peer envelope landed between the
        // boundary's HLC mint and our UPDATE; surface as
        // `StaleVersion` so the caller can re-stamp + retry.
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM tasks WHERE id = ?1 AND archived_at IS NULL",
                rusqlite::params![task_id],
                |_| Ok(true),
            )
            .unwrap_or(false);
        if exists {
            return Err(RecurrenceChangeError::StaleVersion {
                task_id: task_id.to_string(),
            });
        }
    }

    Ok(transition)
}

#[cfg(test)]
mod tests;
