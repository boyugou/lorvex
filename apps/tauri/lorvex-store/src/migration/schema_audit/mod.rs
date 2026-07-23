//! Post-migration schema audit.
//!
//! For every migration whose `schema_migrations` row checksum matches the
//! file on disk, parse the file's CREATE-object signature and verify each
//! object still exists in `sqlite_schema`. A prior crash or out-of-band
//! manual repair can leave a checksum-match row pointing at DDL that is
//! partially or entirely missing; without this audit the runner would
//! happily skip the migration, letting the first read touch a half-
//! applied schema and producing confusing "no such table" errors
//! downstream.
//!
//! Scope:
//!   * ADDITIVE post-check. Does not alter the existing checksum branch.
//!   * Fails hard with `MigrationError::CorruptedSchema`; never re-runs or
//!     patches the DDL. Recovery is a user action (restore backup, delete
//!     corrupted DB, re-pull from sync).
//!   * Signature is "object existence only" — we do not compare column
//!     lists, WHERE clauses, or index expressions. The checksum already
//!     catches file-level drift; the audit catches DB-level absence.
//!   * Runs for EVERY already-applied migration, the baseline included, and
//!     requires each `CREATE` object it declares to still exist. A future
//!     numbered migration that legitimately DROPs or renames a baseline
//!     object must therefore be reconciled with this audit first — scope the
//!     check to a migration's net-surviving objects, or remove the superseded
//!     object from the audited set — otherwise the baseline re-audit reports
//!     the intentionally-dropped object as `CorruptedSchema` and refuses to
//!     open. Not reachable while `ladder_migrations()` is empty: pre-launch
//!     (`schema/migration_policy.json` `launched: false`) the baseline evolves
//!     in place and no destructive numbered migration exists.

use rusqlite::Connection;

use super::runner::{Migration, MigrationError};

/// A DDL object extracted from a migration's SQL text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct DdlObject {
    pub(super) kind: DdlKind,
    pub(super) name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum DdlKind {
    Table,
    Index,
    Trigger,
    View,
}

impl DdlKind {
    /// The value stored in `sqlite_schema.type` for this DDL kind. SQLite
    /// records both ordinary tables and `CREATE VIRTUAL TABLE` (FTS5) as
    /// `"table"`, so we collapse them here.
    const fn sqlite_type(self) -> &'static str {
        match self {
            DdlKind::Table => "table",
            DdlKind::Index => "index",
            DdlKind::Trigger => "trigger",
            DdlKind::View => "view",
        }
    }

    const fn human(self) -> &'static str {
        match self {
            DdlKind::Table => "table",
            DdlKind::Index => "index",
            DdlKind::Trigger => "trigger",
            DdlKind::View => "view",
        }
    }
}

