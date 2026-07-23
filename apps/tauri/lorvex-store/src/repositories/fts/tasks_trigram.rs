//! `tasks_fts_trigram` mutation helpers (#3281).
//!
//! `tasks_fts_trigram` is an external-content FTS5 table backed by
//! the SQLite-built-in `trigram` tokenizer; CJK queries hit this
//! index instead of the LIKE fallback's full-table scan (#2288).
//!
//! Because the table is external-content, a row update has to be
//! expressed as the canonical FTS5 "tombstone then re-insert" pair:
//! the `'delete'` command form removes the row's postings without
//! touching the backing `tasks` row, and a bare insert re-projects
//! the new column values.
//!
//! Every SQL string that writes to this table lives here.

use rusqlite::{params, Connection};

/// SQLite identifier for the trigram FTS5 virtual table. Use this
/// constant whenever the projection registry needs a stable name
/// (savepoint names, log breadcrumbs, registry assertions) so a
/// future rename lands in one place.
pub const TABLE_NAME: &str = "tasks_fts_trigram";

/// SQL fragment that drops the row's existing trigram postings.
///
/// Parameters (in order): `rowid`, `title`, `body`, `ai_notes`.
///
/// External-content FTS5 requires the *previous* column values for
/// the `'delete'` command — they are used to invert the postings
/// list. Passing the *new* values (or NULLs) leaks stale 3-grams
/// into the index. This is the same constraint the
/// `tasks_fts_trigram_update` trigger encodes via `old.title`,
/// `old.body`, `old.ai_notes`.
pub(crate) const TOMBSTONE_SQL: &str = "INSERT INTO tasks_fts_trigram\
    (tasks_fts_trigram, rowid, title, body, ai_notes) \
    VALUES ('delete', ?1, ?2, ?3, ?4)";

/// SQL fragment that inserts a row's trigram postings.
///
/// Parameters (in order): `rowid`, `title`, `body`, `ai_notes`.
pub(crate) const INSERT_SQL: &str = "INSERT INTO tasks_fts_trigram\
    (rowid, title, body, ai_notes) \
    VALUES (?1, ?2, ?3, ?4)";

/// Trigger DDL kept in lockstep with `001_schema.sql`. The schema
/// file is the canonical install-time source; this constant is the
/// re-install source used by
/// [`crate::projection::tasks_fts_trigram_projection`] after a
/// maintenance window. The two must stay byte-equivalent — see
/// [`assert_triggers_match_schema`](super::tests::assert_triggers_match_schema)
/// for the invariant test.
const TRIGGERS_SQL: &str = "\
CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_insert AFTER INSERT ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
    VALUES (new.rowid, new.title, new.body, new.ai_notes);
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_update AFTER UPDATE OF title, body, ai_notes ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
    VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
    INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
    VALUES (new.rowid, new.title, new.body, new.ai_notes);
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_delete AFTER DELETE ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
    VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
END;
";

/// SQL that drops every trigger that mutates `tasks_fts_trigram`.
const DROP_TRIGGERS_SQL: &str = "\
DROP TRIGGER IF EXISTS tasks_fts_trigram_insert;
DROP TRIGGER IF EXISTS tasks_fts_trigram_update;
DROP TRIGGER IF EXISTS tasks_fts_trigram_delete;";

/// SQL that fully repopulates the index from the backing `tasks`
/// table via the FTS5 `'rebuild'` command. External-content FTS5
/// supports this in a single pass — it walks the source rows and
/// re-projects every column.
const REBUILD_SQL: &str = "INSERT INTO tasks_fts_trigram(tasks_fts_trigram) VALUES('rebuild');";

/// Searchable column tuple for `tasks_fts_trigram`. Borrowed
/// values keep the helper allocation-free at the call site.
///
/// Grouping the columns into a struct (rather than four positional
/// `Option<&str>` parameters) prevents argument-order bugs —
/// the trigger DDL had to be read carefully to confirm `title`
/// preceded `body` preceded `ai_notes`. The struct field order is
/// the canonical order the FTS5 schema declares.
#[derive(Clone, Copy, Debug, Default)]
pub struct TasksTrigramColumns<'a> {
    pub title: Option<&'a str>,
    pub body: Option<&'a str>,
    pub ai_notes: Option<&'a str>,
}

/// Tombstone the row's postings without re-inserting. Use this when
/// removing a `tasks` row directly (the trigger does it for you on
/// `DELETE FROM tasks`; this helper exists for sync apply paths
/// that mutate the FTS index without going through the base table).
///
/// Pass the *previous* column values — see [`TOMBSTONE_SQL`].
pub fn tasks_fts_trigram_delete(
    conn: &Connection,
    rowid: i64,
    previous: TasksTrigramColumns<'_>,
) -> rusqlite::Result<usize> {
    conn.execute(
        TOMBSTONE_SQL,
        params![rowid, previous.title, previous.body, previous.ai_notes],
    )
}

/// Upsert a single `tasks_fts_trigram` row using the canonical
/// tombstone-then-insert idiom.
///
/// `previous` is the values currently indexed for `rowid` (
/// invert the existing postings); `next` is the values to project.
/// On a fresh insert (rowid not yet indexed) pass
/// [`TasksTrigramColumns::default()`] for `previous` — the
/// `'delete'` command is a no-op when no matching postings exist.
pub fn tasks_fts_trigram_upsert(
    conn: &Connection,
    rowid: i64,
    previous: TasksTrigramColumns<'_>,
    next: TasksTrigramColumns<'_>,
) -> rusqlite::Result<()> {
    conn.execute(
        TOMBSTONE_SQL,
        params![rowid, previous.title, previous.body, previous.ai_notes],
    )?;
    conn.execute(
        INSERT_SQL,
        params![rowid, next.title, next.body, next.ai_notes],
    )?;
    Ok(())
}

/// Install the `tasks_fts_trigram_*` triggers. Idempotent — every
/// statement uses `CREATE TRIGGER IF NOT EXISTS`.
pub fn install_triggers(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(TRIGGERS_SQL)
}

/// Drop the `tasks_fts_trigram_*` triggers. Used by the projection
/// suspend path before a bulk import / sync apply.
pub fn drop_triggers(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(DROP_TRIGGERS_SQL)
}

/// Repopulate the index from the backing table.
pub fn rebuild(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(REBUILD_SQL)
}
