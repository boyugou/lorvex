import AppIntents

struct ReadLorvexWeeklyReviewIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.weekly.read.title", defaultValue: "Read Lorvex Weekly Review", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.weekly.read.description", defaultValue: "Read the Lorvex weekly review snapshot.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.week_of", defaultValue: "Week Of", table: "Localizable", bundle: SystemL10n.bundle))
  var weekOf: String?

  init() {}

  init(weekOf: String? = nil) {
    self.weekOf = weekOf
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let review = try await LorvexTaskIntentRunner.readWeeklyReview(weekOf: weekOf)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.weekly.read.dialog",
          defaultValue: "\(review.completedThisWeek) completed this week.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
