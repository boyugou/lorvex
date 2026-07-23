import AppIntents
import LorvexCore

struct ReopenLorvexTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reopen.title", defaultValue: "Reopen Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reopen.description", defaultValue: "Reopen a completed, cancelled, or deferred Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexReopenableTaskEntity

  init() {
    task = LorvexReopenableTaskEntity(id: "", title: "", status: "")
  }

  init(taskID: String) {
    task = LorvexReopenableTaskEntity(id: taskID, title: taskID, status: "")
  }

  init(task: LorvexReopenableTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let title = try await LorvexTaskIntentRunner.reopenTask(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reopen.dialog", defaultValue: "Reopened task \(title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
