import AppIntents

struct CompleteLorvexTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.complete.title", defaultValue: "Complete Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.complete.description", defaultValue: "Complete a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let taskTitle = try await LorvexTaskIntentRunner.completeTask(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.complete.dialog", defaultValue: "Completed \(taskTitle).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
