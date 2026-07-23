use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::Connection;
use std::collections::HashMap;

/// Check whether adding the proposed `depends_on` edges for `task_id`
/// would create a cycle in the dependency graph.
///
/// Semantics:
/// - `depends_on` = [B] means task_id depends on B, i.e. edge task_id -> B
///
/// A cycle exists when following dependency edges from any target of `depends_on`
/// eventually leads back to `task_id`.
///
/// Returns `Ok(())` if no cycle, or a `StoreError::Validation` describing the
/// cycle path.
pub fn validate_no_dependency_cycle(
    conn: &Connection,
    task_id: &TaskId,
    new_depends_on: &[String],
) -> Result<(), StoreError> {
    for dep_id in new_depends_on {
        if dep_id.as_str() == task_id.as_str() {
            return Err(StoreError::Validation(format!(
                "Circular dependency detected: task cannot depend on itself ({task_id})"
            )));
        }
        let dep_id_typed = TaskId::from_trusted(dep_id.clone());
        if let Some(cycle_path) = find_cycle_path(conn, task_id, &dep_id_typed)? {
            return Err(StoreError::Validation(format!(
                "Circular dependency detected: {}",
                cycle_path.join(" -> ")
            )));
        }
    }

    Ok(())
}

/// DFS from `start_id` to `target_id` following
/// `task_id → depends_on_task_id` edges. Returns the full cycle path
/// shaped as `[target_id, start_id, ..., target_id]` when one exists.
///
/// The DFS is deterministic across devices: every visited node's
/// outgoing edges are enumerated in `depends_on_task_id ASC` order,
/// and the stack walks children in that same ascending order
/// (pushed reverse + popped LIFO). The cycle path is reconstructed
/// from a `parents` map only when a cycle is actually found, so heap
/// allocation scales linearly with the visited frontier rather than
/// quadratically with depth × width as a per-frame `Vec<String>` would.
///
/// Determinism matters because the sync apply pipeline uses this to
/// elect a single cycle-break loser; if two peers enumerated the same
/// logical cycle as different paths they'd elect different HLC-min
/// edges and the cluster would silently fork. The pre-write
/// validation path does not strictly need determinism (it operates on
/// a single device's local input) but inherits the property for free
/// since both paths share this implementation.
pub fn find_cycle_path(
    conn: &Connection,
    target_id: &TaskId,
    start_id: &TaskId,
) -> Result<Option<Vec<String>>, StoreError> {
    // `parents[node] = Some(parent)` records the edge this DFS used
    // to first reach `node`. The root (`start_id`) maps to `None`.
    // Insertion into `parents` doubles as the visited-set: a node
    // with a `parents` entry has been (or is being) explored.
    let mut parents: HashMap<String, Option<String>> = HashMap::new();
    parents.insert(start_id.as_str().to_string(), None);
    let mut stack: Vec<String> = vec![start_id.as_str().to_string()];

    // Hoist the prepared statement out of the DFS loop. SQLite's
    // statement cache mitigates but doesn't eliminate the per-visit
    // re-prepare cost on a deep graph.
    let mut stmt = conn.prepare_cached(
        "SELECT depends_on_task_id FROM task_dependencies \
         WHERE task_id = ?1 \
         ORDER BY depends_on_task_id ASC",
    )?;

    while let Some(current) = stack.pop() {
        let deps: Vec<String> = stmt
            .query_map([&current], |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?;

        // Push in reverse so DFS pops children in ascending order
        // (the stack is LIFO and the SQL produced ascending).
        for dep in deps.into_iter().rev() {
            if dep.as_str() == target_id.as_str() {
                // Walk the parents map backward from `current` to
                // `start_id`, then frame with the implicit
                // `target → start` opener and the closing `target`
                // to produce `[target, start, ..., current, target]`.
                let mut tail: Vec<String> = Vec::new();
                let mut cursor: Option<&str> = Some(current.as_str());
                while let Some(node) = cursor {
                    tail.push(node.to_string());
                    cursor = parents.get(node).and_then(|p| p.as_deref());
                }
                tail.reverse();
                let mut cycle = Vec::with_capacity(tail.len().saturating_add(2));
                cycle.push(target_id.as_str().to_string());
                cycle.extend(tail);
                cycle.push(dep);
                return Ok(Some(cycle));
            }
            if !parents.contains_key(&dep) {
                parents.insert(dep.clone(), Some(current.clone()));
                stack.push(dep);
            }
        }
    }
    Ok(None)
}

#[cfg(test)]
mod tests;
