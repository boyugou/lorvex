import Foundation
import LorvexCore

/// Week-to-week navigation for the Reviews workspace's weekly pane. The
/// window anchor is the final day of the viewed week; `nil` is the live
/// trailing week ending today, and forward steps clamp back to it so the
/// pane can never look into the future.
extension AppStore {
  var isViewingCurrentWeek: Bool { weeklyReviewAnchor == nil }

  func stepWeeklyReview(byWeeks delta: Int) async {
    let today = logicalTodayDateString
    let current = weeklyReviewAnchor ?? today
    guard let shifted = LorvexDateFormatters.ymdUTCAddingDays(current, days: delta * 7) else {
      return
    }
    await loadWeeklyReview(weekOf: shifted >= today ? nil : shifted)
  }

  func jumpWeeklyReviewToCurrentWeek() async {
    await loadWeeklyReview(weekOf: nil)
  }

  /// Jump the weekly pane to the week containing `date` (a `YYYY-MM-DD` day).
  /// A day on or after today resolves to the live trailing week (`nil` anchor)
  /// so the pane can never look into the future. Loads the snapshot and the
  /// matching digest via ``loadWeeklyReview(weekOf:)``.
  func selectReviewWeek(of date: String) async {
    let today = logicalTodayDateString
    await loadWeeklyReview(weekOf: date >= today ? nil : date)
  }

  func loadWeeklyReview(weekOf anchor: String?) async {
    await perform {
      weeklyReview = try await core.getWeeklyReviewSnapshot(weekOf: anchor)
      weeklyReviewAnchor = anchor
    }
    // The read-only week digest tracks the same window as the snapshot, so
    // reload it whenever the viewed week changes.
    await loadWeekReviewDigest(weekOf: anchor)
  }
}
