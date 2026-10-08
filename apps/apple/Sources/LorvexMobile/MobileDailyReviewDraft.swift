import Foundation
import LorvexCore

public struct MobileDailyReviewDraft: Equatable, Sendable {
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

  private func isValidRating(_ value: Int?) -> Bool {
    value.map { (1...5).contains($0) } ?? true
  }
}
