import LorvexCore

extension LorvexTaskIntentRunner {
  public static func planTaskForToday(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.planTaskForToday(id: id, core: core)
  }

  public static func readDayTimes(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> (date: String, tasks: [LorvexTask]) {
    try await LorvexSystemIntentRunner.readDayTimes(date: date, core: core)
  }

  public static func proposeDayTimes(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> DayTimesProposal {
    try await LorvexSystemIntentRunner.proposeDayTimes(date: date, core: core)
  }

  public static func saveProposedDayTimes(
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> DayTimesProposal {
    try await LorvexSystemIntentRunner.saveProposedDayTimes(date: date, core: core)
  }
}
