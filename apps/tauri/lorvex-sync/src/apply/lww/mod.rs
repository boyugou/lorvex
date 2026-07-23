//! LWW (last-writer-wins) machinery shared by every aggregate / edge /
//! child / day-scoped apply handler.
//!
//! The LWW tie-break enum, SQL comparator, upsert spec, merge-winner
//! version stamper, and shared rejection-detail struct live in one
//! inspectable place so every apply handler picks up the same
//! comparison and conflict-log shape.

use rusqlite::{Connection, OptionalExtension};

use super::ApplyError;

/// LWW tie-break policy used by every aggregate / edge / child /
/// day-scoped apply handler.
///
/// The typed enum captures two distinct invariants in one rename-
/// traceable shape: at the SQL layer it picks the comparison operator
/// (`>` vs `>=`), and at the apply layer it routes an envelope into
/// the strict-LWW or replay path. Plumbing this as a single bool
/// across the 29 call sites that need it would conflate the two
/// intents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LwwTieBreak {
    /// Strict LWW — the inbound envelope's version must be strictly
    /// greater than the local row's version to win. Same-version
    /// envelopes are rejected as no-ops. This is the default for live
    /// envelope apply; concurrent writes from two peers with the same
    /// HLC are not legal in our HLC scheme (the device-id suffix
    /// breaks the tie at generation), so a same-version inbound is
    /// either an exact replay we already applied or a malformed peer.
    RejectEqual,
    /// Allow same-version envelopes to land idempotently. Used by
    /// replay / shadow-promotion paths where the goal is "make sure
    /// this exact envelope is the last write" without requiring a
    /// fresh HLC.
    AllowEqual,
}

impl LwwTieBreak {
    /// SQL comparison operator that implements this policy in a
    /// `WHERE excluded.version <op> table.version` clause.
    pub(crate) const fn sql_op(self) -> &'static str {
        match self {
            LwwTieBreak::RejectEqual => ">",
            LwwTieBreak::AllowEqual => ">=",
        }
    }

    /// Convenience for callers that mix typed and untyped layers
    /// during the migration window.
    pub(crate) const fn allow_equal(self) -> bool {
        matches!(self, LwwTieBreak::AllowEqual)
    }
}

impl From<bool> for LwwTieBreak {
    fn from(allow_equal_versions: bool) -> Self {
        if allow_equal_versions {
            LwwTieBreak::AllowEqual
        } else {
            LwwTieBreak::RejectEqual
        }
    }
}

/// Choose the `WHERE excluded.version <op> table.version` clause for the LWW
/// upsert. [`LwwTieBreak::AllowEqual`] is used by re-emit / replay paths
/// where an identical envelope must be idempotent rather than rejected as a
/// no-op.
///
/// All sibling apply submodules (`day_scoped`, `tag`, `blob`, `edge`,
/// `child`, plus `aggregate::helpers`) share this single definition
/// so the comparison operator never drifts between them.
pub(crate) const fn version_cmp(tie_break: LwwTieBreak) -> &'static str {
    tie_break.sql_op()
}

/// Shared payload for the sibling `LwwRejected(LwwRejectedDetail)`
/// variants in [`apply::aggregate::list::ListDeleteOutcome`] and
/// [`apply::aggregate::LwwGatedDeleteOutcome`]. The dispatcher
/// destructures `local_version` and re-exposes it through
/// `EntityApplyOutcome::LwwRejected { local_version }` so the
/// post-handler delete-flow can render the conflict-log row without
/// re-querying the row's `version`. The
/// in-handler conflict-log row is still written inside the handler
/// itself; this struct is the bridge that lets the envelope-level
/// caller render the same value into the typed `Hlc` it needs for
/// `record_lww_conflict_and_skip` without paying a second SELECT.
#[derive(Debug, Clone)]
pub(crate) struct LwwRejectedDetail {
    pub(crate) local_version: String,
}