/// Strip `-- line comments` and `/* block comments */` from SQL. Without
/// this, a commented-out `CREATE TABLE` line (which the file has many of,
/// as schema documentation) would produce a phantom object the audit
/// would then fail to find in `sqlite_schema`.
fn strip_comments(sql: &str) -> String {
    let bytes = sql.as_bytes();
    let mut out = String::with_capacity(sql.len());
    let mut i = 0;
    while i < bytes.len() {
        // Line comment: `-- ... \n`
        if i + 1 < bytes.len() && bytes[i] == b'-' && bytes[i + 1] == b'-' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        // Block comment: `/* ... */`
        if i + 1 < bytes.len() && bytes[i] == b'/' && bytes[i + 1] == b'*' {
            i += 2;
            while i + 1 < bytes.len() && !(bytes[i] == b'*' && bytes[i + 1] == b'/') {
                i += 1;
            }
            i = (i + 2).min(bytes.len());
            continue;
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

/// Extract the DDL object signature of a migration.
///
/// Recognizes:
///   * `CREATE [UNIQUE] INDEX [IF NOT EXISTS] <name> ...`
///   * `CREATE [VIRTUAL] TABLE [IF NOT EXISTS] <name> ...`
///   * `CREATE TRIGGER [IF NOT EXISTS] <name> ...`
///   * `CREATE [TEMP] VIEW [IF NOT EXISTS] <name> ...`
///
/// Object names may be bare (`foo`), double-quoted (`"foo"`), back-ticked
/// (`` `foo` ``), or bracketed (`[foo]`). We unwrap the quoting so the
/// name matches `sqlite_schema.name` verbatim.
pub(super) fn extract_objects(sql: &str) -> Vec<DdlObject> {
    let stripped = strip_comments(sql);
    let mut objects = Vec::new();

    // Normalize to ASCII-uppercase for keyword scanning, but keep an
    // index map back to the original so we can read object names with
    // original casing.
    let upper: Vec<u8> = stripped.bytes().map(|b| b.to_ascii_uppercase()).collect();
    let orig = stripped.as_bytes();

    let len = upper.len();
    let mut i = 0;
    while i < len {
        // Find the next `CREATE` token that starts at a word boundary.
        if !(i + 6 <= len
            && &upper[i..i + 6] == b"CREATE"
            && (i == 0 || !is_ident_byte(upper[i - 1]))
            && (i + 6 == len || !is_ident_byte(upper[i + 6])))
        {
            i += 1;
            continue;
        }

        // Walk forward through optional modifiers: UNIQUE, VIRTUAL, TEMP,
        // TEMPORARY. Any number in any order (SQLite is liberal).
        let mut j = i + 6;
        j = skip_ws(&upper, j);
        loop {
            if let Some(next) = match_keyword(&upper, j, b"UNIQUE") {
                j = skip_ws(&upper, next);
                continue;
            }
            if let Some(next) = match_keyword(&upper, j, b"VIRTUAL") {
                j = skip_ws(&upper, next);
                continue;
            }
            if let Some(next) = match_keyword(&upper, j, b"TEMPORARY") {
                j = skip_ws(&upper, next);
                continue;
            }
            if let Some(next) = match_keyword(&upper, j, b"TEMP") {
                j = skip_ws(&upper, next);
                continue;
            }
            break;
        }

        let kind = if let Some(next) = match_keyword(&upper, j, b"TABLE") {
            j = next;
            DdlKind::Table
        } else if let Some(next) = match_keyword(&upper, j, b"INDEX") {
            j = next;
            DdlKind::Index
        } else if let Some(next) = match_keyword(&upper, j, b"TRIGGER") {
            j = next;
            DdlKind::Trigger
        } else if let Some(next) = match_keyword(&upper, j, b"VIEW") {
            j = next;
            DdlKind::View
        } else {
            // Not a CREATE we care about (e.g. CREATE ROLE in some dialect
            // — SQLite doesn't have it, but parse defensively).
            i += 6;
            continue;
        };

        j = skip_ws(&upper, j);

        // Optional `IF NOT EXISTS`.
        if let Some(next) = match_keyword(&upper, j, b"IF") {
            let after_if = skip_ws(&upper, next);
            if let Some(next) = match_keyword(&upper, after_if, b"NOT") {
                let after_not = skip_ws(&upper, next);
                if let Some(next) = match_keyword(&upper, after_not, b"EXISTS") {
                    j = skip_ws(&upper, next);
                }
            }
        }

        // Read the object name. May be quoted.
        if let Some((name, end)) = read_identifier(orig, j) {
            // Audit only accepts unqualified names — a `schema.name`
            // prefix would mean the author is targeting an attached DB,
            // which we don't support. Strip any leading `main.`.
            let name = name.trim_start_matches("main.").to_string();
            objects.push(DdlObject { kind, name });
            i = end;
        } else {
            i += 6;
        }
    }

    objects
}

const fn is_ident_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn skip_ws(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() && bytes[i].is_ascii_whitespace() {
        i += 1;
    }
    i
}

/// If `bytes[i..]` starts with `keyword` followed by a non-identifier
/// byte (or end of input), return the index just past the keyword.
fn match_keyword(bytes: &[u8], i: usize, keyword: &[u8]) -> Option<usize> {
    let end = i + keyword.len();
    if end > bytes.len() {
        return None;
    }
    if &bytes[i..end] != keyword {
        return None;
    }
    if end < bytes.len() && is_ident_byte(bytes[end]) {
        return None;
    }
    Some(end)
}

/// Read a SQL identifier starting at `bytes[i]`. Handles:
///   * bare names: `foo_bar`
///   * double-quoted: `"foo bar"` (SQL standard)
///   * back-ticked: `` `foo` ``
///   * bracketed: `[foo]` (T-SQL style; SQLite accepts it)
///
/// Returns `(name, index_past_name)` with the quoting characters stripped.
fn read_identifier(bytes: &[u8], i: usize) -> Option<(String, usize)> {
    if i >= bytes.len() {
        return None;
    }
    let first = bytes[i];
    if first == b'"' {
        return read_until(bytes, i + 1, b'"').map(|(s, end)| (s, end + 1));
    }
    if first == b'`' {
        return read_until(bytes, i + 1, b'`').map(|(s, end)| (s, end + 1));
    }
    if first == b'[' {
        return read_until(bytes, i + 1, b']').map(|(s, end)| (s, end + 1));
    }

    // Bare identifier: [A-Za-z_][A-Za-z0-9_.]*  — allow one optional
    // schema-qualifier dot; anything else terminates.
    if !(first.is_ascii_alphabetic() || first == b'_') {
        return None;
    }
    let mut end = i;
    while end < bytes.len() && (is_ident_byte(bytes[end]) || bytes[end] == b'.') {
        end += 1;
    }
    let name = std::str::from_utf8(&bytes[i..end]).ok()?.to_string();
    Some((name, end))
}

fn read_until(bytes: &[u8], start: usize, terminator: u8) -> Option<(String, usize)> {
    let mut end = start;
    while end < bytes.len() && bytes[end] != terminator {
        end += 1;
    }
    if end >= bytes.len() {
        return None;
    }
    let name = std::str::from_utf8(&bytes[start..end]).ok()?.to_string();
    Some((name, end))
}

/// Verify every DDL object declared by `migration` exists in the live DB.
///
/// Called from the runner AFTER confirming the recorded checksum matches.
/// Returns `MigrationError::CorruptedSchema` on the first missing object.
///
/// this audit is intentionally existence-only — it
/// proves the table / index / trigger names declared by the migration
/// are still in `sqlite_schema`, but does NOT verify the column shape,
/// constraint set, or trigger body still matches what the migration
/// authored. A manual `ALTER TABLE … DROP COLUMN` (or an out-of-band
/// rebuild that omitted a column) leaves the object name intact and
/// passes this gate. Defending against that requires diffing the
/// serialized DDL of every object against the migration source, which
/// is non-trivial because SQLite normalizes whitespace, quoting, and
/// expression parens in `sqlite_schema.sql`. Catching name drift
/// (which is the realistic failure mode after a partial-apply crash —
/// the symptom #2740 was filed against) closes the most common gap;
/// a deeper structural audit can be added if a future incident shows
/// it's needed.
pub(super) fn audit_migration(
    conn: &Connection,
    migration: &Migration,
) -> Result<(), MigrationError> {
    for obj in extract_objects(&migration.sql) {
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM sqlite_schema WHERE type = ?1 AND name = ?2 LIMIT 1",
                rusqlite::params![obj.kind.sqlite_type(), obj.name],
                |_| Ok(true),
            )
            .or_else(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => Ok(false),
                other => Err(other),
            })?;
        if !exists {
            return Err(MigrationError::CorruptedSchema {
                version: migration.version,
                name: migration.name.clone(),
                missing_kind: obj.kind.human(),
                missing_object: obj.name,
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
