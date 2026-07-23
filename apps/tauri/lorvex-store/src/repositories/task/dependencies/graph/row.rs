//! Row → [`GraphNode`] mapper shared by the edge-driven and the
//! center-only zero-edge query paths.

use super::types::GraphNode;

pub(super) fn node_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<GraphNode> {
    Ok(GraphNode {
        id: row.get(0)?,
        title: row.get(1)?,
        status: row.get(2)?,
        priority: row.get(3)?,
        due_date: row.get(4)?,
        planned_date: row.get(5)?,
        list_id: row.get(6)?,
    })
}
