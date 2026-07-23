//! Recurrence-exception (EXDATE) storage helpers for the two canonical
//! recurring entities, `tasks` and `calendar_events`.
//!
//! EXDATE membership is normalized into per-date rows in
//! [`task_recurrence_exceptions`] and
//! [`calendar_event_recurrence_exceptions`]. Membership checks reduce
//! to a primary-key equality probe; replacement is a DELETE-then-INSERT
//! over the small per-entity set. The sync envelope wire form remains a
//! JSON array of `YYYY-MM-DD` strings, so this module also exposes:
//!
//! - [`load_task_exceptions_json`] / [`load_event_exceptions_json`] —
//!   build the JSON array string from the child rows so payload
//!   builders, exporters, and undo snapshots stay
//!   tuple-position-compatible.
//! - [`replace_task_exceptions_from_json`] /
//!   [`replace_event_exceptions_from_json`] — accept the wire-form
//!   JSON string, replace the entity's full registry. Empty / `None`
//!   JSON clears the registry. Idempotent.
//! - [`parse_exception_dates`] / [`parse_exception_dates_as_set`] —
//!   kept as the canonical decoder for code paths that receive raw
//!   JSON from a sync envelope or hand off to the recurrence
//!   expansion module.

use std::collections::HashSet;

use rusqlite::{params, Connection};

use crate::error::StoreError;

/// Parse a JSON array of date strings (`["2026-04-01","2026-04-08"]`)
/// into a `Vec<String>`. `None` and blank input both return the empty
/// vector. The error variant is `Validation` because every caller
/// treats invalid JSON here as bad-input data, not a transport
/// failure. Callers that want a different `StoreError` kind can
/// `map_err` after.
pub fn parse_exception_dates(raw: Option<&str>) -> Result<Vec<String>, StoreError> {
    let Some(raw) = raw else {
        return Ok(Vec::new());
    };
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str::<Vec<String>>(raw)
        .map_err(|e| StoreError::Validation(format!("invalid recurrence_exceptions JSON: {e}")))
}

/// `parse_exception_dates` with a `HashSet` collected at the
/// allocation boundary, so callers that only need membership testing
/// don't pay the conversion themselves.
pub fn parse_exception_dates_as_set(raw: Option<&str>) -> Result<HashSet<String>, StoreError> {
    parse_exception_dates(raw).map(|v| v.into_iter().collect())
}

