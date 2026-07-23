use rusqlite::{Connection, OptionalExtension};
use std::fmt;

use super::checksum::sha256_hex;
use super::schema_audit;

/// A numbered, named SQL migration.
#[derive(Debug, Clone)]
pub struct Migration {
    /// Monotonically increasing version number (1, 2, 3, ...).
    pub version: u32,
    /// Human-readable name (e.g. "baseline", "convergence").
    pub name: String,
    /// Raw SQL to execute (may contain multiple statements).
    pub sql: String,
}

/// Errors that can occur during migration.
#[derive(Debug)]
pub enum MigrationError {
    /// A previously-applied migration has a different checksum than the one
    /// we are trying to apply. This indicates a schema drift or accidental
    /// edit of a frozen migration file.
    ChecksumMismatch {
        version: u32,
        name: String,
        expected: String,
        actual: String,
    },
    /// The database has a higher-versioned migration recorded than the
    /// binary knows about. Prior behavior was to ignore
    /// the extra rows and proceed, which let an older build silently
    /// open a newer schema — CHECK constraints from future migrations
    /// stayed in place, FTS tokenizers stayed modified, etc. — and
    /// writes would produce hard-to-diagnose constraint violations and
    /// unexplained search misses. Now we refuse to open so the user
    /// sees an actionable "your DB is newer than this build" error.
    DowngradeDetected {
        binary_max_version: u32,
        db_max_version: u32,
    },
    /// a migration is recorded as applied with a matching
    /// checksum, but one of the DDL objects it declares is missing from
    /// `sqlite_schema`. This catches the crash-recovery gap spun out of
    /// #2260 — a partial apply (or out-of-band manual repair) that left
    /// the bookkeeping row intact while its DDL side effects evaporated.
    /// The runner refuses to proceed; the caller must restore a backup,
    /// delete the corrupted DB, or re-pull from sync.
    CorruptedSchema {
        version: u32,
        name: String,
        /// SQLite object kind: `"table"`, `"index"`, `"trigger"`, or
        /// `"view"`. Included in the error so the diagnostic points at
        /// exactly which object is gone.
        missing_kind: &'static str,
        missing_object: String,
    },
    /// An error from SQLite while applying a migration or managing the
    /// schema_migrations table.
    Sql(rusqlite::Error),
    /// A migration failed and transaction cleanup also failed.
    Transaction(String),
    /// The embedded `checksums.lock` recorded a canonical SHA-256 (or file
    /// name) that disagrees with an embedded migration's SQL. The runtime
    /// must enforce this in addition to CI: without runtime
    /// enforcement, a developer who edits an embedded schema/migration file
    /// but forgets to regenerate the lock would have the runtime happily
    /// install the edited schema on a fresh DB. See
    /// `lorvex_store::schema::enforce_embedded_lock_checksums`.
    LockChecksumMismatch {
        version: u32,
        name: String,
        expected: String,
        actual: String,
    },
    /// The embedded `checksums.lock` and the compiled-in migration registry
    /// disagree in size: a lock entry exists with no registered migration
    /// (a canonical migration file was copied and locked but never added to
    /// `ladder_migrations()`), or a migration is registered that the lock
    /// does not record. Boot refuses so a fresh install can never realize a
    /// schema that skips part of the recorded ladder.
    LockRegistryMismatch { registered: usize, locked: usize },
}

