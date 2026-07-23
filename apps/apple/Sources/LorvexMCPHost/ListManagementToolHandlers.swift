import Foundation
import MCP

extension ToolRegistry {
  func updateListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A list id is required.", toolName: "update_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let name = try StrictScalarArguments.optionalString(arguments["name"], field: "name")
    let description = try StrictScalarArguments.optionalString(
      arguments["description"], field: "description")
    let color = try StrictScalarArguments.optionalString(arguments["color"], field: "color")
    let icon = try StrictScalarArguments.optionalString(arguments["icon"], field: "icon")

    let list = try await updateListPayload(
      id: id,
      name: name,
      description: description,
      color: color,
      icon: icon,
      aiNotes: nil
    )
    return successResult(text: "Updated list \(id).", value: list)
  }

  func setListAINotesResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let id = arguments["list_id"]?.stringValue, !id.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A list_id is required.", toolName: "set_list_ai_notes")
    }
    guard let notes = arguments["notes"]?.stringValue else {
      return Self.errorResult(
        code: "validation",
        message: "A notes value is required; pass an empty string to clear.",
        toolName: "set_list_ai_notes")
    }

    let list = try await setListAINotesPayload(id: id, notes: notes)
    return successResult(text: "Set list AI context \(id).", value: list)
  }

  func deleteListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A list id is required.", toolName: "delete_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let deleted = try await deleteListPayload(id: id)
    return successResult(text: "Deleted list \(id).", value: deleted)
  }

  func archiveListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A list id is required.", toolName: "archive_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let list = try await archiveListPayload(id: id)
    return successResult(text: "Archived list \(id).", value: list)
  }

  func unarchiveListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A list id is required.", toolName: "unarchive_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let list = try await unarchiveListPayload(id: id)
    return successResult(text: "Unarchived list \(id).", value: list)
  }

  func getListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A list id is required.", toolName: "get_list") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let list = try await listPayload(id: id)
    return fencedReadResult(text: "Loaded list \(id).", value: list)
  }

  func getListHealthSnapshotResult() async throws -> CallTool.Result {
    let snapshot = try await listHealthSnapshotPayload()
    let totalLists: Int = {
      guard case .object(let object) = snapshot else { return 0 }
      return object["total_lists"]?.intValue ?? 0
    }()
    return fencedReadResult(text: "Health for \(totalLists) list(s).", value: snapshot)
  }

  func reorderListsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let listIDs = try StrictArgumentArray.requiredUniqueStrings(
      arguments["list_ids"], field: "list_ids")
    guard !listIDs.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty list_ids array is required.",
        toolName: "reorder_lists")
    }

    let values = try await reorderListsPayload(orderedIDs: listIDs)
    return successResult(
      text: "Reordered \(values.count) list(s).", value: .object(["lists": .array(values)]))
  }
}
