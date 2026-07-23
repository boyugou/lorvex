import AppIntents
import LorvexCore

struct CancelLorvexTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.cancel.title", defaultValue: "Cancel Lorvex Task Occurrence", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.cancel.description", defaultValue: "Cancel this Lorvex task occurrence from Shortcuts or Siri. Repeating tasks continue.", table: "Localizable", bundle: SystemL10n.bundle))

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
          "system.confirm.cancel_task", defaultValue: "Cancel this occurrence?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let title = try await LorvexTaskIntentRunner.cancelTask(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.cancel.dialog",
          defaultValue: "Cancelled \(title) for this occurrence only.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
