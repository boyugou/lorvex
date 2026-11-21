import Foundation

/// The written fields and ratings a journal editor can change, including
/// unsaved whitespace still under the insertion point.
public struct DailyReviewDraftFields: Equatable, Sendable {
  public var summary: String
  public var wins: String
  public var blockers: String
  public var learnings: String
  public var mood: Int?
  public var energy: Int?

  public init(
    summary: String = "",
    wins: String = "",
    blockers: String = "",
    learnings: String = "",
    mood: Int? = nil,
    energy: Int? = nil
  ) {
    self.summary = summary
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.mood = mood
    self.energy = energy
  }

  public init(review: DailyReviewEntry?) {
    self.init(
      summary: review?.summary ?? "",
      wins: review?.wins ?? "",
      blockers: review?.blockers ?? "",
      learnings: review?.learnings ?? "",
      mood: review?.mood,
      energy: review?.energyLevel
    )
  }

  public var trimmedSummary: String {
    summary.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedWins: String? {
    wins.trimmedNilIfEmpty
  }

  public var trimmedBlockers: String? {
    blockers.trimmedNilIfEmpty
  }

  public var trimmedLearnings: String? {
    learnings.trimmedNilIfEmpty
  }

  public var canSave: Bool {
    !trimmedSummary.isEmpty && isValidRating(mood) && isValidRating(energy)
  }

  /// True when saving this draft would leave `review` (`nil` for a day with no
  /// entry) as it is. A save stores every section trimmed, so a section that
  /// differs from the stored copy only by whitespace around its text is the
  /// same entry, and a blank section is the same as none.
  public func isStored(as review: DailyReviewEntry?) -> Bool {
    DailyReviewEntry.isStored(
      summary: summary, wins: wins, blockers: blockers, learnings: learnings,
      mood: mood, energy: energy, as: review)
  }

  /// Apply only the fields edited since the base snapshot. If the stored
  /// value is equivalent, keep the user's spacing and selection intact.
  public func rebased(from base: Self, onto latest: Self) -> Self {
    func text(_ local: String, _ original: String, _ incoming: String) -> String {
      let current = local.trimmedNilIfEmpty
      return current == original.trimmedNilIfEmpty && current != incoming.trimmedNilIfEmpty ? incoming : local
    }
    return Self(
      summary: text(summary, base.summary, latest.summary),
      wins: text(wins, base.wins, latest.wins),
      blockers: text(blockers, base.blockers, latest.blockers),
      learnings: text(learnings, base.learnings, latest.learnings),
      mood: mood == base.mood ? latest.mood : mood,
      energy: energy == base.energy ? latest.energy : energy)
  }

  private func isValidRating(_ value: Int?) -> Bool {
    value.map { (1...5).contains($0) } ?? true
  }
}
