import LorvexCore

extension LorvexTaskIntentRunner {
  public static func captureTask(
    title: String,
    notes: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.captureTask(title: title, notes: notes, core: core)
  }

  /// Capture variant that returns the freshly created task so a returning
  /// App Intent can hand the real entity back to Shortcuts for chaining.
  public static func captureTaskReturningTask(
    title: String,
    notes: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.captureTaskReturningTask(title: title, notes: notes, core: core)
  }

  public static func createList(
    name: String,
    description: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexList {
    try await LorvexSystemIntentRunner.createList(
      name: name,
      description: description,
      core: core
    )
  }

  public static func createHabit(
    name: String,
    cue: String?,
    targetCount: Int?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexSystemIntentRunner.createHabit(
      name: name,
      cue: cue,
      targetCount: targetCount,
      core: core
    )
  }

  public static func createCalendarEvent(
    title: String,
    startDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CalendarTimelineEvent {
    try await LorvexSystemIntentRunner.createCalendarEvent(
      title: title,
      startDate: startDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: notes,
      core: core
    )
  }
}
