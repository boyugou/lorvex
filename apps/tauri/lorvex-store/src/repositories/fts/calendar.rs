//! `calendar_events_fts` mutation helpers (#3281).
//!
//! `calendar_events_fts` is an external-content FTS5 table over the
//! `(title, description, location)` columns of `calendar_events`.
//! Single-row mutations follow the same tombstone-then-insert idiom
//! used by [`super::tasks_trigram`].

use rusqlite::{params, Connection};

/// SQLite identifier for the calendar-events FTS5 virtual table.
pub const TABLE_NAME: &str = "calendar_events_fts";

/// SQL fragment that drops the row's existing postings.
///
/// Parameters (in order): `rowid`, `title`, `description`, `location`.
///
/// External-content FTS5 inverts postings using the *previous*
/// column values — pass `old.*`, never `new.*` or NULLs.
pub(crate) const TOMBSTONE_SQL: &str = "INSERT INTO calendar_events_fts\
    (calendar_events_fts, rowid, title, description, location) \
    VALUES ('delete', ?1, ?2, ?3, ?4)";

/// SQL fragment that inserts the row's postings.
///
/// Parameters (in order): `rowid`, `title`, `description`, `location`.
pub(crate) const INSERT_SQL: &str = "INSERT INTO calendar_events_fts\
    (rowid, title, description, location) \
    VALUES (?1, ?2, ?3, ?4)";

/// Trigger DDL kept in lockstep with `001_schema.sql`. The schema
/// file is the canonical install-time source; this constant is the
/// re-install source used by
/// [`crate::projection::calendar_events_fts_projection`].
const TRIGGERS_SQL: &str = "\
CREATE TRIGGER IF NOT EXISTS calendar_events_fts_insert AFTER INSERT ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(rowid, title, description, location)
    VALUES (new.rowid, new.title, new.description, new.location);
END;

CREATE TRIGGER IF NOT EXISTS calendar_events_fts_update AFTER UPDATE OF title, description, location ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
    VALUES ('delete', old.rowid, old.title, old.description, old.location);
    INSERT INTO calendar_events_fts(rowid, title, description, location)
    VALUES (new.rowid, new.title, new.description, new.location);
END;

CREATE TRIGGER IF NOT EXISTS calendar_events_fts_delete AFTER DELETE ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
    VALUES ('delete', old.rowid, old.title, old.description, old.location);
END;
";

/// SQL that drops every `calendar_events_fts_*` trigger.
const DROP_TRIGGERS_SQL: &str = "\
DROP TRIGGER IF EXISTS calendar_events_fts_insert;
DROP TRIGGER IF EXISTS calendar_events_fts_update;
DROP TRIGGER IF EXISTS calendar_events_fts_delete;";

/// SQL that fully repopulates the index via FTS5's `'rebuild'`.
const REBUILD_SQL: &str = "INSERT INTO calendar_events_fts(calendar_events_fts) VALUES('rebuild');";

/// SQL that asks FTS5 to compact accumulated segments. Invoked on
/// the periodic-maintenance pass alongside `tasks_fts(optimize)`.
pub const OPTIMIZE_SQL: &str =
    "INSERT INTO calendar_events_fts(calendar_events_fts) VALUES('optimize');";

/// Searchable column tuple for `calendar_events_fts`. See the
/// rationale on
/// [`super::tasks_trigram::TasksTrigramColumns`] — grouping the
/// borrowed `&str` references into a struct keeps argument-order
/// drift out of every future call site.
#[derive(Clone, Copy, Debug, Default)]
pub struct CalendarEventsColumns<'a> {
    pub title: Option<&'a str>,
    pub description: Option<&'a str>,
    pub location: Option<&'a str>,
}

/// Upsert a single `calendar_events_fts` row using the canonical
/// tombstone-then-insert idiom.
pub fn calendar_events_fts_upsert(
    conn: &Connection,
    rowid: i64,
    previous: CalendarEventsColumns<'_>,
    next: CalendarEventsColumns<'_>,
) -> rusqlite::Result<()> {
    conn.execute(
        TOMBSTONE_SQL,
        params![
            rowid,
            previous.title,
            previous.description,
            previous.location
        ],
    )?;
    conn.execute(
        INSERT_SQL,
        params![rowid, next.title, next.description, next.location],
    )?;
    Ok(())
}

/// Install the `calendar_events_fts_*` triggers (idempotent).
pub fn install_triggers(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(TRIGGERS_SQL)
}

/// Drop the `calendar_events_fts_*` triggers.
pub fn drop_triggers(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(DROP_TRIGGERS_SQL)
}

/// Repopulate the index from the backing table.
pub fn rebuild(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(REBUILD_SQL)
}

/// Compact accumulated segments. Used by `run_periodic_maintenance`.
pub fn optimize(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(OPTIMIZE_SQL)
}
