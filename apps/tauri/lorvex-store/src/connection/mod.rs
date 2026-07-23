//! Database connection helpers.
//!
//! Every connection opened through this module has:
//! - WAL journal mode for concurrent reads
//! - Foreign keys enforced
//! - Busy timeout for write contention
//! - All migrations applied

use rusqlite::Connection;
use std::path::Path;

use crate::migration::apply_migrations;
use crate::repositories::task::checklist::promote_markdown_task_checklists;
use crate::schema::all_migrations;

/// Errors that can occur when opening a database.
#[derive(Debug)]
pub enum OpenError {
    /// Failed to create the parent directory for the database file.
    CreateDir(std::io::Error),
    /// Failed to open the SQLite connection.
    Sqlite(rusqlite::Error),
    /// Failed to apply migrations.
    Migration(crate::migration::MigrationError),
    /// Failed to run store-level startup maintenance.
    Store(crate::error::StoreError),
}

impl std::fmt::Display for OpenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OpenError::CreateDir(e) => write!(f, "failed to create db directory: {e}"),
            OpenError::Sqlite(e) => write!(f, "SQLite error: {e}"),
            OpenError::Migration(e) => write!(f, "migration error: {e}"),
            OpenError::Store(e) => write!(f, "store error: {e}"),
        }
    }
}

impl std::error::Error for OpenError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            OpenError::CreateDir(e) => Some(e),
            OpenError::Sqlite(e) => Some(e),
            OpenError::Migration(e) => Some(e),
            OpenError::Store(e) => Some(e),
        }
    }
}

impl From<rusqlite::Error> for OpenError {
    fn from(e: rusqlite::Error) -> Self {
        OpenError::Sqlite(e)
    }
}

impl From<crate::migration::MigrationError> for OpenError {
    fn from(e: crate::migration::MigrationError) -> Self {
        OpenError::Migration(e)
    }
}

impl From<crate::error::StoreError> for OpenError {
    fn from(e: crate::error::StoreError) -> Self {
        OpenError::Store(e)
    }
}

/// Open the database at the platform-default path.
///
/// Resolves the path via [`lorvex_runtime::resolve_db_location_details`],
/// creates the parent directory if needed, applies PRAGMAs and migrations.
pub fn open_db() -> Result<Connection, OpenError> {
    let location = lorvex_runtime::resolve_db_location_details();
    let conn = open_db_at_path(&location.resolved_path)?;
    persist_db_location_diagnostics(&conn, &location.diagnostics);
    Ok(conn)
}

pub fn persist_pending_db_location_diagnostics(conn: &Connection) {
    persist_db_location_diagnostics(conn, &lorvex_runtime::take_db_location_diagnostics());
}

pub fn persist_db_location_diagnostics(
    conn: &Connection,
    diagnostics: &[lorvex_runtime::DbLocationDiagnostic],
) {
    for diagnostic in diagnostics {
        let source = format!("store.db_locator.{}", diagnostic.code.as_str());
        crate::error::log::append_error_log_best_effort(
            conn,
            &source,
            &diagnostic.message,
            diagnostic.details.as_deref(),
            Some(diagnostic.level),
        );
    }
}

/// Open the database at a specific file path.
///
/// Creates the parent directory if it does not exist.
pub fn open_db_at_path(path: &Path) -> Result<Connection, OpenError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(OpenError::CreateDir)?;
    }

    let conn = Connection::open(path)?;
    apply_standard_pragmas(&conn)?;
    apply_migrations(&conn, &all_migrations())?;
    reconcile_projections(&conn)?;
    promote_markdown_task_checklists(&conn)?;

    Ok(conn)
}