/// Stamp `merge_version` onto a merge-winner aggregate row IFF the
/// row's current version lex-orders strictly below `merge_version`,
/// using the same parse-then-typed-compare discipline as
/// `version_stamp.rs:212-220` and the outbox coalesce LWW guard.
///
/// the merge sites in
/// `apply::aggregate::recurrence` and `apply::tag` open-
/// coded `UPDATE table SET version = ?1 WHERE id = ?2 AND ?1 > version`,
/// a SQL byte-compare that is correct for canonical HLCs but
/// inverts when the row carries a stale-shape literal (`'v1'`,
/// `'seed'`). Letters sort ABOVE digits, so a tainted row would
/// falsely win the LWW guard and the merge winner would be left at
/// its pre-merge version — opening the same aggregate-root invariant
/// regression the merge winner-stamp exists to close.
///
/// Discipline: read the existing version, parse both sides, compare
/// as typed `Hlc` whenever both parse, fall back to byte-compare
/// only when both fail to parse, and log+continue on partial-tainted
/// cases (canonical side wins). Returns the number of rows updated
/// (0 if the row is missing or the LWW guard rejected the stamp).
///
/// `pk_column` and `pk_value` identify the winner row (e.g.
/// `("id", winner_task_id)` for the recurrence merge, `("id",
/// winner_tag_id)` for the tag merge).
pub(crate) fn stamp_merge_winner_version(
    conn: &Connection,
    table: &str,
    pk_column: &str,
    pk_value: &str,
    merge_version: &str,
) -> Result<usize, ApplyError> {
    // Defense-in-depth: every current caller passes a `&'static str`
    // table/pk_column from the in-crate closed set, but a `debug_assert!`
    // guard pins the contract so a future caller routing untrusted input
    // here trips on test runs instead of producing malformed SQL.
    if cfg!(debug_assertions) {
        lorvex_domain::assert_safe_sql_identifier(table);
        lorvex_domain::assert_safe_sql_identifier(pk_column);
    }
    // Read the existing version. The pk_column / pk_value pair is
    // a closed set used only by the merge sites in this crate, so a
    // `format!` interpolation is safe (no untrusted input reaches
    // either argument). The same pattern is used by
    // `version_stamp::stamp_entity_version` for its dispatch table.
    // The (table, pk_column) pair has a small bounded cardinality (one
    // entry per edge/child table the apply pipeline touches), so
    // `prepare_cached` caches the version-read plan per table instead
    // of re-parsing on every envelope.
    let read_sql = format!("SELECT version FROM {table} WHERE {pk_column} = ?1");
    let existing: Option<String> = conn
        .prepare_cached(&read_sql)?
        .query_row(rusqlite::params![pk_value], |row| row.get(0))
        .optional()?;
    let Some(existing) = existing else {
        return Ok(0);
    };

    let existing_parse = lorvex_domain::hlc::Hlc::parse(&existing);
    let merge_parse = lorvex_domain::hlc::Hlc::parse(merge_version);
    let should_write = match (&existing_parse, &merge_parse) {
        (Ok(existing_hlc), Ok(merge_hlc)) => merge_hlc > existing_hlc,
        (Err(_), Err(_)) => {
            // Both tainted: best-effort byte compare so the merge
            // winner stamp still terminates on a legacy DB.
            let dedup_signature = format!("merge_winner_stamp|{table}|{pk_value}|both_tainted");
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.merge_winner_stamp_unparseable",
                &format!(
                    "merge winner-stamp byte-compare fallback for \
                     table={table}, {pk_column}={pk_value:?}, \
                     merge_version={merge_version:?} (parsed=false), \
                     existing={existing:?} (parsed=false)"
                ),
                Some(&dedup_signature),
                Some("warn"),
            );
            merge_version > existing.as_str()
        }
        (Ok(_), Err(_)) => {
            // Canonical merge_version vs tainted existing: the
            // canonical side is the unambiguous winner. Stamp the
            // canonical merge_version and clear the taint in the
            // same call.
            let dedup_signature =
                format!("merge_winner_stamp|{table}|{pk_value}|incoming_ok=true|existing_ok=false");
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.merge_winner_stamp_unparseable",
                &format!(
                    "merge winner-stamp partial-tainted fallback for \
                     table={table}, {pk_column}={pk_value:?}, \
                     merge_version={merge_version:?} (parsed=true), \
                     existing={existing:?} (parsed=false); \
                     stamping canonical merge_version"
                ),
                Some(&dedup_signature),
                Some("warn"),
            );
            true
        }
        (Err(_), Ok(_)) => {
            // Tainted merge_version vs canonical existing: refuse
            // the stamp; a malformed merge_version is a bug
            // upstream.
            let dedup_signature =
                format!("merge_winner_stamp|{table}|{pk_value}|incoming_ok=false|existing_ok=true");
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.merge_winner_stamp_unparseable",
                &format!(
                    "merge winner-stamp REFUSED for tainted merge_version: \
                     table={table}, {pk_column}={pk_value:?}, \
                     merge_version={merge_version:?} (parsed=false), \
                     existing={existing:?} (parsed=true)"
                ),
                Some(&dedup_signature),
                Some("error"),
            );
            false
        }
    };

    if !should_write {
        return Ok(0);
    }
    let write_sql = format!("UPDATE {table} SET version = ?1 WHERE {pk_column} = ?2");
    let updated = conn
        .prepare_cached(&write_sql)?
        .execute(rusqlite::params![merge_version, pk_value])?;
    Ok(updated)
}