impl fmt::Display for MigrationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MigrationError::ChecksumMismatch {
                version,
                name,
                expected,
                actual,
            } => write!(
                f,
                "migration {version} ({name}) checksum mismatch: \
                 recorded={expected}, computed={actual}. \
                 A frozen migration file may have been modified."
            ),
            MigrationError::Sql(e) => write!(f, "migration SQL error: {e}"),
            MigrationError::Transaction(message) => write!(f, "{message}"),
            MigrationError::DowngradeDetected {
                binary_max_version,
                db_max_version,
            } => write!(
                f,
                "database schema (v{db_max_version}) is newer than this build supports \
                 (v{binary_max_version}). Please upgrade Lorvex to the latest release \
                 before opening this database. Opening with an older build risks data \
                 loss from schema drift."
            ),
            MigrationError::CorruptedSchema {
                version,
                name,
                missing_kind,
                missing_object,
            } => write!(
                f,
                "migration {version} ({name}) is recorded as applied but {missing_kind} \
                 `{missing_object}` is missing from the database. The on-disk schema has \
                 drifted from the migration file — this usually means a prior apply \
                 crashed mid-commit or an object was dropped out of band. Refusing to \
                 open to prevent silent data corruption. Recovery: restore from backup, \
                 delete the DB to re-initialize, or re-pull from a healthy sync peer. \
                 See #2740 for context."
            ),
            MigrationError::LockChecksumMismatch {
                version,
                name,
                expected,
                actual,
            } => write!(
                f,
                "migration {version} ({name}) hash disagrees with checksums.lock: \
                 lock={expected}, actual={actual}. The schema SQL has been edited \
                 without regenerating checksums.lock — run `npm run \
                 verify:migration-checksums --update` to refresh the lock, or revert \
                 the schema edit. Refusing to open the database so a fresh install \
                 cannot silently land an unreviewed schema."
            ),
            MigrationError::LockRegistryMismatch { registered, locked } => write!(
                f,
                "checksums.lock records {locked} migration entr{}, but this build \
                 registers {registered}. A locked migration was not registered in \
                 `ladder_migrations()` (or a registered one was never locked). \
                 Reconcile the registry with the canonical schema/migrations/ \
                 directory before shipping. Refusing to open the database so a \
                 fresh install cannot realize a schema that skips part of the \
                 recorded ladder.",
                if *locked == 1 { "y" } else { "ies" }
            ),
        }
    }
}

impl std::error::Error for MigrationError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            MigrationError::Sql(e) => Some(e),
            _ => None,
        }
    }
}

impl From<rusqlite::Error> for MigrationError {
    fn from(e: rusqlite::Error) -> Self {
        MigrationError::Sql(e)
    }
}

impl From<String> for MigrationError {
    /// `with_immediate_transaction` produces a combined transaction-
    /// cleanup error string when ROLLBACK fails alongside the original
    /// failure. Route those through `Transaction` so the original
    /// migration failure (and the rollback failure) remain visible.
    fn from(message: String) -> Self {
        MigrationError::Transaction(message)
    }
}

/// Ensure the `schema_migrations` bookkeeping table exists.
fn ensure_schema_migrations_table(conn: &Connection) -> Result<(), MigrationError> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
            version  INTEGER PRIMARY KEY,
            name     TEXT NOT NULL,
            checksum TEXT NOT NULL,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        ) STRICT;",
    )?;
    Ok(())
}

