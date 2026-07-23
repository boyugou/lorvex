import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func getDependencyGraph(
    rootTaskID: LorvexTask.ID?,
    listID: LorvexList.ID?,
    includeInactive: Bool
  ) async throws -> DependencyGraph {
    try read { db in
      let params = TaskRepo.DependencyGraph.Params(
        taskId: rootTaskID,
        listId: listID,
        includeInactive: includeInactive,
        limitNodes: 500,
        limitEdges: 1000)
      let result = try TaskRepo.DependencyGraph.getDependencyGraph(db, params: params)
      let nodes = result.nodes.map { node in
        DependencyGraphNode(
          id: node.id,
          title: node.title,
          status: node.status,
          priority: node.priority.map(Int.init),
          dueDate: node.dueDate?.asString,
          plannedDate: node.plannedDate?.asString,
          listID: node.listId)
      }
      let edges = result.edges.map { edge in
        DependencyGraphEdge(from: edge.taskId, to: edge.dependsOnTaskId)
      }
      return DependencyGraph(
        nodes: nodes,
        edges: edges,
        roots: result.roots,
        blocked: result.blocked,
        leafBlockers: result.leafBlockers,
        truncated: result.truncated)
    }
  }
}
