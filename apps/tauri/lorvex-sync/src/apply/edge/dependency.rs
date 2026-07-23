use rusqlite::{named_params, params, Connection, OptionalExtension};

use lorvex_domain::ids::TaskId;

use super::super::{ApplyError, LwwTieBreak};
use super::helpers::{required_str, split_composite_id};

// ---------------------------------------------------------------------------
// task_dependency (PK = task_id, depends_on_task_id)
// ---------------------------------------------------------------------------

pub(crate) fn apply_task_dependency_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components into typed
    // `TaskId` newtypes at handler entry. The cycle-validator and
    // cycle-break helpers still take `&str`, so we thread `as_str()`
    // through them; SQL bind sites use the rusqlite ToSql impl on the
    // newtype (zero-copy). Dispatcher-validated upstream so
    // `from_trusted` skips a redundant parse.
    let (task_id_str, depends_on_task_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let depends_on_task_id = TaskId::from_trusted(depends_on_task_id_str.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let created_at = required_str(&val, "created_at", "task_dependency")?;

    // Two devices operating offline can each add an edge that, when merged,
    // closes a cycle on the receiving device — e.g. device A inserts A→B
    // while device B inserts B→A. The local write path validates cycles via
    // `validate_no_dependency_cycle` before every insert, so remote edges
    // must pass the same gate or the DAG invariant collapses and the
    // DependencyGraphView's Kahn's-sort fallback gets exercised on real
    // data.
    //
    // Self-dependency (task_id == depends_on_task_id) falls through to the
    // same validation error — the DB-level CHECK constraint on
    // task_dependencies would otherwise surface as a less actionable
    // SQLite error at INSERT time.
    let depends_on_slice = [depends_on_task_id.as_str().to_string()];

    // wrap cycle-break + INSERT in a SAVEPOINT so a
    // partial failure (e.g. INSERT hits a transient SQLite error
    // after the loser edge has already been DELETE'd + tombstoned by
    // `try_break_cycle_by_hlc`) cannot leave the graph with a hole
    // the cluster will broadcast. Mirror the merge-tags savepoint
    // pattern (#2880-M1) for the same reason. The ROLLBACK TO restores
    // the loser edge, the conflict_log row that we wrote here, and
    // the unfinished INSERT into a single atomic apply.
    //
    // Routes through `lorvex_store::transaction::with_savepoint_mapped`
    // so a panic inside the cycle-break body rolls the savepoint back
    // BEFORE the unwind resumes, matching the panic-safety contract
    // every other savepoint site in the apply pipeline now uses.
    lorvex_store::transaction::with_savepoint_mapped(
        conn,
        "cycle_break_and_insert",
        ApplyError::InvalidPayload,
        |conn| {
            if let Err(cycle_err) =
                lorvex_workflow::dependency_validation::validate_no_dependency_cycle(
                    conn,
                    &lorvex_domain::TaskId::from_trusted(task_id.as_str().to_string()),
                    &depends_on_slice,
                )
            {
                // Self-dependencies (task_id == depends_on_task_id) never break
                // via tiebreak — the CHECK constraint on task_dependencies and
                // the validator's explicit self-dep check both mean there is
                // no legitimate way to land this edge. Fall through to the
                // store error so it ends up in sync_conflict_log.
                if task_id == depends_on_task_id {
                    return Err(ApplyError::Store(cycle_err));
                }
                // #2142 deterministic tiebreak: when a cycle exists, compare the
                // incoming edge's HLC version to the versions of the existing
                // edges on the cycle path. The oldest HLC loses. If the incoming
                // loses, reject as before. If an existing local edge loses,
                // delete + tombstone it and fall through to insert the incoming.
                // Every device reaches the same verdict because the cycle-
                // detection + HLC-min calculation is deterministic, so the graph
                // converges across the cluster instead of permanently forking.
                match try_break_cycle_by_hlc(
                    conn,
                    &task_id,
                    &depends_on_task_id,
                    version,
                    apply_ts,
                )? {
                    CycleBreak::IncomingLoses => return Err(ApplyError::Store(cycle_err)),
                    CycleBreak::NoCycle => {
                        // Nothing to record — the cycle resolved itself
                        // between validator and tiebreak. Just fall through.
                    }
                    CycleBreak::ExistingLoses {
                        loser_task_id,
                        loser_depends_on_task_id,
                        loser_version,
                        loser_device_suffix,
                    } => {
                        // The loser is already deleted + tombstoned by
                        // `try_break_cycle_by_hlc`. Log the resolution for the
                        // diagnostics panel so the user can see that a remote
                        // peer overruled their local edge.
                        crate::conflict_log::log_conflict(
                            conn,
                            &crate::conflict_log::ConflictLogEntry {
                                id: 0,
                                entity_type: std::borrow::Cow::Borrowed(
                                    lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
                                ),
                                entity_id: format!("{loser_task_id}:{loser_depends_on_task_id}"),
                                winner_version: version.to_string(),
                                loser_version,
                                loser_device_id: loser_device_suffix,
                                loser_payload: None,
                                // share the once-per-
                                // envelope `apply_ts`.
                                resolved_at: apply_ts.to_string(),
                                resolution_type: std::borrow::Cow::Borrowed(
                                    lorvex_domain::naming::RESOLUTION_CYCLE_BREAK,
                                ),
                            },
                        )?;
                    }
                }
            }

            // lifted to shared `LwwUpsertSpec`.
            static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
            let sql = crate::apply::LwwUpsertSpec {
                table: "task_dependencies",
                columns: &["task_id", "depends_on_task_id", "created_at", "version"],
                conflict: &["task_id", "depends_on_task_id"],
                tie_break: allow_equal_versions,
            }
            .build_sql_cached(&SQL_CACHE);
            conn.prepare_cached(sql)?.execute(named_params! {
                ":task_id": &task_id,
                ":depends_on_task_id": &depends_on_task_id,
                ":created_at": created_at,
                ":version": version,
            })?;
            Ok(())
        },
    )
}

pub(crate) fn apply_task_dependency_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components into typed
    // `TaskId` newtypes once at handler entry. `lww_gated_delete` still
    // takes `&[&str]` so we feed `as_str()` through.
    let (task_id_str, depends_on_task_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let depends_on_task_id = TaskId::from_trusted(depends_on_task_id_str.to_string());
    // defense-in-depth in-row LWW guard. See `lww_gated_delete` for
    // the typed-comparator discipline this routes through.
    crate::apply::lww_gated_delete(
        conn,
        "task_dependencies",
        &["task_id", "depends_on_task_id"],
        &[task_id.as_str(), depends_on_task_id.as_str()],
        version,
    )?;
    Ok(())
}

/// Outcome of `try_break_cycle_by_hlc`. See call site in
/// [`apply_task_dependency_upsert`] for the decision policy.
enum CycleBreak {
    /// The incoming edge has the oldest HLC on the cycle path; reject it.
    /// Caller propagates `StoreError::Validation` via the normal per-
    /// envelope failure path (sync_conflict_log records it).
    IncomingLoses,
    /// An existing local edge on the cycle path has the oldest HLC;
    /// that edge has been deleted and tombstoned so the insert can now
    /// proceed without closing a cycle. Also carries
    /// the loser edge's HLC so the conflict-log row gets a real
    /// `loser_version` + `loser_device_id` instead of empty strings.
    ExistingLoses {
        loser_task_id: TaskId,
        loser_depends_on_task_id: TaskId,
        loser_version: String,
        loser_device_suffix: String,
    },
    /// The cycle has already vanished between the validator and the
    /// tiebreak (e.g. a concurrent envelope deleted the closing
    /// edge). No tombstone needed and no conflict_log row is
    /// emitted — a degenerate `ExistingLoses { "", "" }` shape
    /// would let the caller write `entity_id = ":"` into
    /// conflict_log.
    NoCycle,
}

/// Resolve an edge-closes-cycle conflict deterministically.
///
/// Comparing the incoming edge's version against the versions of
/// edges on a SINGLE cycle path (e.g. one discovered by
/// `find_cycle_path`'s DFS) is non-deterministic across the
/// cluster. The DFS order is deterministic on a fixed graph, but
/// the resulting "loser" is a function of the *path* the DFS
/// happened to take — and two devices with the SAME logical edge
/// set can have arrived at that set through different insertion
/// orders, so their parents-map walks can enumerate different
/// paths and elect different losers. The cluster then forks on
/// cycles of length ≥ 3.
///
/// The deterministic shape uses a recursive CTE to enumerate every
/// edge that lies on the strongly-connected component (SCC) the
/// incoming edge would close — i.e., every existing edge `(u, v)`
/// such that `u` is reachable from `depends_on_task_id` AND `v` can
/// reach `task_id` along existing edges. The SCC depends only on
/// the edge set, not on insertion history, so every device computes
/// the same set. Within that set we pick the globally-minimum
/// `(version, task_id, depends_on_task_id)` triple as the loser.
/// Two devices with identical edge sets therefore reach identical
/// verdicts regardless of how they arrived at those sets.
///
/// On `ExistingLoses`, this function DELETES the loser edge and emits a
/// tombstone so the decision propagates across the sync ring. On
/// `IncomingLoses`, the incoming edge simply fails to apply and gets
/// logged to sync_conflict_log by the caller.
fn try_break_cycle_by_hlc(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
    incoming_version: &str,
    apply_ts: &str,
) -> Result<CycleBreak, ApplyError> {
    // Quick rejection: if no path exists from `depends_on_task_id`
    // back to `task_id`, the incoming edge does not close a cycle —
    // surface `NoCycle` so the caller skips both the conflict_log
    // entry and the tombstone.
    if find_cycle_path(conn, task_id.as_str(), depends_on_task_id.as_str())?.is_none() {
        return Ok(CycleBreak::NoCycle);
    }

    // deterministic global MIN(version) over all
    // existing edges in the SCC the incoming edge would close.
    //
    // - `forward(node)` = nodes reachable from `depends_on_task_id`
    //   along existing edges (`task_id → depends_on_task_id`).
    // - `backward(node)` = nodes that can reach `task_id` along the
    //   same edge direction (computed by traversing edges
    //   tail-to-head: an edge `(u, v)` with `v` already in
    //   `backward` means `u` can reach `task_id`).
    //
    // Every existing edge `(u, v)` whose endpoints are BOTH in
    // forward AND BOTH in backward sits inside the SCC the incoming
    // edge would close. The deterministic loser is the one with the
    // lexicographically smallest `(version, task_id,
    // depends_on_task_id)` — `version` first because HLC ordering is
    // the cluster-wide truth; `task_id` / `depends_on_task_id`
    // tiebreak the (extremely rare) case where two edges share a
    // version (same physical_ms, same counter, same device suffix —
    // only possible from a hand-crafted fixture).
    let candidate: Option<(String, String, String)> = conn
        .query_row(
            "WITH RECURSIVE
                 forward(node) AS (
                     SELECT :start_id
                     UNION
                     SELECT td.depends_on_task_id
                     FROM task_dependencies td
                     JOIN forward f ON td.task_id = f.node
                 ),
                 backward(node) AS (
                     SELECT :target_id
                     UNION
                     SELECT td.task_id
                     FROM task_dependencies td
                     JOIN backward b ON td.depends_on_task_id = b.node
                 )
             SELECT td.task_id, td.depends_on_task_id, td.version
             FROM task_dependencies td
             WHERE td.task_id IN forward
               AND td.depends_on_task_id IN forward
               AND td.task_id IN backward
               AND td.depends_on_task_id IN backward
             ORDER BY td.version ASC, td.task_id ASC, td.depends_on_task_id ASC
             LIMIT 1",
            named_params! {
                ":start_id": depends_on_task_id,
                ":target_id": task_id,
            },
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .optional()?;

    // Compare the SCC-min existing edge against the incoming edge:
    // the incoming wins iff strictly older than every candidate.
    //
    // Use the parse-then-typed-compare pattern from
    // `outbox::coalesce::enqueue_coalesced`. A raw string lex-compare is correct
    // for two well-formed HLCs but inverts when one side is a
    // stale-shape literal (`'v1'`, `'seed'`, hand-crafted
    // fixtures): ASCII letters sort ABOVE digits, so a tainted
    // `'seed'` row would compare as "newer" than every canonical
    // HLC and falsely win the cycle break.
    //
    // Discipline: parse both sides; compare as typed `Hlc` whenever
    // both parse; fall back to byte compare ONLY when both fail to
    // parse (so the cycle-break decision still terminates on a
    // legacy DB). Partial-tainted cases log+continue treating the
    // canonical side as the unambiguous winner — same shape as
    // `outbox::coalesce::enqueue_coalesced_body`.
    let (min_edge, min_version): (Option<(String, String)>, String) = match candidate {
        None => (None, incoming_version.to_string()),
        Some((existing_task, existing_dep, existing_version)) => {
            let existing_is_loser = compare_cycle_loser(
                conn,
                task_id,
                depends_on_task_id,
                incoming_version,
                &existing_version,
            );
            if existing_is_loser {
                (Some((existing_task, existing_dep)), existing_version)
            } else {
                (None, incoming_version.to_string())
            }
        }
    };

    match min_edge {
        None => Ok(CycleBreak::IncomingLoses),
        Some((loser_task, loser_dep)) => {
            // Delete the losing edge locally and emit a sync-delete
            // tombstone so peers also drop it. The tombstone uses the
            // incoming edge's version as its HLC — that's the cluster-
            // agreed moment the decision was made, and it's strictly
            // greater than the loser edge's version (else it wouldn't
            // be the loser).
            conn.prepare_cached(
                "DELETE FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2",
            )?
            .execute(params![loser_task, loser_dep])?;
            // share the once-per-envelope `apply_ts`.
            crate::tombstone::create_tombstone(
                conn,
                lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
                &format!("{loser_task}:{loser_dep}"),
                incoming_version,
                apply_ts,
                None,
                None,
            )?;
            // derive the loser device id from the
            // loser HLC's suffix so the diagnostics panel can show
            // which peer's edge was overruled. `min_version` here
            // is the edge's actual HLC string captured during the
            // path scan above. Audit (silent-failure-hunter): on
            // indistinguishable from a genuinely empty suffix —
            // diagnostics couldn't tell "we don't know which peer"
            // from "this peer authored without a suffix". Log the
            // corruption to error_logs so the diagnostic panel can
            // surface it; the empty fallback is preserved because
            // cycle-break still has to record the loser even when
            // its provenance HLC is corrupt.
            let loser_device_suffix = match lorvex_domain::hlc::Hlc::parse(&min_version) {
                Ok(h) => h.device_suffix().to_string(),
                Err(parse_err) => {
                    crate::error_log::log_sync_error(
                        conn,
                        "sync.apply.dependency_cycle_break_corrupt_hlc",
                        &format!(
                            "loser HLC '{min_version}' on dependency edge {loser_task} -> {loser_dep} \
                             is not a valid HLC at cycle-break attribution: {parse_err}"
                        ),
                        None,
                    );
                    String::new()
                }
            };
            Ok(CycleBreak::ExistingLoses {
                loser_task_id: TaskId::from_trusted(loser_task),
                loser_depends_on_task_id: TaskId::from_trusted(loser_dep),
                loser_version: min_version,
                loser_device_suffix,
            })
        }
    }
}

/// Decide whether the `existing_version` edge should lose to the
/// `incoming_version` on the SCC under cycle-break tiebreak.
///
/// Returns `true` when the existing edge is the loser (i.e. should be
/// deleted + tombstoned), `false` when the incoming side loses.
///
/// Mirrors the parse-then-typed-compare discipline in
/// `outbox::coalesce::enqueue_coalesced_body`: parse both sides,
/// compare as typed `Hlc` whenever both parse, fall back to byte
/// compare ONLY when both fail to parse. Partial-tainted cases
/// log+continue treating the canonical side as the unambiguous
/// winner so the cluster verdict converges even on a corrupt DB.
fn compare_cycle_loser(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
    incoming_version: &str,
    existing_version: &str,
) -> bool {
    let existing_parse = lorvex_domain::hlc::Hlc::parse(existing_version);
    let incoming_parse = lorvex_domain::hlc::Hlc::parse(incoming_version);
    match (&existing_parse, &incoming_parse) {
        (Ok(existing_hlc), Ok(incoming_hlc)) => existing_hlc < incoming_hlc,
        (Err(_), Err(_)) => {
            // Both tainted: best-effort byte compare, log so
            // the corruption stays visible. Letters > digits
            // means a legacy `'seed'` literal would beat a
            // legacy timestamp string here, but with both
            // sides equally suspect there is no better
            // verdict than the historical fallback.
            let dedup_signature =
                format!("edge_cycle_break|{task_id}|{depends_on_task_id}|both_tainted");
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.edge_cycle_break_unparseable",
                &format!(
                    "edge cycle-break byte-compare fallback for \
                     task_id={task_id}, depends_on_task_id={depends_on_task_id}, \
                     incoming={incoming_version:?} (parsed=false), \
                     existing={existing_version:?} (parsed=false)"
                ),
                Some(&dedup_signature),
                Some("warn"),
            );
            existing_version < incoming_version
        }
        (Ok(_), Err(_)) => {
            // Canonical incoming vs tainted existing: the
            // canonical side is the unambiguous winner. Treat
            // the tainted existing edge as the loser so the
            // cycle break converges; log+continue per H1's
            // partial-tainted contract.
            let dedup_signature = format!(
                "edge_cycle_break|{task_id}|{depends_on_task_id}|incoming_ok=true|existing_ok=false"
            );
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.edge_cycle_break_unparseable",
                &format!(
                    "edge cycle-break partial-tainted fallback for \
                     task_id={task_id}, depends_on_task_id={depends_on_task_id}, \
                     incoming={incoming_version:?} (parsed=true), \
                     existing={existing_version:?} (parsed=false); \
                     treating tainted existing as loser"
                ),
                Some(&dedup_signature),
                Some("warn"),
            );
            true
        }
        (Err(_), Ok(_)) => {
            // Tainted incoming vs canonical existing: keep
            // the canonical edge; surface the corruption.
            let dedup_signature = format!(
                "edge_cycle_break|{task_id}|{depends_on_task_id}|incoming_ok=false|existing_ok=true"
            );
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.apply.edge_cycle_break_unparseable",
                &format!(
                    "edge cycle-break partial-tainted fallback for \
                     task_id={task_id}, depends_on_task_id={depends_on_task_id}, \
                     incoming={incoming_version:?} (parsed=false), \
                     existing={existing_version:?} (parsed=true); \
                     treating tainted incoming as loser"
                ),
                Some(&dedup_signature),
                Some("warn"),
            );
            false
        }
    }
}

/// DFS from `start_id` to `target_id` following `task_id → depends_on_task_id`
/// edges. Returns the full cycle path shaped as
/// `[target_id, start_id, ..., target_id]` when a cycle exists.
///
/// Delegates to the canonical implementation in
/// [`lorvex_workflow::dependency_validation::find_cycle_path`]
/// (see that doc-comment for the deterministic-DFS contract +
/// parents-map memory shape). The MCP local-write validation path
/// runs the same DFS, so a single source of truth means a future fix
/// flows to both surfaces. The `StoreError → ApplyError` mapping
/// uses the existing `From<StoreError>` impl on `ApplyError`.
fn find_cycle_path(
    conn: &Connection,
    target_id: &str,
    start_id: &str,
) -> Result<Option<Vec<String>>, ApplyError> {
    let target = lorvex_domain::TaskId::from_trusted(target_id.to_string());
    let start = lorvex_domain::TaskId::from_trusted(start_id.to_string());
    Ok(lorvex_workflow::dependency_validation::find_cycle_path(
        conn, &target, &start,
    )?)
}
