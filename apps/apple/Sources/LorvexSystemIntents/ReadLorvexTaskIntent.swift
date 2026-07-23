import AppIntents

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
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.read.dialog", defaultValue: "\(loaded.title) is \(loaded.status.rawValue).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
