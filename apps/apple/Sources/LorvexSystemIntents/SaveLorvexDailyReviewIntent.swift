import AppIntents
import LorvexCore

struct SaveLorvexDailyReviewIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.daily.save.title", defaultValue: "Save Lorvex Daily Review", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.daily.save.description", defaultValue: "Save a daily review in Lorvex from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.summary", defaultValue: "Summary", table: "Localizable", bundle: SystemL10n.bundle))
  var summary: String

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.mood", defaultValue: "Mood", table: "Localizable", bundle: SystemL10n.bundle))
  var mood: Int?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.energy", defaultValue: "Energy", table: "Localizable", bundle: SystemL10n.bundle))
  var energy: Int?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.wins", defaultValue: "Wins", table: "Localizable", bundle: SystemL10n.bundle))
  var wins: String?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.blockers", defaultValue: "Blockers", table: "Localizable", bundle: SystemL10n.bundle))
  var blockers: String?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.learnings", defaultValue: "Learnings", table: "Localizable", bundle: SystemL10n.bundle))
  var learnings: String?

  init() {
    summary = ""
    date = nil
    mood = nil
    energy = nil
    wins = nil
    blockers = nil
    learnings = nil
  }

  init(
    summary: String,
    date: String? = nil,
    mood: Int? = nil,
    energy: Int? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil
  ) {
    self.summary = summary
    self.date = date
    self.mood = mood
    self.energy = energy
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let review = try await LorvexTaskIntentRunner.saveDailyReview(
      summary: summary,
      date: date,
      mood: mood,
      energyLevel: energy,
      wins: wins,
      blockers: blockers,
      learnings: learnings
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.daily.save.dialog", defaultValue: "Saved daily review for \(review.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
