import AppIntents

struct DeferLorvexTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.defer.title", defaultValue: "Defer Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.defer.description", defaultValue: "Defer a Lorvex task until tomorrow.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let taskTitle = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.defer.dialog", defaultValue: "Deferred \(taskTitle) until tomorrow.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
