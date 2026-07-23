import AppIntents

struct AmendLorvexDailyReviewIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.daily.amend.title", defaultValue: "Amend Lorvex Daily Review", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.daily.amend.description", defaultValue: "Update fields on an existing Lorvex daily review.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.summary", defaultValue: "Summary", table: "Localizable", bundle: SystemL10n.bundle))
  var summary: String?

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
    date = ""
  }

  init(
    date: String,
    summary: String? = nil,
    mood: Int? = nil,
    energy: Int? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil
  ) {
    self.date = date
    self.summary = summary
    self.mood = mood
    self.energy = energy
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let review = try await LorvexTaskIntentRunner.amendDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energy,
      wins: wins,
      blockers: blockers,
      learnings: learnings
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.daily.amend.dialog",
          defaultValue: "Updated daily review for \(review.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
