//! Dependency graph snapshot rendering.
//!
//! Renders a `DependencyGraphSnapshot` as a banner + ASCII tree on the
//! text path and as a `query.tasks.dependency_graph` envelope on the
//! JSON path. The tree layout, cycle-guard, and orphan-flush rules live
//! in `render_dependency_tree` / `render_dep_subtree` — see those for
//! the box-drawing and traversal invariants.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::{DependencyGraphNode, DependencyGraphSnapshot};
use crate::render::format::{probe_terminal_cols, style_empty_hint, truncate_to_cols};

pub(crate) fn render_dependency_graph_snapshot(
    db_path: &Path,
    snapshot: &DependencyGraphSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Dependency Graph\nDB: {}\nNodes: {} / limit {}\nEdges: {} / limit {}{}\n",
                db_path.display(),
                snapshot.node_count,
                snapshot.limit_nodes,
                snapshot.edge_count,
                snapshot.limit_edges,
                if snapshot.truncated {
                    " (truncated)"
                } else {
                    ""
                },
            );
            if snapshot.nodes.is_empty() {
                rendered.push_str("Graph:\n");
                rendered.push_str(&style_empty_hint(
                    "No dependency edges yet — add one with `lorvex task depend <blocker-id> --blocks <task-id>`.",
                ));
            } else {
                rendered.push_str("Graph:\n");
                // Probe terminal width once at render entry. On a TTY
                // (interactive shell), wide cluster rows clip to the
                // visible width with a trailing `…`. On non-TTY paths
                // (snapshot tests, pipes, CI logs), the probe returns
                // `None` and we emit the canonical un-truncated form.
                let max_cols = probe_terminal_cols();
                rendered.push_str(&render_dependency_tree(snapshot, max_cols));
            }
            let _ = writeln!(rendered, "Roots: {}", snapshot.roots.join(", "));
            let _ = writeln!(rendered, "Blocked: {}", snapshot.blocked.join(", "));
            let _ = writeln!(
                rendered,
                "Leaf blockers: {}",
                snapshot.leaf_blockers.join(", ")
            );
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.tasks.dependency_graph",
            db_path,
            json!({
                "dependency_graph": snapshot,
            }),
        ),
    }
}

