import AppIntents

struct ToggleLorvexChecklistItemIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.checklist.toggle.title", defaultValue: "Toggle Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.checklist.toggle.description", defaultValue: "Set a Lorvex checklist item complete or incomplete.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.checklist_item", defaultValue: "Checklist Item", table: "Localizable", bundle: SystemL10n.bundle))
  var item: LorvexChecklistItemEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.completed", defaultValue: "Completed", table: "Localizable", bundle: SystemL10n.bundle))
  var completed: Bool

  init() {
    item = LorvexChecklistItemEntity(taskID: "", itemID: "", text: "", taskTitle: "", completed: false)
    completed = true
  }

  init(item: LorvexChecklistItemEntity, completed: Bool) {
    self.item = item
    self.completed = completed
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    _ = try await LorvexTaskIntentRunner.toggleTaskChecklistItem(
      itemID: item.itemID,
      completed: completed
    )
    let dialog =
      completed
      ? LocalizedStringResource(
        "system.task.checklist.toggle.done_dialog",
        defaultValue: "Checked off \(item.text).",
        table: "Localizable", bundle: SystemL10n.bundle)
      : LocalizedStringResource(
        "system.task.checklist.toggle.undone_dialog",
        defaultValue: "Unchecked \(item.text).",
        table: "Localizable", bundle: SystemL10n.bundle)
    return .result(dialog: IntentDialog(dialog))
  }
}
