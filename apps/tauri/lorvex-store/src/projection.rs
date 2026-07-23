//! Projection maintenance system.
//!
//! Derived data (FTS indexes, count caches, etc.) is maintained through a
//! registered projection system. During normal operation, triggers keep
//! projections in sync incrementally. For bulk operations (sync apply, import,
//! migration), callers enter maintenance mode to suspend triggers, perform
//! bulk writes, then exit maintenance mode to rebuild and re-enable triggers.
//!
//! ## Usage
//!
//! ```ignore
//! let registry = ProjectionRegistry::default_projections();
//! // Bulk import:
//! registry.enter_maintenance_mode(&conn)?;
//! // ... bulk inserts ...
//! registry.exit_maintenance_mode(&conn)?;
//! ```

use rusqlite::Connection;

/// One derived projection (FTS index, count cache, …).
///
/// Each projection bundles three lifecycle callbacks: `suspend` disables
/// incremental maintenance (typically by dropping triggers), `rebuild`
/// fully repopulates the projection from its source tables, and `resume`
/// re-enables incremental maintenance. The `name` is a stable identifier
/// used for SAVEPOINT names + log breadcrumbs.
#[derive(Clone, Copy)]
pub struct Projection {
    pub name: &'static str,
    pub suspend: fn(&Connection) -> Result<(), rusqlite::Error>,
    pub rebuild: fn(&Connection) -> Result<(), rusqlite::Error>,
    pub resume: fn(&Connection) -> Result<(), rusqlite::Error>,
}

/// Registry of all derived projections.
pub struct ProjectionRegistry {
    projections: Vec<Projection>,
}

impl Default for ProjectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl ProjectionRegistry {
    /// Create an empty registry.
    pub const fn new() -> Self {
        Self {
            projections: Vec::new(),
        }
    }

    /// Create a registry pre-loaded with all standard projections.
    pub fn default_projections() -> Self {
        let mut registry = Self::new();
        registry.register(tasks_fts_projection());
        registry.register(tasks_fts_trigram_projection());
        registry.register(calendar_events_fts_projection());
        registry
    }

    /// Register a new projection.
    pub fn register(&mut self, projection: Projection) {
        self.projections.push(projection);
    }

