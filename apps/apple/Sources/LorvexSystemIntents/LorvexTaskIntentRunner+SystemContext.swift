import LorvexCore

extension LorvexTaskIntentRunner {
  public static func completeSetup(
    workingHours: String? = nil,
    defaultListID: String? = nil,
    timezone: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> PreferencesSnapshot {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.completeSetup(
        workingHours: workingHours,
        defaultListID: defaultListID,
        timezone: timezone,
        core: core
      )
    }
  }

  public static func readOverview(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> OverviewCompactSnapshot {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.readOverview(core: core)
    }
  }
}
