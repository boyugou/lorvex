import AppIntents

struct AddLorvexTaskRecurrenceExceptionIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.recurrence.exception.add.title", defaultValue: "Add Lorvex Recurrence Exception", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.recurrence.exception.add.description", defaultValue: "Skip one occurrence date for a recurring Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.exception_date", defaultValue: "Exception Date", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var exceptionDate: Date

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    exceptionDate = .now
  }

  init(task: LorvexTaskEntity, exceptionDate: Date) {
    self.task = task
    self.exceptionDate = exceptionDate
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.addTaskRecurrenceException(
      taskID: task.id,
      exceptionDate: IntentDateText.day(exceptionDate)
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.recurrence.exception.add.dialog",
          defaultValue: "Skipped one recurrence date for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
