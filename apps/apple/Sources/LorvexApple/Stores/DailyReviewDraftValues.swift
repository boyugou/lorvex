import LorvexCore

/// The daily-review editor's fields at one moment: the text of each section and
/// the two ratings, as the editor holds them before they are saved.
struct DailyReviewDraftValues: Equatable {
  var summary = ""
  var wins = ""
  var blockers = ""
  var learnings = ""
  var mood: Int?
  var energy: Int?

  /// True when saving these values would leave `review` (`nil` for a day with
  /// no entry) as it is. A save stores every section trimmed, so a section that
  /// differs from the stored copy only by whitespace around its text is the
  /// same entry, and a blank section is the same as none.
  func isStored(as review: DailyReviewEntry?) -> Bool {
    DailyReviewEntry.isStored(
      summary: summary, wins: wins, blockers: blockers, learnings: learnings,
      mood: mood, energy: energy, as: review)
  }
}
