import Foundation

extension LorvexSystemIntentRunner {
  public static func batchCompleteTasks(
    taskIDs: [LorvexTask.ID],
    core: any LorvexCoreServicing
  ) async throws -> TaskBatchLifecycleResult {
    try await core.batchCompleteTasks(ids: validatedTaskIDList(taskIDs))
  }

  public static func batchReopenTasks(
    taskIDs: [LorvexTask.ID],
    core: any LorvexCoreServicing
  ) async throws -> TaskBatchLifecycleResult {
    try await core.batchReopenTasks(ids: validatedTaskIDList(taskIDs))
  }

  public static func batchCreateTasks(
    titlesText: String,
    notes: String?,
    listID: LorvexList.ID?,
    priority: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    let resolvedListID = try listID.map { try validatedListID($0) }
    let resolvedPriority = try parsedPriority(priority)
    let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let titles = try parsedTaskTitleList(titlesText)
    // Bound the batch to the shared write-transaction cap: this runs the whole
    // set in one BEGIN IMMEDIATE, so an unbounded intent payload would starve
    // sync/UI writes just like an unbounded MCP batch would.
    guard titles.count <= LorvexBatchLimits.maxItems else {
      throw LorvexCoreError.validation(
        field: "titles",
        message:
          "Batch create accepts at most \(LorvexBatchLimits.maxItems) task titles per call; split larger sets across calls."
      )
    }
    let drafts = titles.map {
      TaskCreateDraft(
        title: $0,
        notes: trimmedNotes,
        listID: resolvedListID,
        priority: resolvedPriority
      )
    }
    return try await core.batchCreateTasks(drafts)
  }

  public static func batchDeferTasks(
    taskIDs: [LorvexTask.ID],
    until: String,
    core: any LorvexCoreServicing
  ) async throws -> TaskBatchLifecycleResult {
    try await core.batchDeferTasks(
      ids: validatedTaskIDList(taskIDs),
      until: parsedIntentDate(until),
      reason: nil,
      note: nil
    )
  }

  public static func batchMoveTasks(
    taskIDs: [LorvexTask.ID],
    listID: LorvexList.ID,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    try await core.batchMoveTasks(
      ids: validatedTaskIDList(taskIDs),
      toListID: validatedListID(listID)
    ).moved
  }

  private static func validatedTaskIDList(_ ids: [LorvexTask.ID]) throws -> [LorvexTask.ID] {
    guard !ids.isEmpty else {
      throw LorvexCoreError.validation(
        field: "task_ids", message: "At least one task ID is required.")
    }
    return ids
  }
}