/// LWW-gated DELETE against an apply-time edge / child table.
///
/// The apply-pipeline equivalent of [`LwwUpsertSpec`] for the delete
/// side. Routing every edge / child delete through this helper keeps
/// the parse-failure semantics aligned with the upsert path's
/// `version_stamp.rs:212-220` discipline and `stamp_merge_winner_version`
/// above. A raw `DELETE FROM <table> WHERE <pk> AND :version >= version`
/// against the row's `version` column is numerically identical to
/// [`compare_versions_with_fallback`]'s byte-compare fallback for
/// "tainted local" cases (ascii letters lex above digits, so a `'seed'`
/// / `'v1'` placeholder local version blocks an incoming canonical HLC
/// delete — the conservative outcome we want), but bypassing the
/// typed comparator would mean a future change (e.g. switching to a
/// strict-canonical-only mode behind a feature flag) has to land in
/// every handler instead of one.
///
/// Returns the number of rows deleted (0 if the row was already absent
/// or the LWW guard rejected the incoming version).
pub(crate) fn lww_gated_delete(
    conn: &Connection,
    table: &str,
    pk_columns: &[&str],
    pk_values: &[&str],
    incoming_version: &str,
) -> Result<usize, ApplyError> {
    debug_assert!(
        !pk_columns.is_empty() && pk_columns.len() == pk_values.len(),
        "lww_gated_delete: pk_columns and pk_values must be non-empty and equal length",
    );
    // Defense-in-depth: `table` and every `pk_columns` entry flow into
    // a `format!`-built WHERE clause / DELETE / SELECT below. Every
    // current caller passes a `&'static str` from the in-crate closed
    // set, but the `debug_assert!` guard pins the contract so a future
    // caller routing untrusted input here trips on test runs.
    if cfg!(debug_assertions) {
        lorvex_domain::assert_safe_sql_identifier(table);
        for col in pk_columns {
            lorvex_domain::assert_safe_sql_identifier(col);
        }
    }
    // Build a positional `<col> = ?N` WHERE clause; column names come
    // from a closed in-crate set (call sites are listed in this
    // module's rustdoc-equivalent comments) so a `format!` interpolation
    // is safe.
    //
    // Pre-size the buffer for the worst current callsite (3-column
    // composite PK with average column-name length ~16): 3 × ("AND
    // " + col + " = ?N") ≈ 96 bytes. This skips the default
    // 4 → 8 → 16 → … grow path while staying under one heap block on
    // every realistic shape. The per-column `?N` index streams via
    // `write!` so the digits don't allocate a separate `String`.
    use std::fmt::Write as _;
    let columns_len: usize = pk_columns.iter().map(|c| c.len()).sum();
    let mut where_clause = String::with_capacity(columns_len + 8 * pk_columns.len());
    for (i, col) in pk_columns.iter().enumerate() {
        if i > 0 {
            where_clause.push_str(" AND ");
        }
        where_clause.push_str(col);
        let _ = write!(where_clause, " = ?{}", i + 1);
    }

    // `prepare_cached` keys on the SQL text. Each call site passes a
    // closed (table, pk_columns) tuple — `task_dependencies`,
    // `task_calendar_event_links`, `task_tags` etc. — so the rendered
    // string is one of a handful of stable shapes for the process
    // lifetime.
    // parse + plan; the rebuild_sql allocation per call still happens
    // (cheap) but the cached statement amortizes the parse cost.
    let read_sql = format!("SELECT version FROM {table} WHERE {where_clause}");
    let local_version: Option<String> = conn
        .prepare_cached(&read_sql)?
        .query_row(
            rusqlite::params_from_iter(pk_values.iter().copied()),
            |row| row.get(0),
        )
        .optional()?;
    let Some(local_version) = local_version else {
        // Row already absent — DELETE is a no-op. Match the prior raw-
        // SQL behavior (rusqlite::execute returned 0 in this case too).
        return Ok(0);
    };

    if lorvex_domain::hlc::compare_versions_with_fallback(incoming_version, &local_version)
        == std::cmp::Ordering::Less
    {
        // Local strictly newer (or canonical local vs tainted incoming);
        // refuse the delete. The tombstone redirect path already logs
        // the skip via the dispatcher, so no extra error_log is needed
        // here — this is the in-row defense-in-depth gate.
        return Ok(0);
    }

    let delete_sql = format!("DELETE FROM {table} WHERE {where_clause}");
    let deleted = conn
        .prepare_cached(&delete_sql)?
        .execute(rusqlite::params_from_iter(pk_values.iter().copied()))?;
    Ok(deleted)
}