/// Render a `DependencyGraphSnapshot` as an ASCII tree rooted at the
/// snapshot's `roots` (tasks with no outgoing dependency edges — they
/// depend on nothing, so they are ready to start). Children of node
/// `N` are the tasks whose edges point at `N` (i.e. edges where
/// `to == N`, since `from` is the dependent and `to` is the blocker);
/// in tree terms "doing N unblocks these descendants."
///
/// Layout invariants:
///   * `├──` for non-final siblings, `└──` for the last sibling at
///     each level, with `│ ` / ` ` continuation pads — the
///     standard Unicode-box drawing conventions used by `tree(1)`.
///   * Each row carries the task id, the title, the status, the list
///     id, and a `[blocks N]` annotation when the node has dependents
///     that have not been completed yet — so a glance gives "which
///     branches still gate other work."
///   * Cycles are guarded by a per-traversal `visited` set: if a node
///     re-appears during DFS it is rendered with a `(cycle)` suffix
///     and not re-recursed into. The repository already rejects cycle
///     additions at write time, but the renderer must stay safe even
///     if a malformed snapshot reaches the human path.
///   * Isolated nodes (not in `roots`, never referenced as a child)
///     are flushed after the roots so the snapshot never silently
///     drops a node.
fn render_dependency_tree(snapshot: &DependencyGraphSnapshot, max_cols: Option<u16>) -> String {
    use std::collections::{HashMap, HashSet};

    let node_by_id: HashMap<&str, &DependencyGraphNode> =
        snapshot.nodes.iter().map(|n| (n.id.as_str(), n)).collect();

    // children[blocker] = [dependent, …] in declared edge order.
    let mut children: HashMap<&str, Vec<&str>> = HashMap::new();
    for edge in &snapshot.edges {
        children
            .entry(edge.to.as_str())
            .or_default()
            .push(edge.from.as_str());
    }

    // Track which nodes the DFS visits so any node that's neither a
    // root nor reachable from one still surfaces under an "Isolated"
    // branch rather than vanishing.
    let mut visited_globally: HashSet<&str> = HashSet::new();

    let mut out = String::new();
    let root_ids: Vec<&str> = snapshot.roots.iter().map(String::as_str).collect();
    let root_count = root_ids.len();
    for (idx, root_id) in root_ids.iter().enumerate() {
        let is_last = idx + 1 == root_count;
        let mut path_visited: HashSet<&str> = HashSet::new();
        render_dep_subtree(
            &mut out,
            root_id,
            "",
            is_last,
            true,
            &node_by_id,
            &children,
            &mut path_visited,
            &mut visited_globally,
            max_cols,
        );
    }

    // Surface any node the DFS missed (orphans / detached subtrees)
    // under a separate header — better than dropping them and quietly
    // diverging from `Nodes: N` in the banner.
    let orphans: Vec<&DependencyGraphNode> = snapshot
        .nodes
        .iter()
        .filter(|n| !visited_globally.contains(n.id.as_str()))
        .collect();
    if !orphans.is_empty() {
        out.push_str("Isolated:\n");
        let orphan_count = orphans.len();
        for (idx, node) in orphans.iter().enumerate() {
            let is_last = idx + 1 == orphan_count;
            let mut path_visited: HashSet<&str> = HashSet::new();
            render_dep_subtree(
                &mut out,
                node.id.as_str(),
                "",
                is_last,
                true,
                &node_by_id,
                &children,
                &mut path_visited,
                &mut visited_globally,
                max_cols,
            );
        }
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn render_dep_subtree<'a>(
    out: &mut String,
    node_id: &'a str,
    prefix: &str,
    is_last: bool,
    is_root: bool,
    node_by_id: &std::collections::HashMap<&'a str, &'a DependencyGraphNode>,
    children: &std::collections::HashMap<&'a str, Vec<&'a str>>,
    path_visited: &mut std::collections::HashSet<&'a str>,
    visited_globally: &mut std::collections::HashSet<&'a str>,
    max_cols: Option<u16>,
) {
    let connector = if is_root {
        ""
    } else if is_last {
        "└── "
    } else {
        "├── "
    };

    let cycle = !path_visited.insert(node_id);
    visited_globally.insert(node_id);

    let label = node_by_id.get(node_id).map_or_else(
        || format!("{node_id} (missing)"),
        |node| {
            let direct_children = children.get(node_id).map_or(0, Vec::len);
            let blocks = if direct_children > 0 {
                format!(" [blocks {direct_children}]")
            } else {
                String::new()
            };
            format!(
                "{}: {} ({}, list: {}){}",
                node.id, node.title, node.status, node.list_id, blocks,
            )
        },
    );
    let cycle_suffix = if cycle { " (cycle)" } else { "" };
    // Compose the full row, then truncate to the probed terminal width.
    // Truncation is a no-op on the non-TTY snapshot/pipe path because
    // `max_cols` is `None` — the prefix + box-drawing characters + label
    // come through verbatim. On an interactive terminal a 200-char title
    // clips to "…" at the visible edge instead of wrapping into the
    // next row.
    let row = format!("{prefix}{connector}{label}{cycle_suffix}");
    let _ = writeln!(out, "{}", truncate_to_cols(&row, max_cols));

    if cycle {
        return;
    }

    let Some(child_ids) = children.get(node_id) else {
        path_visited.remove(node_id);
        return;
    };
    let total = child_ids.len();
    let next_prefix = if is_root {
        String::new()
    } else if is_last {
        format!("{prefix}    ")
    } else {
        format!("{prefix}│   ")
    };
    for (idx, child) in child_ids.iter().enumerate() {
        let child_is_last = idx + 1 == total;
        render_dep_subtree(
            out,
            child,
            &next_prefix,
            child_is_last,
            false,
            node_by_id,
            children,
            path_visited,
            visited_globally,
            max_cols,
        );
    }
    path_visited.remove(node_id);
}
