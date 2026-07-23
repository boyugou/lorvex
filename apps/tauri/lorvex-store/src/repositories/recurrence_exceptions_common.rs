//! Generic recurrence-exception engine shared by the `tasks` and
//! `calendar_events` exception repositories.
//!
//! (`task_recurrence_exceptions.rs`,
//! `calendar_event_exceptions.rs`) carried byte-identical implementations
//! that diverged only in:
//!
//! 1. The owning **table** (`tasks` vs `calendar_events`).
//! 2. The id **column** (`id`, identical in both — but the parameter is
//!    threaded for clarity).
//! 3. The column carrying the **anchor date** that the exception must be
//!    on/after and aligned to (`canonical_occurrence_date` for tasks,
//!    `start_date` for events).
//! 4. The static `ENTITY_*` naming constant used in `StoreError::NotFound`
//!    / `StoreError::StaleVersion`.
//! 5. The phrasing used in the "before anchor" validation error
//!    (`"... canonical occurrence date"` vs `"... event start date"`).
//!
//! Everything else — the LWW gate, transaction wrapping, exceptions JSON
//! parsing/sort/dedup, occurrence alignment via
//! `first_occurrence_on_or_after` — is shared verbatim. This module
//! captures the shared pipeline behind a [`ExceptionTableConfig`] value
//! that the two adapters supply at call-time, so both sites collapse
//! into ~30 lines that only declare their config and forward.

use chrono::NaiveDate;
use rusqlite::{params, Connection};

use crate::calendar_timeline::recurrence::first_occurrence_on_or_after;
use crate::error::StoreError;
use crate::transaction::with_immediate_transaction;
use lorvex_domain::time::parse_iso_date;

/// Per-table customization. Every field is `&'static str` so callers
/// build the value as a `const`, and the SQL strings are pre-rendered
/// at construction (see the `tasks` / `calendar_events` adapters) so
/// the hot path threads zero `format!` allocations. The table/column
/// names live inside `select_anchor_sql` / `bump_version_sql`
/// directly — callers MUST ensure they are safe SQL identifiers
/// (asserted via the `naming` module).
pub(crate) struct ExceptionTableConfig {
    /// Static naming constant used for `StoreError::NotFound` /
    /// `StoreError::StaleVersion` reporting.
    pub entity: &'static str,
    /// Domain noun used in error messages: "Task" or "Event".
    pub entity_noun: &'static str,
    /// Phrasing used in the "before anchor" validation error so the
    /// task adapter can read "canonical occurrence date" while the
    /// event adapter reads "event start date".
    pub anchor_label: &'static str,
    /// Pre-rendered SELECT that loads `(recurrence, exceptions_json,
    /// anchor)` for [`load_anchor_row`]. The exceptions blob is
    /// rebuilt from the per-entity child table by a correlated
    /// subquery so the validation pipeline reads the same JSON
    /// wire form it always did, while the storage is normalized.
    pub select_anchor_sql: &'static str,
    /// Pre-rendered LWW-gated `UPDATE` that touches only `version`
    /// and `updated_at` on the parent row — the exceptions list is
    /// rewritten via [`crate::recurrence_exceptions`] against the
    /// per-entity child table. Bind shape: `?1 = version`, `?2 =
    /// now`, `?3 = id`. Shared by [`add_exception`] and
    /// [`remove_exception`].
    pub bump_version_sql: &'static str,
    /// Selector identifying which child table the exception list
    /// belongs to. Drives the DELETE-then-INSERT replace through
    /// [`crate::recurrence_exceptions`].
    pub exception_owner: ExceptionOwner,
}

/// Which entity's exception child table to rewrite.
#[derive(Clone, Copy)]
pub(crate) enum ExceptionOwner {
    Task,
    CalendarEvent,
}

/// Row data loaded from the owning table for exception validation.
struct AnchorRow {
    recurrence: Option<String>,
    recurrence_exceptions: Option<String>,
    anchor: Option<String>,
}

fn load_anchor_row(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
) -> Result<AnchorRow, StoreError> {
    conn.prepare_cached(cfg.select_anchor_sql)?
        .query_row(params![id], |row| {
            Ok(AnchorRow {
                recurrence: row.get(0)?,
                recurrence_exceptions: row.get(1)?,
                anchor: row.get(2)?,
            })
        })
        .map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => StoreError::NotFound {
                entity: cfg.entity,
                id: id.to_string(),
            },
            other => StoreError::from(other),
        })
}

/// Run the LWW-gated `UPDATE` that bumps `version` / `updated_at`
/// on the parent row, then rewrite the per-entity exception child
/// table with the new set. Both [`add_exception`] and
/// [`remove_exception`] go through this helper so the StaleVersion
/// detection and the child-table replace stay coupled.
fn execute_exceptions_update(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
    new_dates: &[String],
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let rows_affected = conn
        .prepare_cached(cfg.bump_version_sql)?
        .execute(params![version, now, id])?;
    if rows_affected == 0 {
        return Err(StoreError::StaleVersion {
            entity: cfg.entity,
            id: id.to_string(),
        });
    }
    match cfg.exception_owner {
        ExceptionOwner::Task => {
            crate::recurrence_exceptions::replace_task_exceptions(conn, id, new_dates)?;
        }
        ExceptionOwner::CalendarEvent => {
            crate::recurrence_exceptions::replace_event_exceptions(conn, id, new_dates)?;
        }
    }
    Ok(())
}

