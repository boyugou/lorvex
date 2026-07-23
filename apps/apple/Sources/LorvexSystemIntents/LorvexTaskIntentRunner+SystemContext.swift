import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readPreferences(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> PreferencesSnapshot {
    try await LorvexSystemIntentRunner.readPreferences(core: core)
  }

  public static func readPreference(
    key: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String? {
    try await LorvexSystemIntentRunner.readPreference(key: key, core: core)
  }

  public static func setPreference(
    key: String,
    value: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.setPreference(key: key, value: value, core: core)
  }

  public static func deletePreference(
    key: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws {
    try await LorvexSystemIntentRunner.deletePreference(key: key, core: core)
  }

  public static func completeSetup(
    workingHours: String? = nil,
    defaultListID: String? = nil,
    timezone: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> PreferencesSnapshot {
    try await LorvexSystemIntentRunner.completeSetup(
      workingHours: workingHours,
      defaultListID: defaultListID,
      timezone: timezone,
      core: core
    )
  }

  public static func readOverview(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> OverviewCompactSnapshot {
    try await LorvexSystemIntentRunner.readOverview(core: core)
  }

  public static func readSessionContext(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> SessionContextSnapshot {
    try await LorvexSystemIntentRunner.readSessionContext(core: core)
  }
}
