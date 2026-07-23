import AppIntents
import LorvexCore

struct CaptureLorvexTaskIntent: LorvexUnauthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.capture.title", defaultValue: "Capture Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.capture.description", defaultValue: "Create a Lorvex task from a system surface.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.title", defaultValue: "Title", table: "Localizable", bundle: SystemL10n.bundle))
  var title: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.notes", defaultValue: "Notes", table: "Localizable", bundle: SystemL10n.bundle))
  var notes: String?

  init() {
    title = ""
    notes = nil
  }

  init(title: String, notes: String? = nil) {
    self.title = title
    self.notes = notes
  }

  func perform() async throws -> some IntentResult & ReturnsValue<LorvexTaskEntity> & ProvidesDialog {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.emptyTitle
    }
    let task = try await LorvexTaskIntentRunner.captureTaskReturningTask(title: trimmed, notes: notes)
    return .result(
      value: LorvexTaskEntity(task: task),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.capture.dialog", defaultValue: "Captured \(task.title) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
