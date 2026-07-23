use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{EDGE_TASK_DEPENDENCY, OP_DELETE};
use lorvex_domain::TaskId;

use super::*;

/// Remove a task from all dependency edges (both incoming and outgoing).
/// Returns the IDs of tasks whose dependency sets changed (tasks that
/// depended on this one — now unblocked).
///
/// Combine the dependency-edge fan-out into ONE SELECT and ONE
/// DELETE. Splitting it into four SQL round-trips (two SELECTs +
/// two DELETEs) would make cancel / delete of a heavily-linked
/// task pay the writer lock for each of those, multiplying
/// contention with sibling MCP writers. The single SELECT pulls
/// every edge that touches `task_id` — incoming OR outgoing — and
/// the companion DELETE drops them all at once. The returned
/// `affected` set surfaces only `dependent_id`s of incoming edges,
/// preserving the "tasks now unblocked" contract.
///
/// Pre-load each edge's `(version, created_at)` alongside the
/// composite-id pair so the per-edge tombstone payload matches the
/// canonical shape `remove_task_dependency` and the seed-time
/// enqueue produce. Without `(version, created_at)` peers fall
/// back to the degenerate "no version" branch on the edge
/// tombstone path and a concurrent re-add of the same edge on another
/// device could be silently overridden by the cascade tombstone.
fn remove_task_from_all_deps_at(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    _updated_at: &str,
) -> AppResult<Vec<String>> {
    // Pull every (task_id, depends_on_task_id, version, created_at)
    // tuple that touches the target in one round-trip. Loading the
    // pre-delete `(version, created_at)` BEFORE the DELETE is the
    // contract the typed envelope layer expects — once the row is
    // gone there is no way to reconstruct the LWW basis. The
    // `is_incoming` projection lets the post-write loop classify
    // each edge for envelope construction without re-querying.
    struct Edge {
        task_id: String,
        depends_on_task_id: String,
        version: String,
        created_at: String,
        is_incoming: bool,
    }

    // Two single-index SELECTs (outgoing via PK on task_id, incoming
    // via secondary index on depends_on_task_id) instead of one
    // OR-predicate scan — SQLite cannot combine those two indexes
    // under a single OR. Each branch hard-codes `is_incoming` so the
    // CASE expression is gone too. Mirrors the same split applied to
    // the DELETE below.
    let mut edges: Vec<Edge> = {
        let mut stmt = conn
            .prepare_cached(
                "SELECT task_id, depends_on_task_id, version, created_at \
                 FROM task_dependencies WHERE task_id = ?1",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![task_id.as_str()], |row| {
                Ok(Edge {
                    task_id: row.get(0)?,
                    depends_on_task_id: row.get(1)?,
                    version: row.get(2)?,
                    created_at: row.get(3)?,
                    is_incoming: false,
                })
            })
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        rows
    };
    let incoming: Vec<Edge> = {
        let mut stmt = conn
            .prepare_cached(
                "SELECT task_id, depends_on_task_id, version, created_at \
                 FROM task_dependencies WHERE depends_on_task_id = ?1",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![task_id.as_str()], |row| {
                Ok(Edge {
                    task_id: row.get(0)?,
                    depends_on_task_id: row.get(1)?,
                    version: row.get(2)?,
                    created_at: row.get(3)?,
                    is_incoming: true,
                })
            })
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        rows
    };
    edges.extend(incoming);

    if edges.is_empty() {
        return Ok(Vec::new());
    }

    // Two prepared DELETEs (one per index) instead of one OR-scan —
    // SQLite cannot combine the PK index on task_id with the secondary
    // index on depends_on_task_id under a single OR predicate, so the
    // unified form scans the full table once the graph has any size.
    // Mirrors the reference fix in
    // lorvex-workflow/src/lifecycle/primitives/dependencies.rs.
    conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")
        .map_err(AppError::from)?
        .execute(params![task_id.as_str()])
        .map_err(AppError::from)?;
    conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")
        .map_err(AppError::from)?
        .execute(params![task_id.as_str()])
        .map_err(AppError::from)?;

    // Enqueue sync delete envelopes per edge. Order matches the
    // pre-refactor split (incoming first, then outgoing) so any sync
    // log expectations downstream stay stable. Each payload now
    // carries `(task_id, depends_on_task_id, version, created_at)`
    // so peer LWW on the edge tombstone path has a coherent compare
    // basis (H1; mirrors the inline shape produced by
    // `remove_task_dependency` per #2979-H4).
    let mut affected = Vec::new();
    for edge in edges.iter().filter(|e| e.is_incoming) {
        enqueue_dependency_edge_delete(
            conn,
            edge.task_id.as_str(),
            edge.depends_on_task_id.as_str(),
            edge.version.as_str(),
            edge.created_at.as_str(),
        )?;
        affected.push(edge.task_id.clone());
    }
    for edge in edges.iter().filter(|e| !e.is_incoming) {
        enqueue_dependency_edge_delete(
            conn,
            edge.task_id.as_str(),
            edge.depends_on_task_id.as_str(),
            edge.version.as_str(),
            edge.created_at.as_str(),
        )?;
    }

    Ok(affected)
}

