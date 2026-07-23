import AppIntents

struct OpenLorvexTaskIntent: LorvexUnauthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.open.title", defaultValue: "Open Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.open.description", defaultValue: "Open Lorvex to a specific task.", table: "Localizable", bundle: SystemL10n.bundle))
  static let openAppWhenRun = true

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }

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
    let taskID = try LorvexTaskIntentRunner.validatedTaskID(task.id)
    LorvexIntentHandoff.storeTask(taskID)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.open.dialog", defaultValue: "Opening task in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
