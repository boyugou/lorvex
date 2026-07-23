import AppIntents
import LorvexCore

struct RemoveLorvexTaskFromFocusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.focus.remove.title", defaultValue: "Remove Lorvex Task from Focus", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.focus.remove.description", defaultValue: "Remove a Lorvex task from today's focus plan or a specific focus date.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    date = nil
  }

  init(taskID: String, date: String? = nil) {
    task = LorvexTaskEntity(id: taskID, title: taskID, status: "")
    self.date = date
  }

  init(task: LorvexTaskEntity, date: String? = nil) {
    self.task = task
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let focus = try await LorvexTaskIntentRunner.removeTaskFromFocus(
      id: task.id,
      date: date
    )
    let count = focus?.taskIDs.count ?? 0
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.focus.remove.dialog",
          defaultValue: "Removed task from focus. \(count) tasks remain focused.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