/// typed enqueue helper for a single dependency-edge
/// tombstone. Matches the canonical payload shape
/// (`task_id`, `depends_on_task_id`, `version`, `created_at`) that
/// `remove_task_dependency` produces, so cascade and atomic delete
/// paths converge on one wire format. No `DeleteEnvelope<T>` newtype
/// here because the dependency tombstone schema is a plain JSON
/// composite (the edge has no `updated_at` column to copy, unlike
/// `task_calendar_event_link`); inlining the payload keeps the call
/// site as small as the atomic-remove site already is.
fn enqueue_dependency_edge_delete(
    conn: &rusqlite::Connection,
    task_id: &str,
    depends_on_task_id: &str,
    version: &str,
    created_at: &str,
) -> AppResult<()> {
    let entity_id = lorvex_domain::TaskDependencyEdgeId::new(
        &lorvex_domain::TaskId::from_trusted_str(task_id),
        &lorvex_domain::TaskId::from_trusted_str(depends_on_task_id),
    );
    let payload = serde_json::json!({
        "task_id": task_id,
        "depends_on_task_id": depends_on_task_id,
        "version": version,
        "created_at": created_at,
    });
    crate::commands::enqueue_to_outbox_typed(
        conn,
        EDGE_TASK_DEPENDENCY,
        entity_id.as_str(),
        OP_DELETE,
        &payload,
    )
}

