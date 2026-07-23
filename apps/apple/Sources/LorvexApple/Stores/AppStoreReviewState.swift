import LorvexCore

extension AppStore {
  var dailyReview: DailyReviewEntry? {
    get { dailyReviewStorage.dailyReview }
    set { dailyReviewStorage.dailyReview = newValue }
  }

  var dailyReviewSummaryDraft: String {
    get { dailyReviewStorage.dailyReviewSummaryDraft }
    set { dailyReviewStorage.dailyReviewSummaryDraft = newValue }
  }

  var dailyReviewWinsDraft: String {
    get { dailyReviewStorage.dailyReviewWinsDraft }
    set { dailyReviewStorage.dailyReviewWinsDraft = newValue }
  }

  var dailyReviewBlockersDraft: String {
    get { dailyReviewStorage.dailyReviewBlockersDraft }
    set { dailyReviewStorage.dailyReviewBlockersDraft = newValue }
  }

  var dailyReviewLearningsDraft: String {
    get { dailyReviewStorage.dailyReviewLearningsDraft }
    set { dailyReviewStorage.dailyReviewLearningsDraft = newValue }
  }

  var dailyReviewMood: Int? {
    get { dailyReviewStorage.dailyReviewMood }
    set { dailyReviewStorage.dailyReviewMood = newValue }
  }

  var dailyReviewEnergy: Int? {
    get { dailyReviewStorage.dailyReviewEnergy }
    set { dailyReviewStorage.dailyReviewEnergy = newValue }
  }

  var weeklyReview: WeeklyReviewSnapshot? {
    get { dailyReviewStorage.weeklyReview }
    set { dailyReviewStorage.weeklyReview = newValue }
  }

  var dailyReviewEditingDate: String? {
    get { dailyReviewStorage.dailyReviewEditingDate }
    set { dailyReviewStorage.dailyReviewEditingDate = newValue }
  }

  var weeklyReviewAnchor: String? {
    get { dailyReviewStorage.weeklyReviewAnchor }
    set { dailyReviewStorage.weeklyReviewAnchor = newValue }
  }

  var dayReviewEvidence: DayReviewSummary? {
    get { dailyReviewStorage.dayReviewEvidence }
    set { dailyReviewStorage.dayReviewEvidence = newValue }
  }

  var weekReviewDigest: [DailyReviewEntry] {
    get { dailyReviewStorage.weekReviewDigest }
    set { dailyReviewStorage.weekReviewDigest = newValue }
  }

  /// The day the Reviews surface's Day scope is showing. Defaults to today when
  /// the strip has not selected a specific day yet.
  var selectedReviewDate: String {
    get { dailyReviewStorage.selectedReviewDate ?? logicalTodayDateString }
    set { dailyReviewStorage.selectedReviewDate = newValue }
  }

  /// True when the selected Day-scope day is still inside the interactive write
  /// window — the daily form is editable rather than a read-only past entry.
  var selectedReviewDayIsEditable: Bool {
    dailyReviewIsEditable(date: selectedReviewDate)
  }
}
