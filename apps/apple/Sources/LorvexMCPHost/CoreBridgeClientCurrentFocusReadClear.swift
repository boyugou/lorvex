import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadCurrentFocus(date: String) async throws -> Value? {
    guard let plan = try await service.loadCurrentFocus(date: date) else { return nil }
    return try await currentFocusValueWithTasks(from: plan)
  }

  func clearCurrentFocus(date: String) async throws -> Value {
    let receipt = try await mcpMutations.clearCurrentFocusForMcp(date: date)
    let previousIDs = receipt.previous.plan?.taskIDs ?? []
    return .object([
      "date": .string(date),
      "cleared": .bool(receipt.cleared),
      "current": .null,
      "previous": .object([
        "date": .string(date),
        "task_count": .int(previousIDs.count),
        "task_ids": .array(previousIDs.map(Value.string)),
        "tasks": .array(receipt.previous.tasks.map { Self.taskValue(from: $0) }),
      ]),
    ])
  }

  func currentFocusValueWithTasks(from plan: CurrentFocusPlan) async throws -> Value {
    var fields = Self.currentFocusValue(from: plan).objectValue ?? [:]
    var tasks: [Value] = []
    for id in plan.taskIDs {
      tasks.append(Self.taskValue(from: try await service.loadTask(id: id)))
    }
    fields["tasks"] = .array(tasks)
    return .object(fields)
  }

  static func currentFocusValueWithTasks(from projection: McpCurrentFocusProjection) -> Value {
    guard let plan = projection.plan else { return .null }
    var fields = Self.currentFocusValue(from: plan).objectValue ?? [:]
    fields["tasks"] = .array(projection.tasks.map { Self.taskValue(from: $0) })
    return .object(fields)
  }
}
