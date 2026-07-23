import AppIntents

struct LinkLorvexTaskToProviderEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.provider_event.link.title", defaultValue: "Link Lorvex Task to Provider Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.provider_event.link.description", defaultValue: "Link a Lorvex task to an external calendar event.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.provider_event_id", defaultValue: "Provider Event ID", table: "Localizable", bundle: SystemL10n.bundle))
  var providerEventID: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.provider_source", defaultValue: "Provider Source", table: "Localizable", bundle: SystemL10n.bundle))
  var providerSource: LorvexProviderSourceOption

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    providerEventID = ""
    providerSource = .eventkit
  }

  init(task: LorvexTaskEntity, providerEventID: String, providerSource: LorvexProviderSourceOption = .eventkit) {
    self.task = task
    self.providerEventID = providerEventID
    self.providerSource = providerSource
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let link = try await LorvexTaskIntentRunner.linkTaskToProviderEvent(
      taskID: task.id,
      providerEventID: providerEventID,
      providerSource: providerSource.wireValue
    )
    let dialog: LocalizedStringResource
    if let source = link.providerSource {
      dialog = LocalizedStringResource(
        "system.task.provider_event.link.dialog",
        defaultValue: "Linked \(task.title) to \(source).",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.task.provider_event.link.default_dialog",
        defaultValue: "Linked \(task.title) to the calendar event.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(dialog: IntentDialog(dialog))
  }
}