/// Read every EXDATE registered against `task_id`. Rows are returned
/// in ascending date order, matching the canonical sort the JSON
/// blob carries. Returns an empty vec when no row matches; callers
/// that need to distinguish "task missing" from "task has no
/// exceptions" must check the parent row separately.
pub fn load_task_exception_dates(
    conn: &Connection,
    task_id: &str,
) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT exception_date FROM task_recurrence_exceptions \
         WHERE task_id = ?1 ORDER BY exception_date ASC",
    )?;
    let rows = stmt
        .query_map(params![task_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// Read every EXDATE registered against `event_id`. Rows are returned
/// in ascending date order, matching the canonical sort the JSON
/// blob carries.
pub fn load_event_exception_dates(
    conn: &Connection,
    event_id: &str,
) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT exception_date FROM calendar_event_recurrence_exceptions \
         WHERE event_id = ?1 ORDER BY exception_date ASC",
    )?;
    let rows = stmt
        .query_map(params![event_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// Build the JSON wire form (`["2026-04-01","2026-04-08"]`) of the
/// task's EXDATE registry. Returns `None` when the registry is empty
/// — the sync envelope treats a missing array and an empty array
/// equivalently, and preserving NULL for "no exceptions" keeps
/// payload bytes minimal and equality-roundtrip-stable.
pub fn load_task_exceptions_json(
    conn: &Connection,
    task_id: &str,
) -> Result<Option<String>, StoreError> {
    let dates = load_task_exception_dates(conn, task_id)?;
    if dates.is_empty() {
        Ok(None)
    } else {
        Ok(Some(serde_json::to_string(&dates)?))
    }
}

/// Build the JSON wire form of the event's EXDATE registry. See
/// [`load_task_exceptions_json`] for the empty-vs-missing convention.
pub fn load_event_exceptions_json(
    conn: &Connection,
    event_id: &str,
) -> Result<Option<String>, StoreError> {
    let dates = load_event_exception_dates(conn, event_id)?;
    if dates.is_empty() {
        Ok(None)
    } else {
        Ok(Some(serde_json::to_string(&dates)?))
    }
}

/// Replace the task's full EXDATE registry with the provided set.
/// Performs a single DELETE followed by per-date INSERTs in one
/// prepared statement; the registry is small (one row per
/// user-skipped occurrence) so the wholesale replace is simpler than
/// computing a diff and stays correct under concurrent writers since
/// every caller already holds the immediate transaction.
pub fn replace_task_exceptions(
    conn: &Connection,
    task_id: &str,
    dates: &[String],
) -> Result<(), StoreError> {
    conn.prepare_cached("DELETE FROM task_recurrence_exceptions WHERE task_id = ?1")?
        .execute(params![task_id])?;
    if !dates.is_empty() {
        // `INSERT OR IGNORE` collapses duplicate dates in the
        // caller-supplied set so a wire-form payload that
        // accidentally repeats an EXDATE entry still lands cleanly
        // against the `(task_id, exception_date)` primary key without
        // surfacing a `UNIQUE constraint` error to the caller.
        let mut stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO task_recurrence_exceptions (task_id, exception_date) \
             VALUES (?1, ?2)",
        )?;
        for date in dates {
            stmt.execute(params![task_id, date])?;
        }
    }
    Ok(())
}

/// Replace the event's full EXDATE registry with the provided set.
pub fn replace_event_exceptions(
    conn: &Connection,
    event_id: &str,
    dates: &[String],
) -> Result<(), StoreError> {
    conn.prepare_cached("DELETE FROM calendar_event_recurrence_exceptions WHERE event_id = ?1")?
        .execute(params![event_id])?;
    if !dates.is_empty() {
        // `INSERT OR IGNORE` deduplicates within the caller-
        // supplied set; see [`replace_task_exceptions`] for the
        // full rationale.
        let mut stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO calendar_event_recurrence_exceptions (event_id, exception_date) \
             VALUES (?1, ?2)",
        )?;
        for date in dates {
            stmt.execute(params![event_id, date])?;
        }
    }
    Ok(())
}

/// Replace the task's EXDATE registry from a wire-form JSON array.
/// `None` and blank JSON both clear the registry. Invalid JSON
/// surfaces as `StoreError::Validation` via [`parse_exception_dates`].
pub fn replace_task_exceptions_from_json(
    conn: &Connection,
    task_id: &str,
    json: Option<&str>,
) -> Result<(), StoreError> {
    let dates = parse_exception_dates(json)?;
    replace_task_exceptions(conn, task_id, &dates)
}

/// Replace the event's EXDATE registry from a wire-form JSON array.
pub fn replace_event_exceptions_from_json(
    conn: &Connection,
    event_id: &str,
    json: Option<&str>,
) -> Result<(), StoreError> {
    let dates = parse_exception_dates(json)?;
    replace_event_exceptions(conn, event_id, &dates)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::open_db_in_memory;

    #[test]
    fn replace_task_exceptions_round_trips_through_json_helper() {
        // Pin the wire-form JSON contract: write via the JSON
        // helper, read back as a Vec, and confirm the date order
        // matches the json_group_array projection used at every
        // read site.
        let conn = open_db_in_memory().unwrap();
        crate::test_support::fixtures::ListBuilder::new("list-exc").insert(&conn);
        crate::test_support::fixtures::TaskBuilder::new("task-exc")
            .list_id(Some("list-exc"))
            .insert(&conn);
        replace_task_exceptions_from_json(
            &conn,
            "task-exc",
            Some(r#"["2026-03-22","2026-03-15","2026-03-22"]"#),
        )
        .unwrap();
        let dates = load_task_exception_dates(&conn, "task-exc").unwrap();
        // Ascending order from the SELECT helper, duplicates
        // collapsed by the PK constraint.
        assert_eq!(dates, vec!["2026-03-15", "2026-03-22"]);
        let json = load_task_exceptions_json(&conn, "task-exc").unwrap();
        assert_eq!(json.as_deref(), Some(r#"["2026-03-15","2026-03-22"]"#));
    }

    #[test]
    fn replace_task_exceptions_with_empty_json_clears_registry() {
        let conn = open_db_in_memory().unwrap();
        crate::test_support::fixtures::ListBuilder::new("list-exc").insert(&conn);
        crate::test_support::fixtures::TaskBuilder::new("task-exc")
            .list_id(Some("list-exc"))
            .insert(&conn);
        replace_task_exceptions(
            &conn,
            "task-exc",
            &["2026-03-22".to_string(), "2026-03-15".to_string()],
        )
        .unwrap();
        // Clearing via `None` JSON drops every row; the helper
        // returns `None` for an empty registry.
        replace_task_exceptions_from_json(&conn, "task-exc", None).unwrap();
        assert!(load_task_exception_dates(&conn, "task-exc")
            .unwrap()
            .is_empty());
        assert_eq!(load_task_exceptions_json(&conn, "task-exc").unwrap(), None);
    }

    #[test]
    fn exdate_membership_resolves_via_primary_key_index() {
        // Pin the indexed-membership path: the EXISTS probe on
        // `task_recurrence_exceptions` must use the PK
        // `(task_id, exception_date)`, not a scan. The child-table
        // shape lets membership reduce to an index seek rather than
        // parsing a JSON blob per check.
        let conn = open_db_in_memory().unwrap();
        let plan: Vec<String> = conn
            .prepare(
                "EXPLAIN QUERY PLAN \
                 SELECT 1 FROM task_recurrence_exceptions \
                 WHERE task_id = ?1 AND exception_date = ?2",
            )
            .unwrap()
            .query_map(["task-exc", "2026-03-15"], |row| row.get::<_, String>(3))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        let plan_text = plan.join("\n");
        assert!(
            plan_text.to_uppercase().contains("SEARCH"),
            "EXDATE membership must resolve via an indexed SEARCH, not a SCAN:\n{plan_text}"
        );
    }

    #[test]
    fn parse_none_returns_empty() {
        assert!(parse_exception_dates(None).unwrap().is_empty());
    }

    #[test]
    fn parse_blank_returns_empty() {
        assert!(parse_exception_dates(Some("")).unwrap().is_empty());
        assert!(parse_exception_dates(Some("   ")).unwrap().is_empty());
    }

    #[test]
    fn parse_array_returns_dates_in_order() {
        let parsed = parse_exception_dates(Some(r#"["2026-04-01","2026-04-08"]"#)).unwrap();
        assert_eq!(parsed, vec!["2026-04-01", "2026-04-08"]);
    }

    #[test]
    fn parse_invalid_json_returns_validation_error() {
        let err = parse_exception_dates(Some("not-json")).unwrap_err();
        assert!(matches!(err, StoreError::Validation(_)));
    }

    #[test]
    fn parse_set_collapses_duplicates() {
        let set = parse_exception_dates_as_set(Some(r#"["2026-04-01","2026-04-08","2026-04-01"]"#))
            .unwrap();
        assert_eq!(set.len(), 2);
        assert!(set.contains("2026-04-01"));
        assert!(set.contains("2026-04-08"));
    }
}