/// Open an in-memory database — useful for tests.
///
/// Applies PRAGMAs and all migrations so the schema is fully available.
///
/// the migration + reconcile + checklist-promote passes
/// dominate the cost of every test that needs a fresh DB. We pay them
/// **once** by building a cached source DB inside a process-wide
/// `OnceLock`, then `Connection::backup`-clone its pages into the
/// caller's fresh `Connection`. The clone is an O(N) memcpy at the
/// SQLite-page layer (no SQL re-execution), so the per-call cost
/// drops from the full migration suite (~2-4 ms / call on a warm
/// build) to a single backup pass (~0.2-0.4 ms / call). With 80+
/// callers across the test suite — many of which open the DB twice
/// (export source + import target) — this is the win called out by
/// M1.
///
/// gated behind `cfg(any(test, feature =
/// "test-support"))` so production binaries cannot reach the five
/// chained `.expect()` calls in the cached-schema initializer
/// (`open_in_memory`, `apply_standard_pragmas`, `apply_migrations`,
/// `reconcile_projections`, `promote_markdown_task_checklists`).
/// Each of those expects encodes a "this only happens on a fresh
/// in-memory DB during the first test" invariant; in production the
/// migration-failure path is the persistent-DB
/// `open_db_at_path` -> `OpenError` chain, not a panic. Downstream
/// crates that need the helper for tests already opt into the
/// `test-support` feature in their `[dev-dependencies]` block.
#[cfg(any(test, feature = "test-support"))]
pub fn open_db_in_memory() -> Result<Connection, OpenError> {
    let mut conn = Connection::open_in_memory()?;
    apply_standard_pragmas(&conn)?;
    clone_cached_test_schema(&mut conn)?;
    Ok(conn)
}

/// Build the canonical post-migration in-memory schema once per
/// process and reuse it via SQLite's online-backup API.
///
/// Returns a borrowed reference to the cached source connection so
/// `Connection::backup` can copy its pages into the caller's fresh
/// in-memory DB. The cache is a `OnceLock` so the first caller pays
/// the migration cost and every subsequent caller pays only the
/// backup-clone cost.
///
/// `Connection` is `!Sync` but we only ever **read** from the
/// cached connection (the backup API takes `&Connection` for the
/// source). The `OnceLock` provides `Send + Sync` safe access to the
/// initialization slot, and we hand out only `&Connection` borrows.
/// Concurrent backups from the same source are safe: SQLite's
/// online-backup API serializes through the source's b-tree pager.
#[cfg(any(test, feature = "test-support"))]
fn clone_cached_test_schema(dst: &mut Connection) -> Result<(), OpenError> {
    use std::sync::OnceLock;

    // The cached source DB is built once and then read from
    // concurrently by every backup-clone caller. Wrap in a `Mutex`
    // so the source's internal pager state stays single-threaded
    // even though the rusqlite `Connection` type is `!Sync`.
    static CACHED_SCHEMA: OnceLock<std::sync::Mutex<Connection>> = OnceLock::new();

    let cached = CACHED_SCHEMA.get_or_init(|| {
        let conn = Connection::open_in_memory().expect("cache: open_in_memory");
        apply_standard_pragmas(&conn).expect("cache: apply_standard_pragmas");
        apply_migrations(&conn, &all_migrations()).expect("cache: apply_migrations");
        reconcile_projections(&conn).expect("cache: reconcile_projections");
        promote_markdown_task_checklists(&conn).expect("cache: promote_markdown_task_checklists");
        std::sync::Mutex::new(conn)
    });

    // the
    // `unwrap_or_else(into_inner)` poison recovery is intentional.
    // The cached schema connection is read-only from this site —
    // we hand `&src_guard` to `Backup::new`, which only walks the
    // source pager — so a panic inside any prior caller's backup
    // step (rare, but possible if rusqlite hits an unrecoverable
    // pager condition) cannot leave the cached connection in a
    // partially-mutated state. The poison flag is collateral
    // damage from the panic, not a signal that the cached state is
    // corrupt; recovering with `into_inner` keeps test parallelism
    // working after a single test panics.
    let src_guard = cached
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let backup = rusqlite::backup::Backup::new(&src_guard, dst)?;
    // Copy in a single page-batch chunk; we deliberately pick a
    // page count larger than any realistic post-migration source DB
    // (the schema fits in well under a thousand pages today) so the
    // backup completes in one `step` call.
    //
    // `Backup::run_to_completion` panics
    // inside rusqlite on `pages_per_step <= 0`. The literal `10_000`
    // is safe today, but a future tweak that swaps in a `usize` /
    // arithmetic / config-derived value is one bad subtraction away
    // from a non-positive argument. Type the constant as
    // `NonZeroI32` so the contract is enforced at construction time
    // (compile-time `unwrap` on a positive literal) and surface it
    // as a named binding so a future reader sees the invariant
    // before they see the call site.
    const PAGES_PER_STEP: std::num::NonZeroI32 = match std::num::NonZeroI32::new(10_000) {
        Some(n) => n,
        None => unreachable!(),
    };
    backup.run_to_completion(PAGES_PER_STEP.get(), std::time::Duration::ZERO, None)?;
    Ok(())
}

