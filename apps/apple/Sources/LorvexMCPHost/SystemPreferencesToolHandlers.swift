import LorvexCore
import LorvexDomain
import MCP

extension ToolRegistry {
  func getAllPreferencesResult() async throws -> CallTool.Result {
    let structured = try await allPreferencesPayload()
    return fencedReadResult(text: "Loaded Lorvex preferences.", value: structured)
  }

  func getPreferenceResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let key = arguments["key"]?.stringValue, !key.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "key is required.", toolName: "get_preference")
    }
    let structured = try await preferencePayload(key: key)
    return successResult(text: "Read preference \(key).", value: structured)
  }

  func setPreferenceResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let key = arguments["key"]?.stringValue, !key.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "key is required.", toolName: "set_preference")
    }
    // Only known configuration keys are writable over MCP. This rejects
    // arbitrary-key injection; internal/sync writes use the core directly and
    // are not bound by this allowlist.
    guard PreferenceKeys.isKnownPreferenceKey(key) else {
      return Self.errorResult(
        code: "validation",
        message:
          "Unknown preference key '\(key)'. set_preference only accepts known configuration keys.",
        toolName: "set_preference")
    }
    guard let value = arguments["value"]?.stringValue else {
      return Self.errorResult(
        code: "validation", message: "value is required.", toolName: "set_preference")
    }
    // Bound pathological payloads.
    guard value.utf8.count <= 32_768 else {
      return Self.errorResult(
        code: "validation",
        message: "Preference value is too large (max 32 KB).",
        toolName: "set_preference")
    }
    let structured = try await setPreferencePayload(key: key, value: value)
    return successResult(text: "Updated preference \(key).", value: structured)
  }

  func completeSetupResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let workingHours: String?
    if let rawWorkingHours = try StrictScalarArguments.optionalString(
      arguments["working_hours"], field: "working_hours"), !rawWorkingHours.isEmpty
    {
      guard let canonical = WorkingHoursPreference.canonicalStoredValue(from: rawWorkingHours) else {
        return Self.errorResult(
          code: "validation",
          message:
            "working_hours must be HH:MM-HH:MM or {\"start\":\"HH:MM\",\"end\":\"HH:MM\"}, with end after start.",
          toolName: "complete_setup")
      }
      workingHours = canonical
    } else {
      workingHours = nil
    }
    let defaultListID = try StrictScalarArguments.optionalString(
      arguments["default_list_id"], field: "default_list_id")
    let timezone = try StrictScalarArguments.optionalString(arguments["timezone"], field: "timezone")
    let structured = try await completeSetupPayload(
      workingHours: workingHours,
      defaultListID: defaultListID,
      timezone: timezone
    )
    return successResult(text: "Marked Lorvex setup as complete.", value: structured)
  }

  func deletePreferenceResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let key = arguments["key"]?.stringValue, !key.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "key is required.", toolName: "delete_preference")
    }
    guard PreferenceKeys.isKnownPreferenceKey(key) else {
      return Self.errorResult(
        code: "validation",
        message:
          "Unknown preference key '\(key)'. delete_preference only accepts known configuration keys.",
        toolName: "delete_preference")
    }
    let receipt = try await coreBridge.mcpMutations.deletePreferenceForMcp(key: key)
    let value = Value.object([
      "key": .string(key),
      "deleted": .bool(true),
      "previous": SecurityFencing.fencePreferenceValue(
        key: key, value: receipt.previous.map(CoreBridgeClient.jsonStringValue(_:)) ?? .null),
    ])
    return CallTool.Result(
      content: [
        .text(text: "Deleted preference '\(key)'.", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}
