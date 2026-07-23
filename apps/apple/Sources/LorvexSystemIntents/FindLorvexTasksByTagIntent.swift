import AppIntents

struct FindLorvexTasksByTagIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.tag.find_tasks.title", defaultValue: "Find Lorvex Tasks by Tag", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.tag.find_tasks.description", defaultValue: "Find Lorvex tasks carrying a tag from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.tag.parameter.tag", defaultValue: "Tag", table: "Localizable", bundle: SystemL10n.bundle))
  var tag: String

  init() {
    tag = ""
  }

  init(tag: String) {
    self.tag = tag
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let tasks = try await LorvexTaskIntentRunner.getTasksByTag(tag: tag)
    guard !tasks.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.tag.find_tasks.empty_summary",
            defaultValue: "No matching tasks.",
            table: "Localizable",
            bundle: SystemL10n.bundle)))
    }
    let titles = tasks.prefix(5).map(\.title).joined(separator: ", ")
    let dialog: LocalizedStringResource
    if tasks.count > 5 {
      dialog = LocalizedStringResource(
        "system.tag.find_tasks.dialog.more",
        defaultValue:
          "\(tasks.count) Lorvex tasks tagged \(tag): \(titles), and \(tasks.count - 5) more",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.tag.find_tasks.dialog",
        defaultValue: "\(tasks.count) Lorvex tasks tagged \(tag): \(titles)",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(
      value: tasks.map(LorvexTaskEntity.init(task:)),
      dialog: IntentDialog(dialog))
  }
}
