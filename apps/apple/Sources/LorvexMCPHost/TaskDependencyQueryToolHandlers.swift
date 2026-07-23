import MCP

extension ToolRegistry {
  func dependencyGraphResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let taskID = try StrictScalarArguments.optionalString(
      arguments["task_id"], field: "task_id")
      ?? StrictScalarArguments.optionalString(arguments["id"], field: "id")
    let listID = try StrictScalarArguments.optionalString(arguments["list_id"], field: "list_id")
    let includeInactive = try StrictScalarArguments.bool(
      arguments["include_inactive"], field: "include_inactive", default: false)

    let value = try await coreBridge.getDependencyGraph(
      taskID: taskID,
      listID: listID,
      includeInactive: includeInactive
    )

    return fencedReadResult(text: "Loaded dependency graph.", value: value)
  }

  func upcomingTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let days = max(
      1, try StrictScalarArguments.int(arguments["days"], field: "days", default: 7))
    let limit = min(
      max(1, try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 100)),
      500)
    let offset = max(
      0, try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))
    let outputOptions = try TaskValueOptions.from(arguments: arguments, defaultShape: .compact)

    let value = try await coreBridge.getUpcomingTasks(
      days: days, limit: limit, offset: offset, outputOptions: outputOptions)

    return fencedReadResult(text: "Loaded upcoming tasks.", value: value)
  }

  func dueTaskRemindersResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let asOf = try StrictScalarArguments.optionalString(arguments["as_of"], field: "as_of")
    let limit = min(
      max(1, try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 50)),
      500)
    let offset = max(
      0, try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))

    let value = try await coreBridge.getDueTaskReminders(asOf: asOf, limit: limit, offset: offset)

    return fencedReadResult(text: "Loaded due reminders.", value: value)
  }

  func upcomingTaskRemindersResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let hours = min(
      max(1, try StrictScalarArguments.int(arguments["hours"], field: "hours", default: 24)),
      168)
    let limit = min(
      max(1, try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 50)),
      500)
    let offset = max(
      0, try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))

    let value =
      try await coreBridge.getUpcomingTaskReminders(hours: hours, limit: limit, offset: offset)

    return fencedReadResult(text: "Loaded upcoming reminders.", value: value)
  }
}