/// Ensure every derived projection's triggers exist on `conn`. Runs on
/// every DB open so a crash that interrupted a maintenance-mode window
/// (DROP TRIGGER without the follow-up CREATE TRIGGER) self-heals on
/// the next launch. No-op on a healthy DB (all trigger DDL is
/// `CREATE TRIGGER IF NOT EXISTS`).
///
/// Visibility is `pub(crate)` so `ConnectionPool::new` (the MCP
/// writer path) runs the same reconciliation. Without this step on
/// the MCP path, agent-first installs that create the DB through
/// the MCP binary would silently ship without FTS trigger
/// coverage.
pub(crate) fn reconcile_projections(conn: &Connection) -> Result<(), rusqlite::Error> {
    let registry = crate::projection::ProjectionRegistry::default_projections();
    registry.ensure_triggers_installed(conn)
}

/// Canonical PRAGMA block shared by every binary that opens the app's
/// SQLite file (Tauri app, MCP server, CLI).
///
/// each binary maintained its own copy and drifted — the
/// MCP server omitted `auto_vacuum = INCREMENTAL` and
/// `temp_store = MEMORY`. `auto_vacuum` is set at DB-creation time, so
/// whichever binary created the file won the mode permanently; an
/// agent-first flow that opened the DB via the MCP binary first
/// created a non-incremental DB, breaking the app's periodic
/// `incremental_vacuum(1000)` pass forever. `temp_store` is
/// connection-scoped and caused the MCP server to leak temp B-trees
/// to disk on crash.
///
/// PRAGMA rationale:
///
/// * `auto_vacuum = INCREMENTAL` lets SQLite reclaim pages freed by
///   tombstone / changelog / FTS reindex work. Without it, the .sqlite
///   file grows 2-5× its live footprint over a multi-month session
///   and only shrinks on a manual `VACUUM`. Must run BEFORE the schema
///   is created; no-op on an already-initialized DB, so new installs
///   get the incremental mode and upgrading installs keep whatever
///   they had.
/// * `wal_autocheckpoint = 1000` is set explicitly so a future SQLite
///   default change cannot silently shift our checkpoint cadence.
///   1000 pages matches the historical SQLite default the app was
///   tuned against; pairs with `journal_mode = WAL` and the periodic
///   `wal_checkpoint(TRUNCATE)` in `run_periodic_maintenance`.
/// * `temp_store = MEMORY` keeps temp B-trees out of the user's disk
///   — noticeably faster and avoids leaving temp files behind if the
///   app crashes mid-ORDER-BY.
///
/// IMPORTANT: `PRAGMA auto_vacuum` must be set BEFORE the DB is first
/// written — switching modes later requires a full VACUUM. It must
/// also come BEFORE `journal_mode = WAL` because journal-mode changes
/// trigger a header page write that locks auto_vacuum.
pub fn apply_standard_pragmas(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute_batch(
        "PRAGMA auto_vacuum = INCREMENTAL;
         PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA foreign_keys = ON;
         PRAGMA busy_timeout = 5000;
         PRAGMA cache_size = -8192;
         PRAGMA temp_store = MEMORY;
         PRAGMA wal_autocheckpoint = 1000;",
    )
}

