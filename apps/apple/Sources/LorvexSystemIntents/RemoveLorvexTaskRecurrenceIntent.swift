import AppIntents

struct RemoveLorvexTaskRecurrenceIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.recurrence.remove.title", defaultValue: "Remove Lorvex Task Recurrence", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.recurrence.remove.description", defaultValue: "Remove a Lorvex task recurrence rule.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(task: LorvexTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let updated = try await LorvexTaskIntentRunner.removeTaskRecurrence(taskID: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.recurrence.remove.dialog", defaultValue: "Removed recurrence for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