pub(crate) fn cleanup_task_dependency_refs_after_removal(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    updated_at: &str,
) -> AppResult<Vec<String>> {
    remove_task_from_all_deps_at(conn, task_id, updated_at)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;

    fn seed_task_for_dep(conn: &rusqlite::Connection, id: &str) {
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(id)
            .title("Dep target")
            .list_id(Some("inbox"))
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-04-01T08:00:00Z")
            .insert(conn);
    }

    /// Every cascade-cleanup tombstone for a `task_dependency` edge
    /// must carry `(version, created_at)` so peer LWW on the edge
    /// tombstone path has a coherent compare basis. Shipping only
    /// `(task_id, depends_on_task_id, updated_at)` from the cascade
    /// path (called from cancel, permanent_delete, purge_cancelled,
    /// empty_trash) would drop peers into the no-version branch and
    /// let them silently retain stale edges.
    #[test]
    fn cleanup_dependency_refs_emits_tombstones_with_version_and_created_at() {
        let conn = test_conn();
        // Seed three tasks: target (about to be deleted), incoming
        // dependent (depends on target), and outgoing dependency
        // (target depends on it).
        seed_task_for_dep(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000046");
        seed_task_for_dep(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000044");
        seed_task_for_dep(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000045");

        // Seed both an incoming and an outgoing dependency edge with
        // distinct (version, created_at) tuples so the assertions can
        // verify they round-trip into the tombstone payload verbatim.
        conn.execute(
            "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
             VALUES (?1, ?2, '0000000000000_0001_aaaaaaaaaaaaaaaa', '2026-04-02T09:00:00Z')",
            params![
                "01966a3f-7c8b-7d4e-8f3a-000000000046",
                "01966a3f-7c8b-7d4e-8f3a-000000000045"
            ],
        )
        .expect("seed outgoing dep");
        conn.execute(
            "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
             VALUES (?1, ?2, '0000000000000_0002_bbbbbbbbbbbbbbbb', '2026-04-03T09:00:00Z')",
            params![
                "01966a3f-7c8b-7d4e-8f3a-000000000044",
                "01966a3f-7c8b-7d4e-8f3a-000000000046"
            ],
        )
        .expect("seed incoming dep");

        let affected = cleanup_task_dependency_refs_after_removal(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000046".to_string()),
            "2026-04-04T10:00:00Z",
        )
        .expect("cleanup should succeed");

        // Affected returns the dependents whose dep set lost an edge —
        // that's the incoming-edge `task_id` (the dependent that no
        // longer depends on the deleted target).
        assert_eq!(
            affected,
            vec!["01966a3f-7c8b-7d4e-8f3a-000000000044".to_string()]
        );

        // Both edges must produce DELETE envelopes carrying the
        // pre-delete `created_at` and a non-empty `version`. The
        // `created_at` round-trips verbatim from the row's stored
        // value; `version` is re-stamped by the outbox enqueue layer
        // to the freshly-minted HLC for this tombstone (the
        // `enqueue_payload_internal_body` shared core overwrites the
        // payload `version` with the writer's `ctx.version` so the
        // wire envelope and the outbox row stay coherent — see
        // `lorvex_sync::outbox_enqueue` for the canonical contract).
        // The test pins the wire shape: composite ids, `created_at`
        // from the pre-delete row, and a non-empty `version`.
        // Shipping `updated_at` in place of `created_at` or dropping
        // `version` would drop peers into the no-version branch of
        // the LWW gate.
        for (entity_id, expected_created_at) in [
            (
                "01966a3f-7c8b-7d4e-8f3a-000000000046:01966a3f-7c8b-7d4e-8f3a-000000000045",
                "2026-04-02T09:00:00Z",
            ),
            (
                "01966a3f-7c8b-7d4e-8f3a-000000000044:01966a3f-7c8b-7d4e-8f3a-000000000046",
                "2026-04-03T09:00:00Z",
            ),
        ] {
            let payload_str: String = conn
                .query_row(
                    "SELECT payload FROM sync_outbox \
                     WHERE entity_type = 'task_dependency' AND entity_id = ?1 AND operation = 'delete' \
                     ORDER BY id DESC LIMIT 1",
                    params![entity_id],
                    |row| row.get(0),
                )
                .unwrap_or_else(|err| panic!("missing tombstone payload for {entity_id}: {err}"));
            let payload: serde_json::Value =
                serde_json::from_str(&payload_str).expect("parse tombstone payload");

            let version = payload.get("version").and_then(|v| v.as_str());
            assert!(
                version.is_some_and(|v| !v.is_empty()),
                "tombstone for {entity_id} must carry a non-empty `version` (got {payload})"
            );
            assert_eq!(
                payload.get("created_at").and_then(|v| v.as_str()),
                Some(expected_created_at),
                "tombstone for {entity_id} must carry pre-delete created_at (got {payload})"
            );
            assert!(
                payload
                    .get("depends_on_task_id")
                    .and_then(|v| v.as_str())
                    .is_some(),
                "tombstone for {entity_id} must carry composite-id pair (got {payload})"
            );
            assert!(
                payload.get("task_id").and_then(|v| v.as_str()).is_some(),
                "tombstone for {entity_id} must carry composite-id pair (got {payload})"
            );
        }

        // Edges are gone from the local table.
        let remaining: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM task_dependencies \
                 WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000046' OR depends_on_task_id = '01966a3f-7c8b-7d4e-8f3a-000000000046'",
                [],
                |row| row.get(0),
            )
            .expect("count remaining edges");
        assert_eq!(remaining, 0);
    }
}
