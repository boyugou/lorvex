import Foundation
import MCP

extension ToolRegistry {
  func listsResult(arguments: [String: Value] = [:]) async throws -> CallTool.Result {
    let includeArchived = try StrictScalarArguments.bool(
      arguments["include_archived"], field: "include_archived", default: false)
    let values = try await listsPayload(includeArchived: includeArchived)
    return fencedReadResult(text: "Lorvex has \(values.count) list(s).", value: .object(["lists": .array(values)]))
  }

  func createListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let name = arguments["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A non-empty list name is required.",
        toolName: "create_list")
    }

    let list = try await createListPayload(
      name: name,
      description: try StrictScalarArguments.optionalString(
        arguments["description"], field: "description"),
      color: try StrictScalarArguments.optionalString(arguments["color"], field: "color"),
      icon: try StrictScalarArguments.optionalString(arguments["icon"], field: "icon"),
      aiNotes: try StrictScalarArguments.optionalString(arguments["ai_notes"], field: "ai_notes"),
      originalID: try CoreBridgeClient.strictImportOriginalID(
        arguments["original_id"], field: "original_id"))
    return successResult(text: "Created list: \(name)", value: list)
  }
}
