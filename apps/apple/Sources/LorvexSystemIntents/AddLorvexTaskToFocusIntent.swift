import AppIntents

struct AddLorvexTaskToFocusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.focus.add.title", defaultValue: "Add Lorvex Task to Focus", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.focus.add.description", defaultValue: "Add a Lorvex task to today's focus list.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(taskID: String) {
    task = LorvexTaskEntity(id: taskID, title: taskID, status: "")
  }

  init(task: LorvexTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let count = try await LorvexTaskIntentRunner.addTaskToFocus(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.focus.add.dialog",
          defaultValue: "Added task to focus. \(count) tasks are focused today.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
