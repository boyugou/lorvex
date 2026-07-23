import Foundation
import MCP

extension ToolRegistry {
  func moveTaskToListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "move_task_to_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    guard let listID = arguments["list_id"]?.stringValue, !listID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A list_id value is required.", toolName: "move_task_to_list")
    }

    let value: Value
    do {
      value = try await moveTaskToListPayload(id: id, listID: listID)
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "move_task_to_list")
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return CallTool.Result(
      content: [
        .text(text: "Moved task to list: \(title)", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}
