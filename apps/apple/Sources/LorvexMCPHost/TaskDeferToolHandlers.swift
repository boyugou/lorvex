import MCP

extension ToolRegistry {
  func deferTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "defer_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    guard let untilDate = arguments["until_date"]?.stringValue, !untilDate.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An until_date value is required.", toolName: "defer_task")
    }
    if let rejection = try await deferDayRejection(untilDate, toolName: "defer_task") {
      return rejection
    }

    let value: Value
    do {
      value = try await deferTaskPayload(
        id: id, untilDate: untilDate,
        structuredReason: try StrictScalarArguments.optionalString(
          arguments["structured_reason"], field: "structured_reason"),
        reason: try StrictScalarArguments.optionalString(arguments["reason"], field: "reason"))
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "defer_task")
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Deferred task: \(title)", value: value)
  }

  /// The error result for an `until_date` a deferral cannot use, or nil when
  /// it is a day after today. A deferral moves a task to a later day; a call
  /// naming today or an earlier day would leave the task on today's list
  /// while reporting it as moved.
  func deferDayRejection(_ untilDate: String, toolName: String) async throws -> CallTool.Result? {
    guard let date = CoreBridgeClient.plannedDateFormatter.date(from: untilDate) else {
      return Self.errorResult(
        code: "validation", message: "until_date must be a valid YYYY-MM-DD date.",
        toolName: toolName)
    }
    let today = try await coreBridge.service.getSessionContext().date
    guard CoreBridgeClient.plannedDateFormatter.string(from: date) > today else {
      return Self.errorResult(
        code: "validation",
        message: "until_date must be after today (\(today)): a deferral moves a task to a later "
          + "day. To put a task on today or an earlier day, set planned_date with update_task.",
        toolName: toolName)
    }
    return nil
  }
}