/// Spec for an LWW-gated `INSERT … ON CONFLICT DO UPDATE` against an
/// apply-time aggregate / edge / child / day-scoped table.
///
/// Centralizing the SQL builder here makes the LWW predicate the
/// single inspectable source of truth and shrinks every call site to
/// the per-entity columns plus `named_params!` bindings. Without this
/// helper, every aggregate / edge / child / day-scoped handler would
/// open-code the same six-line `format!` template against
/// [`version_cmp`] — 23 byte-identical copies of the same `INSERT …
/// VALUES … ON CONFLICT(…) DO UPDATE SET col=excluded.col, … WHERE
/// excluded.version <op> table.version` shape. The duplication is a
/// drift hazard: the conflict-list, the SET column list, and the LWW
/// predicate must stay in lockstep across every handler, and a typo
/// in any one would silently mis-merge envelopes for that one entity
/// type.
///
/// Convention:
/// - `columns` lists every column that appears in the INSERT (in
///   declaration order). `version` MUST be the last entry.
/// - The DO UPDATE SET clause omits the conflict columns (they must
///   not be reassigned) and writes every other column as
///   `col=excluded.col`.
/// - The placeholder names in the VALUES clause are derived as
///   `:<col>` — `named_params!` bindings on the call site must match.
pub(crate) struct LwwUpsertSpec<'a> {
    /// Target SQL table, e.g. `"habits"`, `"task_tags"`, `"memory"`.
    pub table: &'a str,
    /// Every column in the INSERT, in column-declaration order.
    /// `version` is required and MUST be last.
    pub columns: &'a [&'a str],
    /// One or more conflict columns matching a UNIQUE / PRIMARY KEY
    /// constraint on `table`. These are excluded from the SET clause.
    pub conflict: &'a [&'a str],
    /// LWW tie-break policy. The typed enum keeps the two modes
    /// ([`LwwTieBreak::RejectEqual`] for live apply,
    /// [`LwwTieBreak::AllowEqual`] for shadow-promotion / replay)
    /// exhaustive at every reader.
    pub tie_break: LwwTieBreak,
}

