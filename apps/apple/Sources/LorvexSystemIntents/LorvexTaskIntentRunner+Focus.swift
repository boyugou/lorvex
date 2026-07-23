import LorvexCore

extension LorvexTaskIntentRunner {
  public static func addTaskToFocus(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> Int {
    try await LorvexSystemIntentRunner.addTaskToFocus(id: id, core: core)
  }

  public static func readCurrentFocus(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CurrentFocusPlan? {
    try await LorvexSystemIntentRunner.readCurrentFocus(date: date, core: core)
  }

  public static func clearCurrentFocus(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.clearCurrentFocus(date: date, core: core)
  }

  public static func removeTaskFromFocus(
    id: LorvexTask.ID,
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CurrentFocusPlan? {
    try await LorvexSystemIntentRunner.removeTaskFromFocus(
      id: id,
      date: date,
      core: core
    )
  }

  public static func readFocusSchedule(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> FocusSchedule? {
    try await LorvexSystemIntentRunner.readFocusSchedule(date: date, core: core)
  }

  public static func proposeFocusSchedule(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> FocusSchedule {
    try await LorvexSystemIntentRunner.proposeFocusSchedule(date: date, core: core)
  }

  public static func saveProposedFocusSchedule(
    date: String? = nil,
    rationale: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> FocusSchedule {
    try await LorvexSystemIntentRunner.saveProposedFocusSchedule(
      date: date,
      rationale: rationale,
      core: core
    )
  }
}