/// Run the heavier maintenance passes that aren't safe on the hot
/// startup path: incremental-vacuum page reclamation, optimizer stats
/// refresh, FTS index compaction, and an explicit WAL truncate.
///
/// caller should invoke this from the app's periodic
/// retention-cleanup cron (every ~6h), not from every DB open. Each
/// pass is bounded and resumable; no lock is held longer than a single
/// statement.
pub fn run_periodic_maintenance(conn: &Connection) -> Result<(), rusqlite::Error> {
    // Refresh query-planner stats — cheap and helps the hot queries
    // that just got their indexes unwrapped from `datetime(col)` per
    //.
    conn.execute_batch("PRAGMA optimize;")?;
    // Reclaim up to 1000 pages per pass so a big sync-tombstone GC
    // doesn't leave the file bloated indefinitely. SQLite serializes
    // the page moves; 1000 pages is sub-second on local storage.
    conn.execute_batch("PRAGMA incremental_vacuum(1000);")?;
    // Compact the FTS5 indexes — accumulated inserts/deletes from
    // task mutations leave fragmented segments. The
    // `calendar_events_fts` SQL lives in
    // [`crate::repositories::fts::calendar`] (#3281).
    conn.execute_batch("INSERT INTO tasks_fts(tasks_fts) VALUES('optimize');")?;
    crate::repositories::fts::calendar::optimize(conn)?;
    // Truncate the WAL file so the next writer doesn't inherit a
    // multi-MB tail. Best-effort: don't fail maintenance on a busy
    // DB.
    //
    // Surface the failure to `error_logs` at debug level rather
    // than swallowing it via `let _ = ...`. The operation is still
    // best-effort, but a recurring checkpoint failure (concurrent
    // writer, disk error, exclusive lock contention) MUST leave a
    // diagnostic trace so Settings → Diagnostics sees recurring
    // failures and an operator can correlate them with
    // bloat.
    if let Err(e) = conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);") {
        crate::error::log::append_error_log_best_effort(
            conn,
            "store.maintenance.wal_checkpoint",
            &format!("wal_checkpoint(TRUNCATE) failed: {e}"),
            None,
            Some("debug"),
        );
    }
    Ok(())
}

/// Run `PRAGMA quick_check` and `PRAGMA foreign_key_check` on the
/// connection and return a list of problems, one per line. An empty
/// `Vec` means the DB looks healthy at page-level and every FK is
/// satisfied.
///
/// Run on app startup so a partially-corrupted SQLite file (disk
/// failure, power loss outside WAL coverage, OS truncation) is
/// detected eagerly rather than surfacing as sporadic "database disk
/// image is malformed" errors when specific queries touch bad pages.
/// Callers are
/// expected to write any findings to `error_logs` and, if running
/// in an interactive context, surface a guided restore flow. We
/// deliberately return results instead of erroring the connection
/// open so the app can still reach the UI layer that shows the
/// diagnostic — blocking startup on a transient `foreign_key_check`
/// hit would brick the app and defeat the "show the user what to
/// do" goal the audit called out.
///
/// `quick_check` is the cheap page-level variant (no index cross-
/// checks). On a ~50 MB Lorvex database it runs in well under a
/// second; safe to call from the 6-hour periodic maintenance cron
/// and from the first-post-migrations startup hook.
pub fn run_integrity_check(conn: &Connection) -> Result<Vec<String>, rusqlite::Error> {
    let mut findings = Vec::new();

    let mut stmt = conn.prepare("PRAGMA quick_check;")?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
    for row in rows {
        let line = row?;
        if line != "ok" {
            findings.push(format!("quick_check: {line}"));
        }
    }
    drop(stmt);

    let mut fk_stmt = conn.prepare("PRAGMA foreign_key_check;")?;
    // Columns: (table, rowid, parent, fkid). Serialize for log legibility.
    let fk_rows = fk_stmt.query_map([], |row| {
        let table: String = row.get(0)?;
        let rowid: Option<i64> = row.get(1)?;
        let parent: String = row.get(2)?;
        let fkid: i64 = row.get(3)?;
        Ok(format!(
            "foreign_key_check: table={table} rowid={} parent={parent} fkid={fkid}",
            rowid.map_or_else(|| "<null>".to_string(), |r| r.to_string())
        ))
    })?;
    for row in fk_rows {
        findings.push(row?);
    }

    Ok(findings)
}

#[cfg(test)]
mod tests;
