import Foundation
import LorvexCore

/// Holds runtime state for the daily-review and weekly-review domains:
/// the loaded review entry, mood/energy scores, and all section drafts.
struct AppStoreDailyReviewStorage {
  var dailyReview: DailyReviewEntry?
  /// Date (`YYYY-MM-DD`) the daily editor is anchored to; `nil` means today.
  /// Only dates inside the staleness write window are ever set here.
  var dailyReviewEditingDate: String?
  /// The day (`YYYY-MM-DD`) the Reviews surface's Day scope is showing. Drives
  /// both the date strip's selected card and which day's review / evidence is
  /// loaded. Defaults to today; a past day still inside the write window keeps
  /// `dailyReviewEditingDate` in sync (editable), while an older day loads the
  /// saved review read-only with `dailyReviewEditingDate` left `nil`.
  var selectedReviewDate: String?
  /// Objective evidence for the selected Day-scope day (counts of completed,
  /// unfinished, habits, events, created). `nil` until first load.
  var dayReviewEvidence: DayReviewSummary?
  /// The daily reviews written in the week the Week scope is viewing, newest
  /// first, for the read-only week digest.
  var weekReviewDigest: [DailyReviewEntry] = []
  var dailyReviewSummaryDraft = ""
  var dailyReviewWinsDraft = ""
  var dailyReviewBlockersDraft = ""
  var dailyReviewLearningsDraft = ""
  /// Mood / energy are genuinely optional: `nil` means the human never rated it,
  /// so an untouched review records no score rather than a fabricated middle value.
  var dailyReviewMood: Int?
  var dailyReviewEnergy: Int?
  var weeklyReview: WeeklyReviewSnapshot?
  /// Final day (`YYYY-MM-DD`) of the weekly window being viewed; `nil` means
  /// the live trailing week ending today.
  var weeklyReviewAnchor: String?

  mutating func reset() {
    dailyReview = nil
    dailyReviewSummaryDraft = ""
    dailyReviewWinsDraft = ""
    dailyReviewBlockersDraft = ""
    dailyReviewLearningsDraft = ""
    dailyReviewMood = nil
    dailyReviewEnergy = nil
    weeklyReview = nil
    selectedReviewDate = nil
    dayReviewEvidence = nil
    weekReviewDigest = []
  }
}