impl<'a> LwwUpsertSpec<'a> {
    /// Render the full LWW upsert SQL string. Caller binds named
    /// parameters via `named_params!` (one binding per column).
    ///
    /// Same as [`build_sql`](Self::build_sql) but caches the rendered
    /// SQL pair (one for each `LwwTieBreak` variant) in the supplied
    /// per-callsite `OnceLock` slot. Use this at per-envelope hot
    /// paths so the SQL allocation is paid once per (callsite,
    /// tie-break) shape instead of every envelope.
    ///
    /// The cache stores both `RejectEqual` and `AllowEqual` shapes
    /// up-front on the first call so subsequent lookups are an
    /// O(1) match against the runtime `tie_break`. Each callsite
    /// declares its own `static CACHE: OnceLock<[String; 2]> =
    /// OnceLock::new();` so the cache lives for the process and the
    /// returned `&'static str` flows directly into `prepare_cached`.
    pub(crate) fn build_sql_cached(
        &self,
        cache: &'static std::sync::OnceLock<[String; 2]>,
    ) -> &'static str {
        let pair = cache.get_or_init(|| {
            let reject = Self {
                table: self.table,
                columns: self.columns,
                conflict: self.conflict,
                tie_break: LwwTieBreak::RejectEqual,
            }
            .build_sql();
            let allow = Self {
                table: self.table,
                columns: self.columns,
                conflict: self.conflict,
                tie_break: LwwTieBreak::AllowEqual,
            }
            .build_sql();
            [reject, allow]
        });
        match self.tie_break {
            LwwTieBreak::RejectEqual => &pair[0],
            LwwTieBreak::AllowEqual => &pair[1],
        }
    }

    /// Rendered into a single pre-sized `String` instead of three
    /// intermediate `Vec<String>` builders, because this runs on every
    /// applied envelope (every aggregate / edge / tag / blob upsert in
    /// the apply pipeline). A naive build would allocate 6 Strings
    /// (3 join lists × 2: collected Vec + final join) plus per-column
    /// `format!` allocations. The fixed-template body (`INSERT INTO
    /// ... VALUES ... ON CONFLICT ... DO UPDATE SET ... WHERE
    /// excluded.version ...`) has predictable per-character cost, so
    /// we sum the slice lengths up-front and `push_str` in order —
    /// one heap allocation per call instead of 6 + N.
    pub(crate) fn build_sql(&self) -> String {
        debug_assert!(
            self.columns.last() == Some(&"version"),
            "LwwUpsertSpec::columns must end with `version`"
        );
        debug_assert!(
            !self.conflict.is_empty(),
            "LwwUpsertSpec::conflict must name at least one column"
        );

        let cmp = version_cmp(self.tie_break);
        // size estimate: fixed template ~80 chars + table name ×2 +
        // per-column overhead (column appears in cols list, in
        // `:col` placeholder, and possibly in `col=excluded.col`
        // SET clause). 4× column-name length covers all three uses
        // with slack for the comma separators.
        let columns_len: usize = self.columns.iter().map(|c| c.len()).sum();
        let conflict_len: usize = self.conflict.iter().map(|c| c.len()).sum();
        let mut sql =
            String::with_capacity(80 + self.table.len() * 2 + columns_len * 4 + conflict_len * 2);

        sql.push_str("INSERT INTO ");
        sql.push_str(self.table);
        sql.push_str(" (");
        for (i, col) in self.columns.iter().enumerate() {
            if i > 0 {
                sql.push_str(", ");
            }
            sql.push_str(col);
        }
        sql.push_str(") VALUES (");
        for (i, col) in self.columns.iter().enumerate() {
            if i > 0 {
                sql.push_str(", ");
            }
            sql.push(':');
            sql.push_str(col);
        }
        sql.push_str(") ON CONFLICT(");
        for (i, col) in self.conflict.iter().enumerate() {
            if i > 0 {
                sql.push_str(", ");
            }
            sql.push_str(col);
        }
        sql.push_str(") DO UPDATE SET ");
        let mut first_update = true;
        for col in self.columns {
            if self.conflict.contains(col) {
                continue;
            }
            if !first_update {
                sql.push_str(", ");
            }
            first_update = false;
            sql.push_str(col);
            sql.push_str("=excluded.");
            sql.push_str(col);
        }
        sql.push_str(" WHERE excluded.version ");
        sql.push_str(cmp);
        sql.push(' ');
        sql.push_str(self.table);
        sql.push_str(".version");
        sql
    }
}

#[cfg(test)]
mod tests;
