//! The `lorvex-interchange` v1 format: a lean, schema-shaped export/import for
//! migrating a Lorvex store to a fresh install. `type` is the SQLite table name
//! and `row` is the table row; the archive carries the user's current-state
//! data (all tables minus a sync/runtime/history denylist) and a digest-backed
//! manifest — no sync envelope, tombstones, payload shadows, or per-row HLC
//! machinery.

use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};

use lorvex_domain::hlc::Hlc;
use lorvex_domain::time::canonicalize_rfc3339_instant;
use rusqlite::types::{Value, ValueRef};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::Value as Json;
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

/// SHA-256 hex digest of `data` — used for the manifest's `data.jsonl` digest.
fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// Tables never exported — sync/runtime/device/diagnostic internals, the
/// migration-bookkeeping row, and history superseded by current state. Allow by
/// default: a new user-data table exports automatically unless added here.
pub const DENYLIST: &[&str] = &[
    "schema_migrations",
    // Sync internals.
    "sync_outbox",
    "sync_tombstones",
    "sync_checkpoints",
    "sync_device_cursors",
    "sync_conflict_log",
    "sync_pending_inbox",
    "sync_quarantine_blocklist",
    "sync_payload_shadow",
    "local_sync_owner",
    "local_counters",
    "mcp_host_authority",
    "mcp_idempotency",
    // Device / runtime state.
    "device_state",
    "provider_calendar_events",
    "task_provider_event_links",
    "provider_scope_runtime_state",
    "calendar_event_attendee_shadow",
    "task_reminder_delivery_state",
    "habit_reminder_delivery_state",
    // Diagnostics / audit.
    "error_logs",
    "ai_changelog",
    "ai_changelog_entities",
    // Superseded history.
    "memory_revisions",
];

const FORMAT: &str = "lorvex-interchange";
const VERSION: u32 = 1;

/// Errors from interchange export/import.
#[derive(Debug)]
pub enum InterchangeError {
    Sqlite(rusqlite::Error),
    Json(serde_json::Error),
    Zip(zip::result::ZipError),
    Io(std::io::Error),
    /// The archive is missing `manifest.json` or `data.jsonl`.
    MissingEntry(&'static str),
    /// The manifest declared an unrecognized format or a newer version.
    UnsupportedFormat(String),
    /// `data.jsonl` did not match its recorded hash.
    DigestMismatch(String),
    /// A `data.jsonl` line was not a `{"type","row"}` object.
    MalformedLine,
    /// A sync-critical column (`version` HLC, an `*_at` timestamp) carried a
    /// value that is not in its required canonical format. Mirrors the Apple
    /// core's `InterchangeRows.InterchangeError.invalidValue`.
    InvalidValue {
        table: String,
        column: String,
        value: String,
    },
}

impl std::fmt::Display for InterchangeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            InterchangeError::Sqlite(e) => write!(f, "sqlite error: {e}"),
            InterchangeError::Json(e) => write!(f, "json error: {e}"),
            InterchangeError::Zip(e) => write!(f, "zip error: {e}"),
            InterchangeError::Io(e) => write!(f, "io error: {e}"),
            InterchangeError::MissingEntry(n) => write!(f, "interchange archive missing {n}"),
            InterchangeError::UnsupportedFormat(s) => write!(f, "unsupported interchange: {s}"),
            InterchangeError::DigestMismatch(s) => write!(f, "interchange digest mismatch: {s}"),
            InterchangeError::MalformedLine => write!(f, "malformed interchange data line"),
            InterchangeError::InvalidValue {
                table,
                column,
                value,
            } => write!(
                f,
                "interchange row for {table}.{column} is not canonical: {value:?}"
            ),
        }
    }
}
impl std::error::Error for InterchangeError {}
impl From<rusqlite::Error> for InterchangeError {
    fn from(e: rusqlite::Error) -> Self {
        InterchangeError::Sqlite(e)
    }
}
impl From<serde_json::Error> for InterchangeError {
    fn from(e: serde_json::Error) -> Self {
        InterchangeError::Json(e)
    }
}
impl From<zip::result::ZipError> for InterchangeError {
    fn from(e: zip::result::ZipError) -> Self {
        InterchangeError::Zip(e)
    }
}
impl From<std::io::Error> for InterchangeError {
    fn from(e: std::io::Error) -> Self {
        InterchangeError::Io(e)
    }
}