/// Apply a list of migrations to the database.
///
/// For each migration in order:
/// 1. If already applied: verify the checksum matches. Error on mismatch.
/// 2. If not yet applied: execute the SQL and record the migration.
///
/// Migrations are expected to be ordered by `version` ascending.
/// Each migration is applied inside its own transaction.
pub fn apply_migrations(conn: &Connection, migrations: &[Migration]) -> Result<(), MigrationError> {
    // Enforce the embedded `checksums.lock` against the embedded
    // schema + ladder bytes BEFORE touching the DB. The lock is the
    // only artifact that pins the canonical hashes across reviewers,
    // so it must be a hard boot gate; without runtime enforcement, a
    // developer who edits `001_schema.sql` (or a ladder file) and runs
    // the binary against a fresh DB would silently install the edited
    // schema. The gate is keyed on the presence of the baseline
    // `(version 1, name "schema")` entry so test-only migration lists
    // bypass it — every production caller ships
    // `crate::schema::all_migrations()`, which carries the baseline,
    // and then the whole list is verified against the lock.
    if migrations
        .iter()
        .any(|m| m.version == 1 && m.name == "schema")
    {
        crate::schema::enforce_embedded_lock_checksums(migrations)?;
    }

    ensure_schema_migrations_table(conn)?;

    // before applying any migration,
    // verify that the DB's recorded max version is not greater than
    // what this binary knows about. If it is, refuse to proceed with
    // a typed error so the caller can surface a clean "DB newer than
    // this build" dialog instead of silently operating on a schema
    // with constraints it doesn't know about.
    //
    // `SELECT MAX(version)` returns SQL NULL when the table is empty
    // (fresh install, pre-first-migration) — read it as
    // `Option<u32>` via `rusqlite::types::Null` → Option conversion.
    let binary_max_version = migrations.iter().map(|m| m.version).max().unwrap_or(0);
    let db_max_version: Option<u32> =
        conn.query_row("SELECT MAX(version) FROM schema_migrations", [], |row| {
            row.get::<_, Option<u32>>(0)
        })?;
    if let Some(db_max) = db_max_version {
        if binary_max_version > 0 && db_max > binary_max_version {
            return Err(MigrationError::DowngradeDetected {
                binary_max_version,
                db_max_version: db_max,
            });
        }
    }

    for migration in migrations {
        let checksum = sha256_hex(&migration.sql);

        let recorded: Option<String> = conn
            .query_row(
                "SELECT checksum FROM schema_migrations WHERE version = ?1",
                [migration.version],
                |row| row.get(0),
            )
            .optional()?;

        if let Some(recorded_checksum) = recorded {
            // Already applied — verify checksum integrity.
            if recorded_checksum != checksum {
                return Err(MigrationError::ChecksumMismatch {
                    version: migration.version,
                    name: migration.name.clone(),
                    expected: recorded_checksum,
                    actual: checksum,
                });
            }
            // checksum matches the file on disk, but the
            // bookkeeping row only tells us the migration *was* written
            // at some point — it cannot tell us the DDL side effects
            // still exist. Verify that every CREATE object declared by
            // the migration file is present in `sqlite_schema`; if any
            // is missing, fail hard with a diagnosable error rather than
            // silently `continue`-ing onto a half-applied schema.
            schema_audit::audit_migration(conn, migration)?;
            continue;
        }

        // Not yet applied — execute within a transaction.
        //
        // Atomicity invariant (#2260): any failure between BEGIN and
        // COMMIT must roll back so the DB is never left with an orphan
        // CREATE TABLE that has no matching schema_migrations row.
        //
        // Panic safety (#2825): a panic mid-DDL (interrupt, OOM, a
        // future panic in `execute_batch`) must ALSO roll back so the
        // connection doesn't retain an open BEGIN IMMEDIATE that would
        // poison the next migration's BEGIN. We can't use
        // `with_immediate_transaction` here because it short-circuits
        // on a process-global disk-full circuit breaker that is not
        // meaningful at migration time — and tripping it elsewhere
        // would silently block all future schema upgrades. So we
        // mirror the helper's catch_unwind pattern inline.
        //
        // this hand-rolled transaction is intentional
        // and remains exempt from the disk-full circuit breaker that
        // wraps every other write path in `lorvex_store::transaction`.
        // The breaker exists to back off application writes when the
        // disk is genuinely full, but back-pressure on a schema
        // upgrade would brick the app on every subsequent boot — the
        // schema can't be applied if the breaker is tripped, and the
        // breaker can't reset without applying the schema. Keep this
        // path on the bare `BEGIN IMMEDIATE` + `catch_unwind` shape
        // so a transient disk-full at migration time fails the apply
        // (caller surfaces a clean error) without trapping the user
        // in an unrecoverable boot loop.
        conn.execute_batch("BEGIN IMMEDIATE;")?;

        let migration_body = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            conn.execute_batch(&migration.sql)?;
            conn.execute(
                "INSERT INTO schema_migrations (version, name, checksum) VALUES (?1, ?2, ?3)",
                rusqlite::params![migration.version, migration.name, checksum],
            )?;
            conn.execute_batch("COMMIT;")?;
            Ok::<(), rusqlite::Error>(())
        }));

        match migration_body {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                if let Err(rollback_error) = conn.execute_batch("ROLLBACK;") {
                    return Err(MigrationError::Transaction(format!(
                        "migration {} ({}) failed: {e}; rollback failed: {rollback_error}",
                        migration.version, migration.name
                    )));
                }
                return Err(MigrationError::Sql(e));
            }
            Err(panic_payload) => {
                // Clean up the open transaction BEFORE resuming the
                // unwind so the connection isn't left in a poisoned
                // state. The panic takes precedence — we can't return
                // a typed error from this arm — but a rollback that
                // also fails leaves the next migration attempt staring
                // at a half-applied state, so surface it on stderr
                // alongside the panic.
                if let Err(rollback_error) = conn.execute_batch("ROLLBACK;") {
                    eprintln!(
                        "migration {} ({}) panicked AND rollback failed: {rollback_error}; \
                         the next migration attempt may see a half-applied state",
                        migration.version, migration.name
                    );
                }
                std::panic::resume_unwind(panic_payload);
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests;
