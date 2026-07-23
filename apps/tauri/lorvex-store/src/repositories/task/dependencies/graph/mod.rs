//! Shared dependency graph repository — builds a subgraph of tasks linked
//! through `task_dependencies`, with computed annotations (roots, blocked,
//! leaf_blockers).
//!
//! Used by both the MCP server and (potentially) the Tauri app.
//!
//! Module layout:
//! - [`types`] — public row carriers ([`GraphNode`], [`GraphEdge`]) plus
//!   the [`DependencyGraphParams`] / [`DependencyGraphResult`] envelopes.
//! - [`row`] — `node_from_row` row mapper shared between the edge-driven
//!   and the center-only zero-edge paths.
//! - [`sql`] — `OnceLock`-cached edge SQL variants and the center-node
//!   SELECT template.
//! - [`orchestrator`] — [`get_dependency_graph`] orchestrator.

mod orchestrator;
mod row;
mod sql;
mod types;

#[cfg(test)]
mod tests;

pub use orchestrator::get_dependency_graph;
pub use types::{DependencyGraphParams, DependencyGraphResult, GraphEdge, GraphNode};
