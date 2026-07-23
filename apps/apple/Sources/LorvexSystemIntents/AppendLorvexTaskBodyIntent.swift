import AppIntents

struct AppendLorvexTaskBodyIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.body.append.title", defaultValue: "Append Lorvex Task Body", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.body.append.description", defaultValue: "Append notes to a Lorvex task from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.text", defaultValue: "Text", table: "Localizable", bundle: SystemL10n.bundle))
  var text: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    text = ""
  }

  init(task: LorvexTaskEntity, text: String) {
    self.task = task
    self.text = text
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.appendToTaskBody(id: task.id, text: text)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.body.append.dialog", defaultValue: "Updated notes for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
