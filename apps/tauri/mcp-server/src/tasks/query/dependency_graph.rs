use crate::contract::{
    GetDependencyGraphArgs, DEPENDENCY_GRAPH_LIMIT_EDGES_CAP, DEPENDENCY_GRAPH_LIMIT_EDGES_DEFAULT,
    DEPENDENCY_GRAPH_LIMIT_NODES_CAP, DEPENDENCY_GRAPH_LIMIT_NODES_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::bounded_limit;
use lorvex_store::repositories::task::dependencies::graph::{self, DependencyGraphParams};
use rusqlite::Connection;
use serde_json::json;

pub(crate) fn get_dependency_graph(
    conn: &Connection,
    args: GetDependencyGraphArgs,
) -> Result<String, McpError> {
    let limit_nodes = bounded_limit(
        args.limit_nodes,
        DEPENDENCY_GRAPH_LIMIT_NODES_DEFAULT,
        DEPENDENCY_GRAPH_LIMIT_NODES_CAP,
    );
    let limit_edges = bounded_limit(
        args.limit_edges,
        DEPENDENCY_GRAPH_LIMIT_EDGES_DEFAULT,
        DEPENDENCY_GRAPH_LIMIT_EDGES_CAP,
    );

    let params = DependencyGraphParams {
        task_id: args.task_id,
        list_id: args.list_id,
        include_inactive: args.include_inactive,
        limit_nodes,
        limit_edges,
    };

    let result = graph::get_dependency_graph(conn, &params)?;

    // #2422: fence user-origin task titles on each node.
    let mut nodes = serde_json::to_value(&result.nodes)?;
    if let Some(arr) = nodes.as_array_mut() {
        for node in arr.iter_mut() {
            if let Some(obj) = node.as_object_mut() {
                crate::system::text_hygiene::fence_object_field(obj, "title");
            }
        }
    }

    let payload = json!({
        "node_count": result.nodes.len(),
        "edge_count": result.edges.len(),
        "nodes": nodes,
        "edges": result.edges.iter().map(|e| json!({
            "from": e.task_id,
            "to": e.depends_on_task_id,
        })).collect::<Vec<_>>(),
        "roots": result.roots,
        "blocked": result.blocked,
        "leaf_blockers": result.leaf_blockers,
        "truncated": result.truncated,
    });
    Ok(serde_json::to_string(&payload)?)
}
