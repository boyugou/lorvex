import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Pre-write validators for `task_dependency` edges.
public enum DependencyValidation {
  /// Check whether adding the proposed `dependsOn` edges for `taskId` would
  /// create a cycle in the dependency graph. Semantics: `dependsOn = [B]`
  /// means edge `taskId → B`. Returns normally on no cycle; throws
  /// ``StoreError/validation(_:)`` with a fixed message on cycle.
  public static func validateNoDependencyCycle(
    _ db: Database, taskId: TaskId, newDependsOn: [String]
  ) throws {
    for depId in newDependsOn {
      if depId == taskId.asString {
        throw StoreError.validation(
          "Circular dependency detected: task cannot depend on itself (\(taskId))")
      }
      let depIdTyped = TaskId(trusted: depId)
      if let cyclePath = try findCyclePath(db, targetId: taskId, startId: depIdTyped) {
        throw StoreError.validation(
          "Circular dependency detected: " + cyclePath.joined(separator: " -> "))
      }
    }
  }

  /// DFS from `startId` to `targetId` following `task_id → depends_on_task_id`
  /// edges. Returns the full cycle path shaped as
  /// `[targetId, startId, ..., targetId]` when one exists. Outgoing edges
  /// are enumerated in `depends_on_task_id ASC` order; the LIFO stack walks
  /// children in that same ascending order (pushed reverse + popped LIFO),
  /// which makes the DFS deterministic across devices — sync's cycle-break
  /// loser election depends on this.
  public static func findCyclePath(
    _ db: Database, targetId: TaskId, startId: TaskId
  ) throws -> [String]? {
    var parents: [String: String?] = [:]
    parents[startId.asString] = .some(nil)
    var stack: [String] = [startId.asString]

    while let current = stack.popLast() {
      let deps: [String] = try String.fetchAll(
        db,
        sql:
          "SELECT depends_on_task_id FROM task_dependencies "
          + "WHERE task_id = ?1 ORDER BY depends_on_task_id ASC",
        arguments: [current])

      // Push in reverse so the LIFO stack pops children in ascending order.
      for dep in deps.reversed() {
        if dep == targetId.asString {
          var tail: [String] = []
          var cursor: String? = current
          while let node = cursor {
            tail.append(node)
            if let parent = parents[node], let p = parent {
              cursor = p
            } else {
              cursor = nil
            }
          }
          tail.reverse()
          var cycle: [String] = []
          cycle.reserveCapacity(tail.count + 2)
          cycle.append(targetId.asString)
          cycle.append(contentsOf: tail)
          cycle.append(dep)
          return cycle
        }
        if parents[dep] == nil {
          parents[dep] = .some(current)
          stack.append(dep)
        }
      }
    }
    return nil
  }
}