/// Parse a date string in the canonical `YYYY-MM-DD` storage shape.
/// Mapped onto `StoreError::Validation` so callers see one consistent
/// error message regardless of which exceptions adapter is invoked.
fn parse_storage_date(date: &str) -> Result<NaiveDate, StoreError> {
    parse_iso_date(date).map_err(|_| StoreError::Validation(format!("invalid date format: {date}")))
}

fn validate_exception_date(
    cfg: &ExceptionTableConfig,
    row: &AnchorRow,
    id: &str,
    date: &str,
) -> Result<NaiveDate, StoreError> {
    let date_nd = parse_storage_date(date)?;

    let recurrence_json = row.recurrence.as_deref().ok_or_else(|| {
        StoreError::Validation(format!(
            "{noun} {id} is not recurring",
            noun = cfg.entity_noun
        ))
    })?;

    let anchor = row.anchor.as_deref().ok_or_else(|| {
        StoreError::Validation(format!(
            "{noun} {id} is not recurring",
            noun = cfg.entity_noun
        ))
    })?;

    let anchor_nd = parse_storage_date(anchor)?;

    if date < anchor {
        return Err(StoreError::Validation(format!(
            "exception date {date} is before {label}",
            label = cfg.anchor_label,
        )));
    }

    if first_occurrence_on_or_after(recurrence_json, anchor_nd, date_nd)
        .map_err(|e| StoreError::Validation(format!("invalid recurrence rule: {e}")))?
        != Some(date_nd)
    {
        return Err(StoreError::Validation(format!(
            "date {date} is not a valid occurrence of the recurrence pattern"
        )));
    }

    Ok(date_nd)
}

/// Add an exception to the recurrence-exceptions JSON column.
///
/// See module-level docs for the full validation contract; per-table
/// customization is supplied via [`ExceptionTableConfig`]. Wraps the
/// SELECT → mutate → UPDATE sequence in an immediate transaction so
/// concurrent writers cannot stomp each other's exception lists.
pub(crate) fn add_exception(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<String, StoreError> {
    if conn.is_autocommit() {
        with_immediate_transaction(conn, |c| {
            add_exception_inner(c, cfg, id, exception_date, version, now)
        })
    } else {
        add_exception_inner(conn, cfg, id, exception_date, version, now)
    }
}

fn add_exception_inner(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<String, StoreError> {
    if version.trim().is_empty() {
        return Err(StoreError::Validation(
            "version must not be empty".to_string(),
        ));
    }
    let row = load_anchor_row(conn, cfg, id)?;
    validate_exception_date(cfg, &row, id, exception_date)?;

    let mut exceptions =
        crate::recurrence_exceptions::parse_exception_dates(row.recurrence_exceptions.as_deref())?;
    // String comparison without allocating a fresh `to_string()` per
    // call — `.iter().any(|e| e == exception_date)` does the same
    // equality check directly on `&str`, and the compiler eliminates
    // the borrow.
    if exceptions.iter().any(|e| e == exception_date) {
        return Err(StoreError::Validation(format!(
            "Exception already exists for date {exception_date}"
        )));
    }
    exceptions.push(exception_date.to_string());
    exceptions.sort();

    let json = serde_json::to_string(&exceptions).map_err(StoreError::from)?;
    execute_exceptions_update(conn, cfg, id, &exceptions, version, now)?;
    Ok(json)
}

/// Remove an exception from the recurrence-exceptions JSON column.
pub(crate) fn remove_exception(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<Option<String>, StoreError> {
    if conn.is_autocommit() {
        with_immediate_transaction(conn, |c| {
            remove_exception_inner(c, cfg, id, exception_date, version, now)
        })
    } else {
        remove_exception_inner(conn, cfg, id, exception_date, version, now)
    }
}

fn remove_exception_inner(
    conn: &Connection,
    cfg: &ExceptionTableConfig,
    id: &str,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<Option<String>, StoreError> {
    if version.trim().is_empty() {
        return Err(StoreError::Validation(
            "version must not be empty".to_string(),
        ));
    }
    parse_storage_date(exception_date)?;

    let row = load_anchor_row(conn, cfg, id)?;
    let mut exceptions =
        crate::recurrence_exceptions::parse_exception_dates(row.recurrence_exceptions.as_deref())?;

    let before_len = exceptions.len();
    exceptions.retain(|d| d != exception_date);
    if exceptions.len() == before_len {
        return Err(StoreError::Validation(format!(
            "Date {exception_date} is not in the exceptions list"
        )));
    }

    let json_val: Option<String> = if exceptions.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&exceptions).map_err(StoreError::from)?)
    };

    execute_exceptions_update(conn, cfg, id, &exceptions, version, now)?;
    Ok(json_val)
}
