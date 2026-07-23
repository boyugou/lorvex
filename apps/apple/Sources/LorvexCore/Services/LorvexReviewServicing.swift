import Foundation

public protocol LorvexReviewServicing: Sendable {
  func loadDailyReview(date: String?) async throws -> DailyReviewEntry?

  /// Canonical full replacement used by MCP and other link-aware writers.
  /// Both link sets are mandatory; pass `[]` to clear one explicitly.
  func upsertDailyReview(
    date: String?,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    linkedTaskIDs: [String],
    linkedListIDs: [String]
  ) async throws -> DailyReviewEntry

  /// Replaces every human-editable scalar field while preserving the link
  /// sets that exist when the write transaction runs. Use this for surfaces
  /// that cannot edit links (Apple UI and App Intents), so a stale draft cannot
  /// overwrite a concurrent MCP or CloudKit link update.
  func upsertDailyReviewPreservingLinks(
    date: String?,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?
  ) async throws -> DailyReviewEntry

  func loadWeeklyReview() async throws -> WeeklyReviewSnapshot

  /// Applies only the provided fields from `patch` to the existing review for `date`.
  /// Fields absent from `patch` (nil) are left unchanged.
  /// Throws if no review exists for `date`.
  func amendDailyReview(date: String, patch: DailyReviewPatch) async throws -> DailyReviewEntry

  /// Date-preserving idempotent upsert for data import/restore. Unlike
  /// `upsertDailyReview`, the date is exempt from the staleness/future write
  /// window — restoring a backup must accept historical reviews, exactly as
  /// remote sync payloads do. The date must still be a valid canonical
  /// `YYYY-MM-DD` string. Re-importing the same payload overwrites in place.
  func importDailyReview(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String?,
    updatedAt: String?,
    linkedTaskIDs: [String]?,
    linkedListIDs: [String]?
  ) async throws -> DailyReviewEntry

  /// Returns daily reviews in the optional window [from, to], newest first, up to `limit`.
  func getReviewHistory(from: String?, to: String?, limit: Int?) async throws -> [DailyReviewEntry]

  /// Returns the full WeeklyReviewSnapshot for the week containing `weekOf` (YYYY-MM-DD).
  /// Defaults to the current week when `weekOf` is nil.
  func getWeeklyReviewSnapshot(weekOf: String?) async throws -> WeeklyReviewSnapshot

  /// Weekly brief with caller-tunable section sizes. `nil` limits take the
  /// section defaults from ``WeeklyReviewBriefLimitPolicy``; explicit values
  /// are clamped to its cap. Every section's meta reports the limit that was
  /// actually applied.
  func getWeeklyReviewBrief(
    completedLimit: Int?,
    stalledListsLimit: Int?,
    deferredLimit: Int?,
    somedayLimit: Int?
  ) async throws -> WeeklyReviewBriefModel

  /// Objective evidence for the single local calendar day `date` (`YYYY-MM-DD`,
  /// interpreted in the user's configured timezone), backing the Review-surface
  /// day panel. `completedLimit` caps ``DayReviewSummary/topCompleted`` and is
  /// clamped to `1...50`. See ``DayReviewSummary`` for the per-field contract.
  func loadDaySummary(date: String, completedLimit: Int) async throws -> DayReviewSummary
}

extension LorvexReviewServicing {
  /// Convenience overload for callers that take the default top-completed cap
  /// of 5, matching the weekly-snapshot `top_completed` default.
  public func loadDaySummary(date: String) async throws -> DayReviewSummary {
    try await loadDaySummary(date: date, completedLimit: 5)
  }
}
