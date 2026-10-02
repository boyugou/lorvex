import AppIntents

struct ReadLorvexReviewHistoryIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.history.read.title", defaultValue: "Read Lorvex Review History", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.history.read.description", defaultValue: "Read recent Lorvex daily reviews.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var from: Date?

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var to: Date?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {}

  init(from: Date? = nil, to: Date? = nil, limit: Int? = nil) {
    self.from = from
    self.to = to
    self.limit = limit
  }

  /// Returns each review's summary, newest first.
  func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
    let range = IntentDateText.dayRange(from: from, to: to)
    let reviews = try await LorvexTaskIntentRunner.readReviewHistory(
      from: range.from,
      to: range.to,
      limit: limit
    )
    return .result(
      value: reviews.map(\.summary),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.history.read.dialog_count", defaultValue: "\(reviews.count) reviews.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
