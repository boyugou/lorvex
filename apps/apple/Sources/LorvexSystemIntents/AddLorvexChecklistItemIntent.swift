import AppIntents

struct AddLorvexChecklistItemIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.checklist.add.title", defaultValue: "Add Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.checklist.add.description", defaultValue: "Add a checklist item to a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let updated = try await LorvexTaskIntentRunner.addTaskChecklistItem(
      taskID: task.id,
      text: text
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.checklist.add.dialog",
          defaultValue: "Added checklist item to \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
