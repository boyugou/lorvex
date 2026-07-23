import Foundation
import MCP

extension ToolRegistry {
  func createTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let title = arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    else {
      return Self.errorResult(
        code: "validation",
        message: "A non-empty title is required.",
        toolName: "create_task"
      )
    }

    let value = try await createTaskPayload(arguments: arguments, title: title)
    let returnedTitle = value.objectValue?["title"]?.stringValue ?? title
    return successResult(text: "Created task: \(returnedTitle)", value: value)
  }
}
