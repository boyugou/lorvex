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

  private func isValidRating(_ value: Int?) -> Bool {
    value.map { (1...5).contains($0) } ?? true
  }
}
