import LorvexCore

extension LorvexTaskIntentRunner {
  public static func saveDailyReview(
    summary: String,
    date: String? = nil,
    mood: Int? = nil,
    energyLevel: Int? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> DailyReviewEntry {
    try await LorvexSystemIntentRunner.saveDailyReview(
      summary: summary,
      date: date,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins,
      blockers: blockers,
      learnings: learnings,
      core: core
    )
  }

  public static func amendDailyReview(
    date: String,
    summary: String? = nil,
    mood: Int? = nil,
    energyLevel: Int? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> DailyReviewEntry {
    try await LorvexSystemIntentRunner.amendDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins,
      blockers: blockers,
      learnings: learnings,
      core: core
    )
  }

  public static func readReviewHistory(
    from: String? = nil,
    to: String? = nil,
    limit: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [DailyReviewEntry] {
    try await LorvexSystemIntentRunner.readReviewHistory(
      from: from,
      to: to,
      limit: limit,
      core: core
    )
  }

  public static func readWeeklyReview(
    weekOf: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> WeeklyReviewSnapshot {
    try await LorvexSystemIntentRunner.readWeeklyReview(weekOf: weekOf, core: core)
  }
}
