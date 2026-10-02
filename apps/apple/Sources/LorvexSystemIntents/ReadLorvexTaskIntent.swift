import AppIntents
import LorvexCore

struct ReadLorvexTaskIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.read.title", defaultValue: "Read Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(
    LocalizedStringResource("system.task.read.description", defaultValue: "Read a Lorvex task from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(task: LorvexTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ReturnsValue<LorvexTaskEntity> & ProvidesDialog {
    let loaded = try await LorvexTaskIntentRunner.readTask(id: task.id)
    return .result(
      value: LorvexTaskEntity(task: loaded),
      dialog: IntentDialog(Self.dialog(title: loaded.title, status: loaded.status)))
  }

  /// What Siri or Shortcuts says about a task: one whole sentence per status,
  /// so each language words the status the way it reads after the title
  /// instead of slotting a status label into a shared sentence.
  static func dialog(title: String, status: LorvexTask.Status) -> LocalizedStringResource {
    switch status {
    case .open:
      LocalizedStringResource(
        "system.task.read.dialog.open", defaultValue: "\(title) is still open.",
        table: "Localizable", bundle: SystemL10n.bundle)
    case .inProgress:
      LocalizedStringResource(
        "system.task.read.dialog.in_progress", defaultValue: "\(title) is in progress.",
        table: "Localizable", bundle: SystemL10n.bundle)
    case .someday:
      LocalizedStringResource(
        "system.task.read.dialog.someday", defaultValue: "\(title) is in Someday.",
        table: "Localizable", bundle: SystemL10n.bundle)
    case .completed:
      LocalizedStringResource(
        "system.task.read.dialog.completed", defaultValue: "\(title) is done.",
        table: "Localizable", bundle: SystemL10n.bundle)
    case .cancelled:
      LocalizedStringResource(
        "system.task.read.dialog.cancelled", defaultValue: "\(title) was cancelled.",
        table: "Localizable", bundle: SystemL10n.bundle)
    }
  }
}