    /// Return the names of all registered projections.
    pub fn names(&self) -> Vec<&'static str> {
        self.projections.iter().map(|p| p.name).collect()
    }

    /// Suspend all projections (enter maintenance mode).
    ///
    /// Call this before bulk writes to avoid trigger overhead.
    ///
    /// # Invariant (#2863)
    ///
    /// Must be called from inside an active write transaction
    /// (`BEGIN IMMEDIATE` or equivalent). DROP TRIGGER autocommits
    /// when the connection is in autocommit mode, exposing a window
    /// where another connection's write could land on the base table
    /// without firing the FTS projection trigger — the rebuild on
    /// exit only re-INSERTs from base tables and cannot reconcile
    /// concurrent deletions, so a stale tombstone would survive in
    /// the FTS index.
    ///
    /// Debug builds panic on misuse; release builds return an
    /// `InvalidQuery` error so the caller can surface it.
    pub fn enter_maintenance_mode(&self, conn: &Connection) -> Result<(), rusqlite::Error> {
        if conn.is_autocommit() {
            debug_assert!(
                false,
                "enter_maintenance_mode called outside a write transaction \
                 — DROP TRIGGER would autocommit and break the writer-exclusion \
                 guarantee (#2863)"
            );
            return Err(rusqlite::Error::InvalidQuery);
        }
        for p in &self.projections {
            (p.suspend)(conn)?;
        }
        Ok(())
    }

    /// Idempotently re-install every projection's triggers without
    /// touching the index contents. Safe to call at DB-open time —
    /// closes, where a crash between
    /// `enter_maintenance_mode` (DROP TRIGGER, SQLite autocommit) and
    /// `exit_maintenance_mode` (CREATE TRIGGER) permanently left FTS
    /// triggers absent on the affected install, silently corrupting
    /// search until the user spotted empty results. All trigger DDL
    /// uses `CREATE TRIGGER IF NOT EXISTS`, so invocation on a healthy
    /// DB is a no-op.
    pub fn ensure_triggers_installed(&self, conn: &Connection) -> Result<(), rusqlite::Error> {
        for p in &self.projections {
            (p.resume)(conn)?;
        }
        Ok(())
    }

    /// Rebuild all projections and re-enable triggers (exit maintenance mode).
    ///
    /// Call this after bulk writes are complete.
    ///
    /// each projection's rebuild runs inside its own
    /// SAVEPOINT so a failure (disk full, OOM, FTS5 internal error)
    /// rolls back to the pre-rebuild state instead of leaving a
    /// half-emptied FTS table that resume() would then start
    /// incrementally maintaining from a broken baseline. Triggers are
    /// always re-installed afterwards — even when a rebuild failed —
    /// so subsequent writes stay incrementally indexed; the caller
    /// receives the first error so they can retry or run repair.
    pub fn exit_maintenance_mode(&self, conn: &Connection) -> Result<(), rusqlite::Error> {
        let mut first_error: Option<rusqlite::Error> = None;

        for p in &self.projections {
            // SAVEPOINT names follow SQLite identifier rules; projection
            // names are stable static strings (`tasks_fts`, etc.) so
            // direct interpolation is safe — no user input reaches here.
            let savepoint = format!("rebuild_{}", p.name);
            if let Err(e) = conn.execute_batch(&format!("SAVEPOINT {savepoint};")) {
                if first_error.is_none() {
                    first_error = Some(e);
                }
                continue;
            }

            match (p.rebuild)(conn) {
                Ok(()) => {
                    if let Err(e) = conn.execute_batch(&format!("RELEASE {savepoint};")) {
                        if first_error.is_none() {
                            first_error = Some(e);
                        }
                    }
                }
                Err(rebuild_err) => {
                    // Roll back the partial rebuild then release the
                    // savepoint frame. SQLite requires both: ROLLBACK TO
                    // restores state but leaves the savepoint active.
                    //
                    // `execute_batch(..."ROLLBACK TO ...; RELEASE ...;")`
                    // and the result discarded with `let _ = ...` —
                    // if RELEASE failed (rare; corrupted savepoint
                    // stack from an earlier panic), the frame leaked
                    // and every subsequent rebuild stacked another
                    // unreleased frame for the rest of the connection's
                    // lifetime. Run them separately so a `RELEASE`
                    // failure surfaces an `error_log` breadcrumb the
                    // operator can act on.
                    if let Err(rollback_err) =
                        conn.execute_batch(&format!("ROLLBACK TO {savepoint};"))
                    {
                        crate::error::log::append_error_log_best_effort(
                            conn,
                            "store.projection.savepoint_rollback_failed",
                            &format!(
                                "ROLLBACK TO {savepoint} failed during projection rebuild: \
                                 {rollback_err}"
                            ),
                            None,
                            Some("error"),
                        );
                    }
                    if let Err(release_err) = conn.execute_batch(&format!("RELEASE {savepoint};")) {
                        // RELEASE after ROLLBACK TO leaks the savepoint
                        // frame on failure — every future rebuild
                        // would nest inside this orphaned frame. The
                        // log below is the only signal that a future
                        // rebuild is operating in a degraded state.
                        crate::error::log::append_error_log_best_effort(
                            conn,
                            "store.projection.savepoint_release_failed",
                            &format!(
                                "RELEASE {savepoint} failed after ROLLBACK TO during projection \
                                 rebuild — savepoint frame leaks: {release_err}"
                            ),
                            None,
                            Some("error"),
                        );
                    }
                    if first_error.is_none() {
                        first_error = Some(rebuild_err);
                    }
                }
            }
        }

        for p in &self.projections {
            if let Err(e) = (p.resume)(conn) {
                if first_error.is_none() {
                    first_error = Some(e);
                }
            }
        }

        first_error.map_or(Ok(()), Err)
    }
}

// ---------------------------------------------------------------------------
// tasks_fts_projection — FTS5 full-text search for tasks
// ---------------------------------------------------------------------------

/// Tasks FTS trigger SQL installed by `tasks_fts_resume`.
/// Kept as a constant string (rather than re-parsed out of
/// `001_schema.sql`) so projection rebuilds stay self-contained and
/// visible in one place. Must stay byte-equivalent to the FTS
/// trigger block in `001_schema.sql`; a drift would mean a rebuild
/// installs a different trigger shape than the initial schema.
///
/// the trigger set now covers tag membership (`task_tags`
/// insert/delete) and tag renames (`tags.display_name` update) so the
/// 4th FTS column `tags` stays in sync with the relational source.
const TASKS_FTS_TRIGGERS_SQL: &str = r"
CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks BEGIN
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    VALUES (
        new.rowid,
        new.title,
        new.body,
        new.ai_notes,
        (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
           FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id
          WHERE tt.task_id = new.id)
    );
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_update AFTER UPDATE OF title, body, ai_notes ON tasks BEGIN
    DELETE FROM tasks_fts WHERE rowid = old.rowid;
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    VALUES (
        new.rowid,
        new.title,
        new.body,
        new.ai_notes,
        (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
           FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id
          WHERE tt.task_id = new.id)
    );
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER DELETE ON tasks BEGIN
    DELETE FROM tasks_fts WHERE rowid = old.rowid;
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_link_insert AFTER INSERT ON task_tags BEGIN
    DELETE FROM tasks_fts WHERE rowid = (SELECT rowid FROM tasks WHERE id = new.task_id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
              FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id
             WHERE tt.task_id = t.id)
      FROM tasks t WHERE t.id = new.task_id;
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_link_delete AFTER DELETE ON task_tags BEGIN
    DELETE FROM tasks_fts WHERE rowid = (SELECT rowid FROM tasks WHERE id = old.task_id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
              FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id
             WHERE tt.task_id = t.id)
      FROM tasks t WHERE t.id = old.task_id;
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_rename AFTER UPDATE OF display_name ON tags BEGIN
    DELETE FROM tasks_fts
     WHERE rowid IN (SELECT t.rowid FROM tasks t
                     JOIN task_tags tt ON tt.task_id = t.id
                    WHERE tt.tag_id = new.id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
              FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id
             WHERE tt2.task_id = t.id)
      FROM tasks t
      JOIN task_tags tt ON tt.task_id = t.id
     WHERE tt.tag_id = new.id;