/// `manifest.json` — keys match the Apple writer's.
#[derive(Debug, Serialize, Deserialize)]
pub struct InterchangeManifest {
    pub format: String,
    pub version: u32,
    pub created_at: String,
    pub source_app: String,
    pub source_app_version: String,
    pub row_counts: BTreeMap<String, u64>,
    pub data_sha256: String,
}

/// Base tables to export: every non-internal, non-FTS table not in `DENYLIST`,
/// in deterministic name order.
pub fn included_tables(conn: &Connection) -> Result<Vec<String>, InterchangeError> {
    let mut stmt = conn.prepare(
        "SELECT name FROM sqlite_master
         WHERE type = 'table'
           AND name NOT LIKE 'sqlite_%'
           AND name NOT LIKE '%\\_fts%' ESCAPE '\\'
         ORDER BY name",
    )?;
    let names = stmt
        .query_map([], |r| r.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(names
        .into_iter()
        .filter(|n| !DENYLIST.contains(&n.as_str()))
        .collect())
}

/// Whether `table` may be written by an import. Mirrors the `included_tables`
/// export filter (not in `DENYLIST`, not a `sqlite_%` internal, not an FTS
/// shadow), so a crafted archive can't target sync/runtime internals, the
/// schema-bookkeeping row, or FTS shadows: writes that bypass every
/// write-surface invariant or quarantine the database on the next launch.
pub fn is_importable_table(table: &str) -> bool {
    !DENYLIST.contains(&table) && !table.starts_with("sqlite_") && !table.contains("_fts")
}

/// Settable (non-generated) columns of `table`, in declared order.
pub fn exportable_columns(conn: &Connection, table: &str) -> Result<Vec<String>, InterchangeError> {
    let mut stmt = conn.prepare("SELECT name, hidden FROM pragma_table_xinfo(?1)")?;
    let cols = stmt
        .query_map([table], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(cols
        .into_iter()
        .filter(|(_, hidden)| *hidden == 0)
        .map(|(name, _)| name)
        .collect())
}

/// Serialize every included row to `data.jsonl` bytes (`{"type","row"}` per
/// line, keys sorted for a byte-stable digest).
pub fn export_data_jsonl(conn: &Connection) -> Result<Vec<u8>, InterchangeError> {
    let mut out = Vec::new();
    for table in included_tables(conn)? {
        let cols = exportable_columns(conn, &table)?;
        if cols.is_empty() {
            continue;
        }
        let col_list = cols
            .iter()
            .map(|c| format!("\"{c}\""))
            .collect::<Vec<_>>()
            .join(", ");
        let mut stmt = conn.prepare(&format!("SELECT {col_list} FROM \"{table}\""))?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let mut obj: BTreeMap<String, Json> = BTreeMap::new();
            for (i, col) in cols.iter().enumerate() {
                obj.insert(col.clone(), value_ref_to_json(row.get_ref(i)?));
            }
            let mut line: BTreeMap<String, Json> = BTreeMap::new();
            line.insert("type".into(), Json::String(table.clone()));
            line.insert("row".into(), serde_json::to_value(obj)?);
            serde_json::to_writer(&mut out, &line)?;
            out.push(b'\n');
        }
    }
    Ok(out)
}

/// A root entity selected for a partial export (table + single-column PK value).
#[derive(Clone, Debug)]
pub struct Seed {
    pub table: String,
    pub id: String,
}

/// Serialize a partial export: only the FK-closure of `seeds`. Computed
/// generically from the schema (no ownership map): phase 1 pulls owned
/// descendants downward through NOT-NULL child foreign keys; phase 2 pulls
/// referenced rows upward (for import validity) without re-expanding downward.
pub fn export_data_jsonl_partial(
    conn: &Connection,
    seeds: &[Seed],
) -> Result<Vec<u8>, InterchangeError> {
    let include = closure_row_ids(conn, seeds)?;
    let mut out = Vec::new();
    for table in included_tables(conn)? {
        let rowids = match include.get(&table) {
            Some(set) if !set.is_empty() => set,
            _ => continue,
        };
        let cols = exportable_columns(conn, &table)?;
        if cols.is_empty() {
            continue;
        }
        let col_list = cols
            .iter()
            .map(|c| format!("\"{c}\""))
            .collect::<Vec<_>>()
            .join(", ");
        let placeholders = rowids.iter().map(|_| "?").collect::<Vec<_>>().join(", ");
        let mut stmt = conn.prepare(&format!(
            "SELECT {col_list} FROM \"{table}\" WHERE rowid IN ({placeholders})"
        ))?;
        let params: Vec<i64> = rowids.iter().copied().collect();
        let mut rows = stmt.query(rusqlite::params_from_iter(params.iter()))?;
        while let Some(row) = rows.next()? {
            let mut obj: BTreeMap<String, Json> = BTreeMap::new();
            for (i, col) in cols.iter().enumerate() {
                obj.insert(col.clone(), value_ref_to_json(row.get_ref(i)?));
            }
            let mut line: BTreeMap<String, Json> = BTreeMap::new();
            line.insert("type".into(), Json::String(table.clone()));
            line.insert("row".into(), serde_json::to_value(obj)?);
            serde_json::to_writer(&mut out, &line)?;
            out.push(b'\n');
        }
    }
    Ok(out)
}

struct Fk {
    from: String,
    to_table: String,
    to: String,
}

fn closure_row_ids(
    conn: &Connection,
    seeds: &[Seed],
) -> Result<BTreeMap<String, std::collections::BTreeSet<i64>>, InterchangeError> {
    use std::collections::{BTreeMap, BTreeSet};
    let tables = included_tables(conn)?;
    let table_set: BTreeSet<&str> = tables.iter().map(String::as_str).collect();

    let mut fks: BTreeMap<String, Vec<Fk>> = BTreeMap::new();
    let mut not_null: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for table in &tables {
        let mut stmt = conn.prepare(&format!("PRAGMA foreign_key_list(\"{table}\")"))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Fk {
                    to_table: r.get::<_, String>(2)?,
                    from: r.get::<_, String>(3)?,
                    to: r.get::<_, String>(4)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        fks.insert(
            table.clone(),
            rows.into_iter()
                .filter(|f| table_set.contains(f.to_table.as_str()))
                .collect(),
        );
        let mut stmt = conn.prepare(&format!("PRAGMA table_xinfo(\"{table}\")"))?;
        let nn = stmt
            .query_map([], |r| Ok((r.get::<_, String>(1)?, r.get::<_, i64>(3)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        not_null.insert(
            table.clone(),
            nn.into_iter()
                .filter(|(_, n)| *n == 1)
                .map(|(c, _)| c)
                .collect(),
        );
    }

    // Parent table → child relationships it owns (child FK column is NOT NULL).
    let mut owned_children: BTreeMap<String, Vec<(String, String, String)>> = BTreeMap::new();
    for table in &tables {
        for fk in fks.get(table).into_iter().flatten() {
            if not_null
                .get(table)
                .map(|s| s.contains(&fk.from))
                .unwrap_or(false)
            {
                owned_children
                    .entry(fk.to_table.clone())
                    .or_default()
                    .push((table.clone(), fk.from.clone(), fk.to.clone()));
            }
        }
    }

    // Phase 1 — owned descendants (downward BFS by rowid).
    let mut owned: BTreeMap<String, BTreeSet<i64>> = BTreeMap::new();
    let mut queue: Vec<(String, i64)> = Vec::new();
    for seed in seeds {
        let Some(pk) = single_primary_key_column(conn, &seed.table)? else {
            continue;
        };
        let mut stmt = conn.prepare(&format!(
            "SELECT rowid FROM \"{}\" WHERE \"{pk}\" = ?1",
            seed.table
        ))?;
        let rids = stmt
            .query_map([&seed.id], |r| r.get::<_, i64>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        for rid in rids {
            if owned.entry(seed.table.clone()).or_default().insert(rid) {
                queue.push((seed.table.clone(), rid));
            }
        }
    }
    while let Some((table, rid)) = queue.pop() {
        for (child, from, to) in owned_children.get(&table).cloned().unwrap_or_default() {
            let parent_val: rusqlite::types::Value = conn.query_row(
                &format!("SELECT \"{to}\" FROM \"{table}\" WHERE rowid = ?1"),
                [rid],
                |r| r.get(0),
            )?;
            if matches!(parent_val, rusqlite::types::Value::Null) {
                continue;
            }
            let mut stmt = conn.prepare(&format!(
                "SELECT rowid FROM \"{child}\" WHERE \"{from}\" = ?1"
            ))?;
            let rids = stmt
                .query_map([&parent_val], |r| r.get::<_, i64>(0))?
                .collect::<Result<Vec<_>, _>>()?;
            for crid in rids {
                if owned.entry(child.clone()).or_default().insert(crid) {
                    queue.push((child.clone(), crid));
                }
            }
        }
    }

    // Phase 2 — referential closure (upward only).
    let mut referenced: BTreeMap<String, BTreeSet<i64>> = BTreeMap::new();
    let mut ref_queue: Vec<(String, i64)> = owned
        .iter()
        .flat_map(|(t, ids)| ids.iter().map(move |r| (t.clone(), *r)))
        .collect();
    while let Some((table, rid)) = ref_queue.pop() {
        for fk in fks.get(&table).into_iter().flatten() {
            let val: rusqlite::types::Value = conn.query_row(
                &format!("SELECT \"{}\" FROM \"{table}\" WHERE rowid = ?1", fk.from),
                [rid],
                |r| r.get(0),
            )?;
            if matches!(val, rusqlite::types::Value::Null) {
                continue;
            }
            let mut stmt = conn.prepare(&format!(
                "SELECT rowid FROM \"{}\" WHERE \"{}\" = ?1",
                fk.to_table, fk.to
            ))?;
            let rids = stmt
                .query_map([&val], |r| r.get::<_, i64>(0))?
                .collect::<Result<Vec<_>, _>>()?;
            for prid in rids {
                let already = owned
                    .get(&fk.to_table)
                    .map(|s| s.contains(&prid))
                    .unwrap_or(false)
                    || referenced
                        .get(&fk.to_table)
                        .map(|s| s.contains(&prid))
                        .unwrap_or(false);
                if !already {
                    referenced
                        .entry(fk.to_table.clone())
                        .or_default()
                        .insert(prid);
                    ref_queue.push((fk.to_table.clone(), prid));
                }
            }
        }
    }

    let mut result = owned;
    for (table, ids) in referenced {
        result.entry(table).or_default().extend(ids);
    }
    Ok(result)
}

fn single_primary_key_column(
    conn: &Connection,
    table: &str,
) -> Result<Option<String>, InterchangeError> {
    let mut pks = primary_key_columns(conn, table)?;
    Ok(if pks.len() == 1 { pks.pop() } else { None })
}

/// The primary-key columns of `table`, in key ordinal order (a composite key's
/// `(a, b)` yields `["a", "b"]`). Empty for a table with no declared PK.
fn primary_key_columns(conn: &Connection, table: &str) -> Result<Vec<String>, InterchangeError> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_xinfo(\"{table}\")"))?;
    let mut pks = stmt
        .query_map([], |r| Ok((r.get::<_, String>(1)?, r.get::<_, i64>(5)?)))?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .filter(|(_, pk)| *pk > 0)
        .collect::<Vec<_>>();
    pks.sort_by_key(|(_, pk)| *pk);
    Ok(pks.into_iter().map(|(name, _)| name).collect())
}

/// Build the `ON CONFLICT …` tail for an import upsert.
///
/// Every non-primary-key column present in the row is refreshed from
/// `excluded`, so a colliding row is updated in place rather than replaced —
/// `ON DELETE CASCADE` never fires, and local-only child rows survive an
/// import into a non-empty store. A row carrying only its primary key
/// (nothing to update), or a table with no declared primary key, degrades to
/// `DO NOTHING` — the existing row and its children are kept intact.
fn upsert_conflict_clause(columns: &[&String], pk_columns: &[String]) -> String {
    let assignments = columns
        .iter()
        .filter(|c| !pk_columns.iter().any(|pk| pk.as_str() == c.as_str()))
        .map(|c| format!("\"{c}\" = excluded.\"{c}\""))
        .collect::<Vec<_>>();
    let target = if pk_columns.is_empty() {
        String::new()
    } else {
        format!(
            "({})",
            pk_columns
                .iter()
                .map(|c| format!("\"{c}\""))
                .collect::<Vec<_>>()
                .join(", ")
        )
    };
    if assignments.is_empty() || pk_columns.is_empty() {
        format!("ON CONFLICT{target} DO NOTHING")
    } else {
        format!(
            "ON CONFLICT{target} DO UPDATE SET {}",
            assignments.join(", ")
        )
    }
}

/// Whether `raw` is a canonical HLC string: three `_`-separated segments — an
/// all-ASCII-digit physical-ms segment, an all-ASCII-digit counter segment,
/// and a 16-char hex device suffix.
/// `lorvex_domain::hlc::Hlc::parse` alone is not sufficient here: it parses
/// the numeric segments via `str::parse`, which (unlike this format's
/// canonical charset) accepts a leading `+`. A `+`-prefixed physical-ms
/// segment would parse to a valid `Hlc` while byte-sorting BELOW every
/// digit-only peer value, silently breaking the lexicographic `version`
/// ordering LWW and SQL range queries rely on. Checking the raw charset first
/// closes that gap.
fn is_canonical_hlc(raw: &str) -> bool {
    let mut parts = raw.splitn(3, '_');
    let (Some(physical_ms), Some(counter), Some(_device_suffix)) =
        (parts.next(), parts.next(), parts.next())
    else {
        return false;
    };
    let all_ascii_digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    all_ascii_digits(physical_ms) && all_ascii_digits(counter) && Hlc::parse(raw).is_ok()
}

/// Validate — and, for a timestamp column, canonicalize — a `data.jsonl` cell
/// before it is bound into the upsert. SQLite's own CHECK constraints already
/// gate every enum / range column on the `INSERT` below, so this covers only
/// the two sync-critical shapes the schema does NOT constrain and a
/// hand-edited archive can otherwise slip in verbatim:
///
/// - **`version` (HLC).** Must satisfy [`is_canonical_hlc`]. Rejected rather
///   than bound — a tainted value would corrupt LWW comparison and the
///   outbound version stamp this store restamps onto the row when it
///   enqueues it for sync. Left AS-IS (not rewritten) when valid, matching
///   Apple.
/// - **A column ending in `_at`.** Must parse as an RFC 3339 instant
///   (`lorvex_domain::time::canonicalize_rfc3339_instant`, which — like
///   Apple's `canonicalizeRfc3339Instant` — accepts a non-UTC offset and
///   converts it). The bound value is REPLACED with its canonical
///   millisecond-UTC rendering so a peer's second/microsecond-precision or
///   offset timestamp compares correctly against this store's own
///   timestamps. Rejected if unparseable.
///
/// A non-string JSON value (including `null`) is passed through
/// unvalidated, matching Apple: neither column is ever anything but TEXT in
/// the schema, so a non-string value here is already headed for a bind-type
/// mismatch the `INSERT` itself rejects.
fn validate_and_canonicalize_column(
    table: &str,
    column: &str,
    value: &Json,
) -> Result<Value, InterchangeError> {
    let Some(raw) = value.as_str() else {
        return Ok(json_to_value(value));
    };
    let invalid = || InterchangeError::InvalidValue {
        table: table.to_string(),
        column: column.to_string(),
        value: raw.to_string(),
    };
    if column == "version" {
        if !is_canonical_hlc(raw) {
            return Err(invalid());
        }
        Ok(json_to_value(value))
    } else if column.ends_with("_at") {
        canonicalize_rfc3339_instant(raw)
            .map(Value::Text)
            .ok_or_else(invalid)
    } else {
        Ok(json_to_value(value))
    }
}

/// Apply `data.jsonl` rows into `conn`. The caller MUST be inside a transaction;
/// this enables `PRAGMA defer_foreign_keys` so rows may arrive in any order.
/// Only columns present in the target schema are bound (unknown columns and
/// unknown tables are ignored — tolerant). Returns per-table counts.
///
/// Each row is applied as a primary-key upsert (`INSERT … ON CONFLICT(<pk>)
/// DO UPDATE SET <non-pk cols> = excluded.<col>`), so importing into a
/// NON-empty store is a non-destructive merge: a colliding row is updated in
/// place — never delete-then-reinserted — so `ON DELETE CASCADE` never fires
/// and child rows the local store holds but the archive omits survive. A row
/// present only in the archive is inserted; a row present only locally is left
/// untouched.
pub fn import_data_jsonl(
    conn: &Connection,
    data: &[u8],
) -> Result<BTreeMap<String, u64>, InterchangeError> {
    conn.execute_batch("PRAGMA defer_foreign_keys = ON")?;
    let mut col_cache: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut pk_cache: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut counts: BTreeMap<String, u64> = BTreeMap::new();

    for line in data.split(|b| *b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let parsed: Json = serde_json::from_slice(line)?;
        let obj = parsed.as_object().ok_or(InterchangeError::MalformedLine)?;
        let table = obj
            .get("type")
            .and_then(Json::as_str)
            .ok_or(InterchangeError::MalformedLine)?
            .to_string();

        // Apply the export allowlist on the way in too, and BEFORE any
        // schema introspection or upsert: drop a record aimed at a table
        // `is_importable_table` rejects (denylisted, FTS shadow,
        // sqlite-internal) so a crafted archive can't overwrite
        // sync/runtime internals or the schema-bookkeeping row.
        if !is_importable_table(&table) {
            continue;
        }

        let row = obj
            .get("row")
            .and_then(Json::as_object)
            .ok_or(InterchangeError::MalformedLine)?;

        if !col_cache.contains_key(&table) {
            col_cache.insert(table.clone(), exportable_columns(conn, &table)?);
            pk_cache.insert(table.clone(), primary_key_columns(conn, &table)?);
        }
        let target_cols = &col_cache[&table];

        let mut cols: Vec<&String> = Vec::new();
        let mut values: Vec<Value> = Vec::new();
        for col in target_cols {
            if let Some(v) = row.get(col) {
                cols.push(col);
                values.push(validate_and_canonicalize_column(&table, col, v)?);
            }
        }
        if cols.is_empty() {
            continue;
        }
        let col_list = cols
            .iter()
            .map(|c| format!("\"{c}\""))
            .collect::<Vec<_>>()
            .join(", ");
        let placeholders = (1..=cols.len())
            .map(|i| format!("?{i}"))
            .collect::<Vec<_>>()
            .join(", ");
        let conflict = upsert_conflict_clause(&cols, &pk_cache[&table]);
        conn.execute(
            &format!("INSERT INTO \"{table}\" ({col_list}) VALUES ({placeholders}) {conflict}"),
            rusqlite::params_from_iter(values.iter()),
        )?;
        *counts.entry(table).or_insert(0) += 1;
    }

    // Rebuild every FTS index from its backing table. An upsert that updates a
    // conflicting row fires the AFTER UPDATE FTS triggers, but a
    // same-transaction sequence of upserts across FTS-backed tables can leave
    // the external-content `tasks_fts_trigram` / `calendar_events_fts` and the
    // full-content `tasks_fts` out of step with their backing tables.
    // Rebuilding after the row apply — in the caller's transaction — restores
    // each index to exactly match its backing table. `tasks_fts` has no
    // `content=` backing (its `tags` column is an aggregate), so it is cleared
    // and re-projected instead of using FTS5's `'rebuild'` command.
    conn.execute_batch(
        "DELETE FROM tasks_fts;
         INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
         SELECT t.rowid, t.title, t.body, t.ai_notes,
                (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = t.id ORDER BY tg.lookup_key ASC))
           FROM tasks t;
         INSERT INTO tasks_fts_trigram(tasks_fts_trigram) VALUES('rebuild');
         INSERT INTO calendar_events_fts(calendar_events_fts) VALUES('rebuild');",
    )?;
    Ok(counts)
}

/// Export the whole store as a `lorvex-interchange` ZIP archive.
pub fn export_archive(
    conn: &Connection,
    source_app_version: &str,
    seeds: &[Seed],
) -> Result<(Vec<u8>, InterchangeManifest), InterchangeError> {
    let data = if seeds.is_empty() {
        export_data_jsonl(conn)?
    } else {
        export_data_jsonl_partial(conn, seeds)?
    };
    let data_sha256 = sha256_hex(&data);

    // Row counts are derived from the produced data.jsonl, so they stay correct
    // for both the full and partial paths.
    let mut row_counts: BTreeMap<String, u64> = BTreeMap::new();
    for line in data.split(|b| *b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let v: Json = serde_json::from_slice(line)?;
        if let Some(ty) = v["type"].as_str() {
            *row_counts.entry(ty.to_string()).or_insert(0) += 1;
        }
    }
    let created_at: String =
        conn.query_row("SELECT strftime('%Y-%m-%dT%H:%M:%fZ','now')", [], |r| {
            r.get(0)
        })?;

    let buf = Vec::new();
    let mut zip = ZipWriter::new(Cursor::new(buf));
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    let manifest = InterchangeManifest {
        format: FORMAT.to_string(),
        version: VERSION,
        created_at,
        source_app: "lorvex-tauri".to_string(),
        source_app_version: source_app_version.to_string(),
        row_counts,
        data_sha256,
    };
    zip.start_file("manifest.json", options)?;
    zip.write_all(&serde_json::to_vec_pretty(&manifest)?)?;
    zip.start_file("data.jsonl", options)?;
    zip.write_all(&data)?;

    Ok((zip.finish()?.into_inner(), manifest))
}

/// Per-table row counts from importing an archive.
pub struct InterchangeImportSummary {
    pub row_counts: BTreeMap<String, u64>,
}

/// Import a `lorvex-interchange` archive into `conn`, verifying the format and
/// the `data.jsonl` digest before applying rows (deferred FK). The caller
/// passes a writer connection; this opens its own transaction.
pub fn import_archive(
    conn: &Connection,
    archive: &[u8],
) -> Result<InterchangeImportSummary, InterchangeError> {
    let mut zip = zip::ZipArchive::new(Cursor::new(archive))?;

    let mut manifest_bytes: Option<Vec<u8>> = None;
    let mut data_bytes: Option<Vec<u8>> = None;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let name = entry.name().to_string();
        let mut bytes = Vec::new();
        entry.read_to_end(&mut bytes)?;
        if name == "manifest.json" {
            manifest_bytes = Some(bytes);
        } else if name == "data.jsonl" {
            data_bytes = Some(bytes);
        }
    }

    let manifest_bytes = manifest_bytes.ok_or(InterchangeError::MissingEntry("manifest.json"))?;
    let data = data_bytes.ok_or(InterchangeError::MissingEntry("data.jsonl"))?;
    let manifest: InterchangeManifest = serde_json::from_slice(&manifest_bytes)?;
    if manifest.format != FORMAT {
        return Err(InterchangeError::UnsupportedFormat(manifest.format));
    }
    if manifest.version > VERSION {
        return Err(InterchangeError::UnsupportedFormat(format!(
            "version {}",
            manifest.version
        )));
    }
    if sha256_hex(&data) != manifest.data_sha256 {
        return Err(InterchangeError::DigestMismatch("data.jsonl".into()));
    }

    // One transaction so `defer_foreign_keys` actually defers — rows arrive in
    // any order and FKs are checked only at commit.
    let tx = conn.unchecked_transaction()?;
    let row_counts = import_data_jsonl(&tx, &data)?;
    tx.commit()?;
    Ok(InterchangeImportSummary { row_counts })
}

fn value_ref_to_json(v: ValueRef<'_>) -> Json {
    match v {
        ValueRef::Null => Json::Null,
        ValueRef::Integer(i) => Json::Number(i.into()),
        ValueRef::Real(f) => serde_json::Number::from_f64(f)
            .map(Json::Number)
            .unwrap_or(Json::Null),
        ValueRef::Text(t) => Json::String(String::from_utf8_lossy(t).into_owned()),
        // The interchange schema has no BLOB columns, so this arm is defensive;
        // emit hex so a stray binary value is at least carried.
        ValueRef::Blob(b) => Json::String(hex::encode(b)),
    }
}

fn json_to_value(v: &Json) -> Value {
    match v {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Integer(i64::from(*b)),
        Json::Number(n) => {
            if let Some(i) = n.as_i64() {
                Value::Integer(i)
            } else if let Some(f) = n.as_f64() {
                Value::Real(f)
            } else {
                Value::Null
            }
        }
        Json::String(s) => Value::Text(s.clone()),
        // Schema has no JSON-array/object columns that aren't TEXT; a nested
        // value reaching here is stored as its compact JSON text.
        other => Value::Text(other.to_string()),
    }
}

#[cfg(test)]
mod tests;
