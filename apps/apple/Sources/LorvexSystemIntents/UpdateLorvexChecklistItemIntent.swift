import AppIntents

struct UpdateLorvexChecklistItemIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.checklist.update.title", defaultValue: "Update Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.checklist.update.description", defaultValue: "Update the text of a Lorvex checklist item.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.checklist_item_id", defaultValue: "Checklist Item ID", table: "Localizable", bundle: SystemL10n.bundle))
  var itemID: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.text", defaultValue: "Text", table: "Localizable", bundle: SystemL10n.bundle))
  var text: String

  init() {
    itemID = ""
    text = ""
  }

  init(itemID: String, text: String) {
    self.itemID = itemID
    self.text = text
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let task = try await LorvexTaskIntentRunner.updateTaskChecklistItem(
      itemID: itemID,
      text: text
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.checklist.update.dialog",
          defaultValue: "Updated checklist item in \(task.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
