import Foundation

extension LorvexSystemIntentRunner {
  public static func saveDailyReview(
    summary: String,
    date: String?,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    core: any LorvexCoreServicing
  ) async throws -> DailyReviewEntry {
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSummary.isEmpty else {
      throw LorvexCoreError.validation(
        field: "summary", message: "A daily review summary is required.")
    }
    let reviewDate = try await logicalDay(date, core: core)
    return try await core.upsertDailyReviewPreservingLinks(
      date: reviewDate,
      summary: trimmedSummary,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins.trimmedNilIfEmpty,
      blockers: blockers.trimmedNilIfEmpty,
      learnings: learnings.trimmedNilIfEmpty
    )
  }

  public static func amendDailyReview(
    date: String,
    summary: String?,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    core: any LorvexCoreServicing
  ) async throws -> DailyReviewEntry {
    try await core.amendDailyReview(
      date: validatedReviewDate(date),
      patch: DailyReviewPatch(
        summary: summary.trimmedNilIfEmpty,
        mood: mood,
        energyLevel: energyLevel,
        wins: wins.trimmedNilIfEmpty,
        blockers: blockers.trimmedNilIfEmpty,
        learnings: learnings.trimmedNilIfEmpty
      )
    )
  }

  public static func readReviewHistory(
    from: String?,
    to: String?,
    limit: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [DailyReviewEntry] {
    try await core.getReviewHistory(
      from: from.trimmedNilIfEmpty,
      to: to.trimmedNilIfEmpty,
      limit: validatedReviewHistoryLimit(limit)
    )
  }

  public static func readWeeklyReview(
    weekOf: String?,
    core: any LorvexCoreServicing
  ) async throws -> WeeklyReviewSnapshot {
    try await core.getWeeklyReviewSnapshot(weekOf: weekOf.trimmedNilIfEmpty)
  }

  private static func validatedReviewDate(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "date", message: "A review date is required.")
    }
    return trimmed
  }

  private static func validatedReviewHistoryLimit(_ value: Int?) throws -> Int? {
    guard let value else { return nil }
    guard value > 0 else {
      throw LorvexCoreError.validation(
        field: "limit", message: "Review history limit must be greater than zero.")
    }
    return min(value, 500)
  }
}
