extension LorvexSystemIntentRunner {
  public static func readCurrentFocus(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> CurrentFocusPlan? {
    let focusDate = try await logicalDay(date, core: core)
    return try await core.loadCurrentFocus(date: focusDate)
  }

  public static func clearCurrentFocus(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let focusDate = try await logicalDay(date, core: core)
    _ = try await core.clearCurrentFocus(date: focusDate)
    return focusDate
  }

  public static func removeTaskFromFocus(
    id: LorvexTask.ID,
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> CurrentFocusPlan? {
    let taskID = try validatedTaskID(id)
    let focusDate = try await logicalDay(date, core: core)
    return try await core.removeFromCurrentFocus(date: focusDate, taskID: taskID)
  }

  public static func readFocusSchedule(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> FocusSchedule? {
    let resolvedDate = try await logicalDay(date, core: core)
    return try await core.loadFocusScheduleForAI(date: resolvedDate)
  }

  public static func proposeFocusSchedule(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> FocusSchedule {
    let resolvedDate = try await logicalDay(date, core: core)
    return try await core.proposeFocusSchedule(date: resolvedDate)
  }

  public static func saveProposedFocusSchedule(
    date: String?,
    rationale: String?,
    core: any LorvexCoreServicing
  ) async throws -> FocusSchedule {
    let resolvedDate = try await logicalDay(date, core: core)
    let proposed = try await core.proposeFocusSchedule(date: resolvedDate)
    return try await core.saveFocusSchedule(
      date: proposed.date,
      blocks: proposed.blocks,
      rationale: rationale.trimmedNilIfEmpty ?? proposed.rationale ?? "Saved from Lorvex Shortcuts"
    )
  }
}
