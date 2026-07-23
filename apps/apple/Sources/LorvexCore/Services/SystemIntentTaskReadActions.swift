import Foundation

extension LorvexSystemIntentRunner {
  public static func readTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.loadTask(id: validatedTaskID(id))
  }

  public static func readUpcomingTasks(
    daysAhead: Int?,
    limit: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    try await core.getUpcomingTasks(
      daysAhead: min(max(1, daysAhead ?? 7), 365),
      limit: min(max(1, limit ?? 25), 200)
    )
  }

  public static func searchTasks(
    query: String,
    status: String?,
    limit: Int?,
    offset: Int?,
    core: any LorvexCoreServicing
  ) async throws -> TaskSearchResult {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      throw LorvexCoreError.validation(
        field: "query", message: "A task search query is required.")
    }
    let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let resolvedStatus = normalizedStatus.flatMap { $0.isEmpty ? nil : $0 } ?? "all"
    let supported = Set(["all", "open", "in_progress", "actionable", "completed", "cancelled", "someday"])
    guard supported.contains(resolvedStatus) else {
      throw LorvexCoreError.validation(
        field: "status", message: "Unsupported task status filter.")
    }
    return try await core.searchTasks(
      query: trimmedQuery,
      status: resolvedStatus,
      limit: min(max(1, limit ?? 25), 200),
      offset: max(0, offset ?? 0)
    )
  }

  public static func listTasks(
    status: String?,
    listID: LorvexList.ID?,
    priority: Int?,
    text: String?,
    limit: Int?,
    offset: Int?,
    core: any LorvexCoreServicing
  ) async throws -> TaskPageResult {
    let trimmedListID = try listID.map { try validatedListID($0) }
    let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    let status = try validatedTaskListStatus(status)
    return try await core.listTasks(
      status: status,
      listID: trimmedListID,
      priority: try validatedPriority(priority),
      text: trimmedText?.isEmpty == false ? trimmedText : nil,
      limit: min(max(1, limit ?? 25), 200),
      offset: max(0, offset ?? 0)
    )
  }

  public static func readDeferredTasks(
    listID: LorvexList.ID?,
    limit: Int?,
    offset: Int?,
    core: any LorvexCoreServicing
  ) async throws -> TaskPageResult {
    let trimmedListID = try listID.map { id -> LorvexList.ID in
      try validatedListID(id)
    }
    return try await core.getDeferredTasks(
      listID: trimmedListID,
      limit: min(max(1, limit ?? 25), 200),
      offset: max(0, offset ?? 0)
    )
  }

  private static func validatedTaskListStatus(_ status: String?) throws -> String {
    let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let resolved = normalized.flatMap { $0.isEmpty ? nil : $0 } ?? "open"
    let supported = Set(["all", "open", "in_progress", "actionable", "completed", "cancelled", "someday"])
    guard supported.contains(resolved) else {
      throw LorvexCoreError.validation(
        field: "status", message: "Unsupported task status filter.")
    }
    return resolved
  }

  private static func validatedPriority(_ priority: Int?) throws -> Int? {
    guard let priority else { return nil }
    guard (1...3).contains(priority) else {
      throw LorvexCoreError.validation(
        field: "priority", message: "Task priority must be 1, 2, or 3.")
    }
    return priority
  }

  public static func readDependencyGraph(
    rootTaskID: LorvexTask.ID?,
    listID: LorvexList.ID?,
    includeInactive: Bool,
    core: any LorvexCoreServicing
  ) async throws -> DependencyGraph {
    try await core.getDependencyGraph(
      rootTaskID: try rootTaskID.map(validatedTaskID),
      listID: try listID.map(validatedListID),
      includeInactive: includeInactive
    )
  }
}
