//! Main entry point for the dependency graph repository:
//! [`get_dependency_graph`] orchestrates edge fetch → node fetch →
//! annotation derivation against the cached SQL variants in
//! [`super::sql`].

use crate::error::StoreError;
use lorvex_domain::naming;
use rusqlite::{
    named_params, params_from_iter, types::Value as SqlValue, Connection, OptionalExtension,
};
use std::collections::HashSet;

use super::row::node_from_row;
use super::sql::{center_node_sql, edges_sql_for_shape};
use super::types::{DependencyGraphParams, DependencyGraphResult, GraphEdge, GraphNode};

/// Build and return a dependency graph, scoped first then capped.
///
/// The query strategy is scope-first:
/// 1. Build the scoped edge set (by task_id neighbourhood, list_id, or status)
///    directly in SQL with LIMIT to avoid pulling the full graph
/// 2. Fetch only the nodes referenced by retained edges
/// 3. Apply node cap and edge cap
/// 4. Compute annotations on the capped subgraph
///
/// ## Pagination — intentionally NOT offered
///
/// every other unbounded read in the audit (`list_tasks`,
/// `get_archived_tasks`, `get_list_tasks_with_recent_completed`) was
/// converted to a `(rows, total_matching)` envelope so the UI can offer
/// "load more" controls. This function is the deliberate exception.
///
/// A graph traversal is not a list. Returning page 2 of a graph means
/// returning a different, partially-disconnected subgraph than page 1
/// — the `roots` / `blocked` / `leaf_blockers` annotations are derived
/// from the *captured* edge set, so a paginated cohort would compute
/// nodes-without-incoming-edges *within the page*, not within the true
/// graph. Showing `tasks/A` as a "root" in page 1 because page 2 (which
/// holds `tasks/B → tasks/A`) hasn't been fetched yet would be a
/// correctness bug at the rendering layer that no client-side
/// pagination control can paper over.
///
/// Bounding is therefore exposed as `limit_nodes` / `limit_edges` caps
/// (with a `truncated: bool` signal in [`DependencyGraphResult`]) so
/// callers can draw a partial graph and explicitly tell the user "this
/// view is truncated; narrow the scope" — instead of the misleading
/// "showing 1-50 of N" pagination affordance.
pub fn get_dependency_graph(
    conn: &Connection,
    params: &DependencyGraphParams,
) -> Result<DependencyGraphResult, StoreError> {
    let limit_nodes = params.limit_nodes.max(1) as usize;
    let limit_edges = params.limit_edges.max(1) as usize;

    // Edge query cap: fetch limit_edges + 1 to detect truncation.
    let edge_fetch_limit = limit_edges + 1;

    // Step 1: pick one of the 8 cached edge SQL variants — see
    // [`edges_sql_for_shape`] for the full matrix. Each call resolves
    // to a `&'static str` after the first init, so per-call work is
    // the variant lookup only.
    let edge_fetch_limit_i64 = edge_fetch_limit as i64;
    let edges_sql = edges_sql_for_shape(
        params.task_id.is_some(),
        params.list_id.is_some(),
        params.include_inactive,
    );

    let mut stmt = conn.prepare_cached(edges_sql)?;
    // Bind only the names referenced by the SQL — `named_params!` is
    // permissive about extras so we always include `center_id` and
    // `list_id` when the corresponding `Option` is `Some`. Use
    // `as_deref()` to borrow the inner `&str` without the redundant
    // `clone().unwrap_or_default()` round-trip the previous shape did
    // for both the present and absent branches.
    let center_id_str = params.task_id.as_deref().unwrap_or("");
    let list_id_str = params.list_id.as_deref().unwrap_or("");
    let raw_edges: Vec<(String, String)> =
        match (params.task_id.is_some(), params.list_id.is_some()) {
            (true, true) => stmt
                .query_map(
                    named_params! {
                        ":center_id": center_id_str,
                        ":list_id": list_id_str,
                        ":edge_fetch_limit": edge_fetch_limit_i64,
                    },
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )?
                .collect::<Result<Vec<_>, _>>()?,
            (true, false) => stmt
                .query_map(
                    named_params! {
                        ":center_id": center_id_str,
                        ":edge_fetch_limit": edge_fetch_limit_i64,
                    },
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )?
                .collect::<Result<Vec<_>, _>>()?,
            (false, true) => stmt
                .query_map(
                    named_params! {
                        ":list_id": list_id_str,
                        ":edge_fetch_limit": edge_fetch_limit_i64,
                    },
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )?
                .collect::<Result<Vec<_>, _>>()?,
            (false, false) => stmt
                .query_map(
                    named_params! {
                        ":edge_fetch_limit": edge_fetch_limit_i64,
                    },
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )?
                .collect::<Result<Vec<_>, _>>()?,
        };

    // Handle task_id centered query with zero edges: return single-node graph
    // (only if the center task passes the active/inactive filter and list filter).
    if raw_edges.is_empty() {
        if let Some(ref center_id) = params.task_id {
            // Single static SQL: bind both filters as predicates so
            // the prepare_cached slot is the same for every
            // `(list_id present?, include_inactive?)` combination.
            // Hoisted to a module-level OnceLock since the only
            // template parameter is the static `ACTIVE_STATUS_SQL_LIST`
            // constant, so flipping `include_inactive` from the UI
            // does not churn the statement cache.
            let mut stmt = conn.prepare_cached(center_node_sql())?;
            let include_inactive_flag: i64 = i64::from(params.include_inactive);
            let center_node = stmt
                .query_row(
                    params_from_iter(
                        [
                            SqlValue::Text(center_id.clone()),
                            params
                                .list_id
                                .as_ref()
                                .map_or(SqlValue::Null, |s| SqlValue::Text(s.clone())),
                            SqlValue::Integer(include_inactive_flag),
                        ]
                        .iter(),
                    ),
                    node_from_row,
                )
                .optional()?;
            if let Some(node) = center_node {
                let node_id = node.id.clone();
                return Ok(DependencyGraphResult {
                    nodes: vec![node],
                    edges: Vec::new(),
                    roots: vec![node_id],
                    blocked: Vec::new(),
                    leaf_blockers: Vec::new(),
                    truncated: false,
                });
            }
        }
        return Ok(DependencyGraphResult {
            nodes: Vec::new(),
            edges: Vec::new(),
            roots: Vec::new(),
            blocked: Vec::new(),
            leaf_blockers: Vec::new(),
            truncated: false,
        });
    }

    // Step 2: Detect edge truncation and apply cap. Move tuple
    // contents directly into `GraphEdge` via `into_iter().take()` so
    // each kept edge is moved once into the new struct rather than
    // double-cloned (once here, once by the node-collection loop
    // below).
    let edges_truncated = raw_edges.len() > limit_edges;
    let capped_edges: Vec<GraphEdge> = raw_edges
        .into_iter()
        .take(limit_edges)
        .map(|(from, to)| GraphEdge {
            task_id: from,
            depends_on_task_id: to,
        })
        .collect();

    // Collect unique node IDs from capped edges only. Borrow into the
    // set so we don't clone strings just to fingerprint them; the
    // dedupe still produces a `HashSet<String>` because `node_ids`
    // outlives `capped_edges`.
    let mut node_ids: HashSet<String> = HashSet::new();
    for e in &capped_edges {
        if !node_ids.contains(e.task_id.as_str()) {
            node_ids.insert(e.task_id.clone());
        }
        if !node_ids.contains(e.depends_on_task_id.as_str()) {
            node_ids.insert(e.depends_on_task_id.clone());
        }
    }

    // Step 3: Apply node cap and fetch task details.
    //
    // Truncation runs in SQL via `LIMIT` after `ORDER BY
    // priority_effective` so a graph wider than `limit_nodes` drops
    // its lowest-priority candidates rather than its lex-latest ids
    // — Rust-side truncation on an `id ASC` sort could keep low-
    // priority nodes simply because their UUIDs sorted earlier than
    // higher-priority neighbors.
    //
    // Center anchoring is also expressed in SQL: a `CASE WHEN
    // t.id = ?2 THEN 0 ELSE 1 END` leading sort key forces the center
    // row (when present) to position 0, then the rest follow priority.
    // The `LIMIT ?3` therefore keeps the center plus the top
    // `(limit - 1)` highest-priority neighbors. When `?2` is NULL the
    // CASE evaluates to 1 for every row and the LIMIT cuts purely
    // by priority.
    //
    // Center may have been truncated out of `capped_edges` (and so
    // absent from `node_ids`); insert it into the candidate list
    // explicitly so the SQL CASE has something to match. The single
    // extra entry is bounded.
    //
    // O(1) HashSet lookup before draining
    // `node_ids` into the Vec, instead of an O(N) linear scan over
    // the post-collected `node_id_list`. A graph capped at 500 nodes
    // would otherwise spend ~500 string compares to insert one
    // element; the set lookup is one hash + bucket compare.
    let center_id_to_append = params.task_id.as_deref().and_then(|cid| {
        if node_ids.contains(cid) {
            None
        } else {
            Some(cid.to_string())
        }
    });
    let mut node_id_list: Vec<String> = node_ids.into_iter().collect();
    if let Some(cid) = center_id_to_append {
        node_id_list.push(cid);
    }
    let nodes_truncated = node_id_list.len() > limit_nodes;

    // Bind the id list as a single JSON array parameter joined via
    // `json_each` so the SQL stays fixed-shape. A placeholder count
    // proportional to `limit_nodes` (50–500 typical) would produce a
    // distinct `prepare_cached` cache entry per page size, ballooning
    // the connection's statement cache and missing the hot path for
    // paginated re-renders. The `json_each` form keeps one cache
    // entry that serves every page size.
    //
    // The `priority_effective` virtual generated column lets the
    // ORDER BY stream from the
    // `idx_tasks_status_priority_effective_due` index instead of
    // sorting. Migration 009 standardized on 4 as the NULL-priority
    // sentinel via `priority_effective`; inlining
    // `COALESCE(t.priority, 3)` would both skip the index and collide
    // with real P3 priorities.
    let id_list_json = serde_json::to_string(&node_id_list)
        .map_err(|e| StoreError::Serialization(format!("dependency-graph node id list: {e}")))?;
    let center_id_param = params.task_id.as_deref();
    let limit_nodes_param = i64::try_from(limit_nodes).map_err(|_| {
        StoreError::Validation(format!("limit_nodes value {limit_nodes} exceeds i64 range"))
    })?;
    let mut stmt = conn.prepare_cached(
        "SELECT t.id, t.title, t.status, t.priority, t.due_date, t.planned_date, t.list_id \
         FROM tasks t \
         JOIN json_each(?1) AS j ON t.id = j.value \
         ORDER BY \
             CASE WHEN ?2 IS NOT NULL AND t.id = ?2 THEN 0 ELSE 1 END ASC, \
             t.priority_effective ASC, \
             t.created_at DESC, \
             t.id ASC \
         LIMIT ?3",
    )?;
    let nodes: Vec<GraphNode> = stmt
        .query_map(
            params_from_iter(
                [
                    SqlValue::Text(id_list_json),
                    center_id_param.map_or(SqlValue::Null, |s| SqlValue::Text(s.to_string())),
                    SqlValue::Integer(limit_nodes_param),
                ]
                .iter(),
            ),
            node_from_row,
        )?
        .collect::<Result<Vec<_>, _>>()?;

    let fetched_ids: HashSet<&str> = nodes.iter().map(|n| n.id.as_str()).collect();

    // Re-filter edges to only reference fetched nodes (node cap may have dropped some).
    let edges: Vec<GraphEdge> = capped_edges
        .into_iter()
        .filter(|e| {
            fetched_ids.contains(e.task_id.as_str())
                && fetched_ids.contains(e.depends_on_task_id.as_str())
        })
        .collect();

    // Step 4: Compute annotations.
    let mut depended_on: HashSet<&str> = HashSet::new();
    let mut has_deps: HashSet<&str> = HashSet::new();
    for e in &edges {
        has_deps.insert(&e.task_id);
        depended_on.insert(&e.depends_on_task_id);
    }

    let roots: Vec<String> = nodes
        .iter()
        .filter(|n| !has_deps.contains(n.id.as_str()))
        .map(|n| n.id.clone())
        .collect();

    let node_status: std::collections::HashMap<&str, &str> = nodes
        .iter()
        .map(|n| (n.id.as_str(), n.status.as_str()))
        .collect();

    let mut blocked_set: HashSet<&str> = HashSet::new();
    for e in &edges {
        if let Some(&status) = node_status.get(e.depends_on_task_id.as_str()) {
            if status == naming::STATUS_OPEN || status == naming::STATUS_SOMEDAY {
                blocked_set.insert(&e.task_id);
            }
        }
    }

    // Derive blocked and leaf_blockers by iterating `nodes` in order so the
    // output is fully deterministic (nodes are already sorted by the SQL
    // ORDER BY plus center-first pinning).
    let blocked: Vec<String> = nodes
        .iter()
        .filter(|n| blocked_set.contains(n.id.as_str()))
        .map(|n| n.id.clone())
        .collect();

    let leaf_blockers: Vec<String> = nodes
        .iter()
        .filter(|n| depended_on.contains(n.id.as_str()) && !has_deps.contains(n.id.as_str()))
        .map(|n| n.id.clone())
        .collect();

    Ok(DependencyGraphResult {
        nodes,
        edges,
        roots,
        blocked,
        leaf_blockers,
        truncated: nodes_truncated || edges_truncated,
    })
}
