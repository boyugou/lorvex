use rusqlite::Connection;
use serde_json::{json, Value};

use super::ApplyError;
use std::collections::HashMap;

/// Snapshot of merge-relevant attribute columns for a task row,
/// captured BEFORE any COALESCE merge runs (#2877). Holding the
/// pre-merge state on the heap means that with N≥3 duplicates the
/// per-loser divergence check still compares against the
/// **original** winner's values rather than a winner whose NULL
/// fields were already filled by an earlier loser's iteration.
#[derive(Clone)]
pub(super) struct RecurrenceMergeSnapshot {
    pub(super) body: Option<String>,
    pub(super) ai_notes: Option<String>,
    pub(super) estimated_minutes: Option<i64>,
    pub(super) due_time: Option<String>,
}

impl RecurrenceMergeSnapshot {
    /// perf: batched read that fetches every
    /// participant's pre-merge snapshot in one round trip.
    /// recurrence merge issued one `SELECT body, ai_notes, ... FROM tasks
    /// WHERE id = ?` per loser inside the dedup loop — N+1 against the
    /// `tasks` table on every recurrence-key collision. Coalescing into
    /// a single `WHERE id IN (...)` query keeps the loop body
    /// allocation-free past the initial map.
    ///
    /// Returns a HashMap keyed by task id so the caller can look up
    /// each participant's snapshot without any further DB traffic. Any
    /// id not present in the result is reported as
    /// `ApplyError::InvariantViolated`-style by the caller; the
    /// snapshot reader itself does not synthesize empty rows.
    pub(super) fn read_many(
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<HashMap<String, Self>, ApplyError> {
        if task_ids.is_empty() {
            return Ok(HashMap::new());
        }
        let placeholders = lorvex_domain::sql_in_placeholders(task_ids.len(), 0);
        let sql = format!(
            "SELECT id, body, ai_notes, estimated_minutes, due_time \
             FROM tasks WHERE id IN ({placeholders})"
        );
        let mut stmt = conn.prepare_cached(&sql)?;
        let rows = stmt.query_map(
            rusqlite::params_from_iter(task_ids.iter().map(String::as_str)),
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    Self {
                        body: row.get(1)?,
                        ai_notes: row.get(2)?,
                        estimated_minutes: row.get(3)?,
                        due_time: row.get(4)?,
                    },
                ))
            },
        )?;
        let mut out = HashMap::with_capacity(task_ids.len());
        for row in rows {
            let (id, snapshot) = row?;
            out.insert(id, snapshot);
        }
        Ok(out)
    }
}

/// compare two pre-merge snapshots (winner +
/// loser, both captured BEFORE any COALESCE runs) and return the
/// loser's divergent values as JSON.
///
/// Returns `Ok(None)` when no divergence exists, or `Ok(Some(json))`
/// with only the divergent loser fields. Diverges whenever:
///   - both sides are non-NULL and differ (loser's distinct value
///     would be silently dropped by COALESCE), OR
///   - winner is NULL and loser has a value AND a previous loser
///     in the same merge already had its own non-NULL value (a 3+
///     way merge would otherwise silently pick the first loser's
///     value with no diagnostic). The 3-way check is encoded by
///     the caller passing `winner` = the merge-time-zero snapshot
///     and tracking which fields a prior loser already filled.
pub(super) fn divergent_loser_fields(
    winner: &RecurrenceMergeSnapshot,
    loser: &RecurrenceMergeSnapshot,
    already_filled: &std::collections::HashSet<&'static str>,
) -> Option<String> {
    let mut divergent = serde_json::Map::new();

    /// Generic helper that merged the previous byte-isomorphic
    /// `record_str` / `record_int` inner fns. Records `loser`'s value
    /// when it differs from `winner` (Some/Some divergence) or when
    /// `winner` is None and an earlier loser already donated a value
    /// (#2877 third-loser case — see [`merge_duplicate_recurrence_instances`]).
    fn record<T: PartialEq + serde::Serialize>(
        out: &mut serde_json::Map<String, Value>,
        key: &'static str,
        winner: Option<T>,
        loser: Option<T>,
        already_filled: &std::collections::HashSet<&'static str>,
    ) {
        match (winner, loser) {
            (Some(w), Some(l)) if w != l => {
                out.insert(key.to_string(), json!(l));
            }
            (None, Some(l)) if already_filled.contains(key) => {
                out.insert(key.to_string(), json!(l));
            }
            _ => {}
        }
    }

    record(
        &mut divergent,
        "body",
        winner.body.as_deref(),
        loser.body.as_deref(),
        already_filled,
    );
    record(
        &mut divergent,
        "ai_notes",
        winner.ai_notes.as_deref(),
        loser.ai_notes.as_deref(),
        already_filled,
    );
    record(
        &mut divergent,
        "estimated_minutes",
        winner.estimated_minutes,
        loser.estimated_minutes,
        already_filled,
    );
    record(
        &mut divergent,
        "due_time",
        winner.due_time.as_deref(),
        loser.due_time.as_deref(),
        already_filled,
    );

    if divergent.is_empty() {
        return None;
    }
    // Serializing a Map<String, Value> built from `json!()` output
    // is infallible — the only failure modes are non-string keys
    // or non-finite floats, neither of which we construct here.
    Some(
        serde_json::to_string(&Value::Object(divergent))
            .expect("recurrence-divergence map must serialize"),
    )
}
