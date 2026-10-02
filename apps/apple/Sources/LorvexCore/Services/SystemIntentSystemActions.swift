extension LorvexSystemIntentRunner {
  public static func completeSetup(
    workingHours: String?,
    defaultListID: String?,
    timezone: String?,
    core: any LorvexCoreServicing
  ) async throws -> PreferencesSnapshot {
    try await core.completeSetup(
      workingHours: workingHours.trimmedNilIfEmpty,
      defaultListID: defaultListID.trimmedNilIfEmpty,
      timezone: timezone.trimmedNilIfEmpty
    )
  }

  public static func readOverview(core: any LorvexCoreServicing) async throws
    -> OverviewCompactSnapshot
  {
    try await core.getOverviewCompact()
  }
}
