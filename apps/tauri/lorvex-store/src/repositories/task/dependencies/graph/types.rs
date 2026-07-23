//! Public types for the dependency graph repository: graph node + edge
//! row carriers, query parameters, and result envelope.

/// `due_date` and `planned_date` use the typed
/// [`Date`](lorvex_domain::time::Date) newtype so the schema-storage
/// `YYYY-MM-DD` invariant is type-system enforced. Wire format is
/// unchanged because the wrapper serializes transparently.
#[derive(Debug, Clone, serde::Serialize)]
pub struct GraphNode {
    pub id: String,
    pub title: String,
    pub status: String,
    pub priority: Option<i64>,
    pub due_date: Option<lorvex_domain::time::Date>,
    pub planned_date: Option<lorvex_domain::time::Date>,
    pub list_id: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct GraphEdge {
    pub task_id: String,
    pub depends_on_task_id: String,
}

/// Parameters for scoping and capping the dependency graph query.
#[derive(Debug, Clone, Default)]
pub struct DependencyGraphParams {
    /// Center the graph on this task (shows its direct neighbourhood).
    pub task_id: Option<String>,
    /// Scope nodes to a specific list.
    pub list_id: Option<String>,
    /// Include completed/cancelled tasks in the graph.
    pub include_inactive: bool,
    /// Maximum number of nodes to return.
    pub limit_nodes: u32,
    /// Maximum number of edges to return.
    pub limit_edges: u32,
}

/// The computed dependency graph result.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DependencyGraphResult {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
    /// Tasks with no incoming dependencies (nothing they depend on).
    pub roots: Vec<String>,
    /// Tasks whose dependencies include unmet (open/someday) tasks.
    pub blocked: Vec<String>,
    /// Tasks that block others but are not themselves blocked.
    pub leaf_blockers: Vec<String>,
    pub truncated: bool,
}
