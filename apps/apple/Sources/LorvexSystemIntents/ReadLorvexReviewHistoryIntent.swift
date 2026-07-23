import AppIntents

struct ReadLorvexReviewHistoryIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.history.read.title", defaultValue: "Read Lorvex Review History", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.history.read.description", defaultValue: "Read recent Lorvex daily reviews.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle))
  var from: String?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle))
  var to: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {}

  init(from: String? = nil, to: String? = nil, limit: Int? = nil) {
    self.from = from
    self.to = to
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reviews = try await LorvexTaskIntentRunner.readReviewHistory(
      from: from,
      to: to,
      limit: limit
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.history.read.dialog_count", defaultValue: "\(reviews.count) reviews.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
