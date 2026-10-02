import Foundation

extension LorvexSystemIntentRunner {
  public static func captureTask(
    title: String,
    notes: String?,
    core: any LorvexCoreServicing
  ) async throws -> String {
    try await captureTaskReturningTask(title: title, notes: notes, core: core).title
  }

  /// Capture variant that echoes the freshly created task rather than just its
  /// title, so a returning surface (a Shortcut chaining on the new task) can act
  /// on the real entity.
  public static func captureTaskReturningTask(
    title: String,
    notes: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LorvexCoreError.emptyTitle }
    return try await core.createTask(title: trimmed, notes: notes ?? "")
  }

  public static func completeTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    // The returning-task variant echoes the mutated task directly; the
    // today-snapshot form excludes non-open tasks, so a lookup there would
    // fall back to the raw id in the spoken/displayed confirmation.
    return try await core.completeTaskReturningTask(id: taskID).title
  }

  public static func cancelTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    return try await core.cancelTaskReturningTask(id: taskID).title
  }

  public static func reopenTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    return try await core.reopenTaskReturningTask(id: taskID).title
  }

  public static func startTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    return try await core.startTaskReturningTask(id: taskID).title
  }

  public static func pauseTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    return try await core.pauseTaskReturningTask(id: taskID).title
  }

  public static func deferTaskUntilTomorrow(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let taskID = try validatedTaskID(id)
    let logicalDay = try await core.getSessionContext().date
    let storageTomorrow = try storageDate(byAddingDays: 1, toLogicalDay: logicalDay)
    return try await core.deferTaskReturningTask(
      id: taskID, until: storageTomorrow, reason: nil
    ).title
  }

  public static func appendToTaskBody(
    id: LorvexTask.ID,
    text: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    let trimmed = try validatedTaskText(text, label: "body text")
    return try await core.appendToTaskBody(taskID: taskID, additionalNotes: trimmed)
  }

  /// Replace the task's reminders with `reminderAts`, ISO-8601 timestamps.
  /// Blank entries are dropped; at least one reminder must remain.
  public static func setTaskReminders(
    id: LorvexTask.ID,
    reminderAts: [String],
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    let reminders = reminderAts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !reminders.isEmpty else {
      throw LorvexCoreError.validation(
        field: "reminders", message: "At least one reminder timestamp is required.")
    }
    return try await core.setTaskReminders(taskID: taskID, reminderAts: reminders)
  }

  /// Plans the task for the configured product day, which puts it on Today.
  public static func planTaskForToday(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    let context = try await core.getSessionContext()
    guard let today = LorvexDateFormatters.ymdUTC.date(from: context.date) else {
      throw LorvexCoreError.validation(field: "date", message: "Today's date is unavailable.")
    }
    var draft = TaskUpdateDraft(id: taskID)
    draft.plannedDate = .set(today)
    return try await core.updateTask(draft)
  }

  public static func validatedTaskID(_ id: LorvexTask.ID) throws -> LorvexTask.ID {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "task_id", message: "A task ID is required.")
    }
    return trimmed
  }

  public static func validatedTaskText(_ text: String, label: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: nil, message: "Task \(label) is required.")
    }
    return trimmed
  }
}
