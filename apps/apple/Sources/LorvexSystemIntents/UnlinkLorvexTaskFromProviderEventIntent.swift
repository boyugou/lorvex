import AppIntents

struct UnlinkLorvexTaskFromProviderEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.provider_event.unlink.title", defaultValue: "Unlink Lorvex Task from Provider Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.provider_event.unlink.description", defaultValue: "Remove the link between a Lorvex task and an external calendar event.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.provider_event_id", defaultValue: "Provider Event ID", table: "Localizable", bundle: SystemL10n.bundle))
  var providerEventID: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    providerEventID = ""
  }

  init(task: LorvexTaskEntity, providerEventID: String) {
    self.task = task
    self.providerEventID = providerEventID
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await LorvexTaskIntentRunner.unlinkTaskFromProviderEvent(
      taskID: task.id,
      providerEventID: providerEventID
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.provider_event.unlink.dialog",
          defaultValue: "Unlinked \(task.title) from the calendar event.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
