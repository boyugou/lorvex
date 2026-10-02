import AppIntents

struct RemoveLorvexChecklistItemIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.checklist.remove.title", defaultValue: "Remove Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.checklist.remove.description", defaultValue: "Remove a checklist item from a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.checklist_item", defaultValue: "Checklist Item", table: "Localizable", bundle: SystemL10n.bundle))
  var item: LorvexChecklistItemEntity

  init() {
    item = LorvexChecklistItemEntity(taskID: "", itemID: "", text: "", taskTitle: "", completed: false)
  }

  init(item: LorvexChecklistItemEntity) {
    self.item = item
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let task = try await LorvexTaskIntentRunner.removeTaskChecklistItem(itemID: item.itemID)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.checklist.remove.dialog",
          defaultValue: "Removed checklist item from \(task.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
