import Foundation
import MCP

extension ToolRegistry {
  func updateTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "update_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    // `title` is optional: an absent key keeps the task's current title (the
    // bridge falls back to the loaded task), while an explicitly supplied but
    // empty/whitespace title is a validation error rather than a silent wipe.
    let title: String?
    if arguments.keys.contains("title") {
      let trimmed = arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let trimmed, !trimmed.isEmpty else {
        return Self.errorResult(
          code: "validation",
          message: "A non-empty title is required.",
          toolName: "update_task"
        )
      }
      title = trimmed
    } else {
      title = nil
    }
    let priority: Int?
    do {
      priority = try Self.requiredPriorityNumber(from: arguments["priority"])
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error),
        message: Self.errorMessage(for: error),
        toolName: "update_task"
      )
    }
    // `tags` wins over `tags_set` when both are present — the same precedence
    // create uses, so the two aliases resolve consistently across all tools.
    let tags: [String]?
    let dependsOn: [String]?
    do {
      tags = try StrictArgumentArray.optionalStrings(
        arguments["tags"] ?? arguments["tags_set"], field: "tags")
      dependsOn = try StrictArgumentArray.optionalStrings(
        arguments["depends_on"], field: "depends_on")
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error),
        message: Self.errorMessage(for: error),
        toolName: "update_task"
      )
    }

    let value: Value
    do {
      value = try await updateTaskPayload(
        id: id,
        title: title,
        priority: priority,
        tags: tags,
        dependsOn: dependsOn,
        arguments: arguments
      )
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "update_task")
    }
    let returnedTitle = value.objectValue?["title"]?.stringValue ?? title ?? id
    return successResult(text: "Updated task: \(returnedTitle)", value: value)
  }
}