END;
";

/// SQL that fully repopulates `tasks_fts` from the source tables.
/// Used by `tasks_fts_rebuild` after a maintenance-mode
/// bulk load, and by installs/tests that want a clean re-index.
///
/// `tasks_fts` is now a self-contained FTS5 table
/// (no `content='tasks'`), so the `INSERT INTO tasks_fts(tasks_fts)
/// VALUES('rebuild')` idiom — which relies on external content —
/// no longer applies. We rebuild by wiping and re-projecting.
const TASKS_FTS_REBUILD_SQL: &str = r"
DELETE FROM tasks_fts;
INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
SELECT t.rowid, t.title, t.body, t.ai_notes,
       (SELECT GROUP_CONCAT(tg.display_name, ' ' ORDER BY tg.lookup_key ASC)
          FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id
         WHERE tt.task_id = t.id)
  FROM tasks t;
";

fn tasks_fts_suspend(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        "DROP TRIGGER IF EXISTS tasks_fts_insert;
         DROP TRIGGER IF EXISTS tasks_fts_update;
         DROP TRIGGER IF EXISTS tasks_fts_delete;
         DROP TRIGGER IF EXISTS tasks_fts_tag_link_insert;
         DROP TRIGGER IF EXISTS tasks_fts_tag_link_delete;
         DROP TRIGGER IF EXISTS tasks_fts_tag_rename;",
    )
}

fn tasks_fts_rebuild(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(TASKS_FTS_REBUILD_SQL)
}

fn tasks_fts_resume(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(TASKS_FTS_TRIGGERS_SQL)
}

/// FTS5 projection for the `tasks` table (title, body, ai_notes, tags).
pub fn tasks_fts_projection() -> Projection {
    Projection {
        name: "tasks_fts",
        suspend: tasks_fts_suspend,
        rebuild: tasks_fts_rebuild,
        resume: tasks_fts_resume,
    }
}

// ---------------------------------------------------------------------------
// tasks_fts_trigram_projection — FTS5 trigram index for CJK substring search
// ---------------------------------------------------------------------------

/// FTS5 projection for the trigram virtual table.
///
/// All mutation SQL — trigger DDL, drop SQL, and the FTS5 `'rebuild'`
/// command — lives in [`crate::repositories::fts::tasks_trigram`]
/// (#3281). This wrapper only adapts the projection callback surface.
pub fn tasks_fts_trigram_projection() -> Projection {
    Projection {
        name: crate::repositories::fts::tasks_trigram::TABLE_NAME,
        suspend: crate::repositories::fts::tasks_trigram::drop_triggers,
        // External-content FTS5 supports the `'rebuild'` command — it
        // repopulates from the backing `tasks` table in a single pass.
        rebuild: crate::repositories::fts::tasks_trigram::rebuild,
        resume: crate::repositories::fts::tasks_trigram::install_triggers,
    }
}

// ---------------------------------------------------------------------------
// calendar_events_fts_projection — FTS5 full-text search for calendar events
// ---------------------------------------------------------------------------

/// FTS5 projection for the calendar-events FTS table.
///
/// All mutation SQL lives in
/// [`crate::repositories::fts::calendar`] (#3281).
pub fn calendar_events_fts_projection() -> Projection {
    Projection {
        name: crate::repositories::fts::calendar::TABLE_NAME,
        suspend: crate::repositories::fts::calendar::drop_triggers,
        rebuild: crate::repositories::fts::calendar::rebuild,
        resume: crate::repositories::fts::calendar::install_triggers,
    }
}

#[cfg(test)]
mod tests;
