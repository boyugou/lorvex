import AppIntents

struct ToggleLorvexChecklistItemIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.checklist.toggle.title", defaultValue: "Toggle Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.checklist.toggle.description", defaultValue: "Set a Lorvex checklist item complete or incomplete.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.checklist_item_id", defaultValue: "Checklist Item ID", table: "Localizable", bundle: SystemL10n.bundle))
  var itemID: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.completed", defaultValue: "Completed", table: "Localizable", bundle: SystemL10n.bundle))
  var completed: Bool

  init() {
    itemID = ""
    completed = true
  }

  init(itemID: String, completed: Bool) {
    self.itemID = itemID
    self.completed = completed
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let task = try await LorvexTaskIntentRunner.toggleTaskChecklistItem(
      itemID: itemID,
      completed: completed
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.checklist.update.dialog",
          defaultValue: "Updated checklist item in \(task.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
