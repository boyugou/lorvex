import AppIntents

struct RemoveLorvexTaskRecurrenceExceptionIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.recurrence.exception.remove.title", defaultValue: "Remove Lorvex Recurrence Exception", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.recurrence.exception.remove.description", defaultValue: "Restore one skipped occurrence date for a recurring task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.exception_date", defaultValue: "Exception Date", table: "Localizable", bundle: SystemL10n.bundle))
  var exceptionDate: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    exceptionDate = ""
  }

  init(task: LorvexTaskEntity, exceptionDate: String) {
    self.task = task
    self.exceptionDate = exceptionDate
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let updated = try await LorvexTaskIntentRunner.removeTaskRecurrenceException(
      taskID: task.id,
      exceptionDate: exceptionDate
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.recurrence.exception.remove.dialog",
          defaultValue: "Restored one recurrence date for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
