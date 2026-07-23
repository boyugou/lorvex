import Foundation

extension LorvexSystemIntentRunner {
  public static func addTaskChecklistItem(
    taskID: LorvexTask.ID,
    text: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let id = try validatedTaskID(taskID)
    let trimmed = try validatedTaskText(text, label: "checklist text")
    return try await core.addTaskChecklistItem(taskID: id, text: trimmed)
  }

  public static func toggleTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    completed: Bool,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.toggleTaskChecklistItem(
      itemID: validatedChecklistItemID(itemID),
      completed: completed
    )
  }

  public static func updateTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    text: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let trimmed = try validatedTaskText(text, label: "checklist text")
    return try await core.updateTaskChecklistItem(
      itemID: validatedChecklistItemID(itemID),
      text: trimmed
    )
  }

  public static func removeTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.removeTaskChecklistItem(itemID: validatedChecklistItemID(itemID))
  }

  private static func validatedChecklistItemID(_ id: TaskChecklistItem.ID) throws
    -> TaskChecklistItem.ID
  {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "item_id", message: "A checklist item ID is required.")
    }
    return trimmed
  }
}
