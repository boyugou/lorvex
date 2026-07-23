import AppIntents

struct OpenLorvexIntent: LorvexUnauthenticatedIntent {
  static let title = LocalizedStringResource("system.open.title", defaultValue: "Open Lorvex", table: "Localizable", bundle: SystemL10n.bundle)

  static let description = IntentDescription(LocalizedStringResource("system.open.description", defaultValue: "Open Lorvex to a planning area.", table: "Localizable", bundle: SystemL10n.bundle))

  static let openAppWhenRun = true

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }

  @Parameter(
    title: LocalizedStringResource("system.open.parameter.destination", defaultValue: "Destination", table: "Localizable", bundle: SystemL10n.bundle))
  var destination: LorvexIntentDestination

  init() {
    destination = .today
  }

  init(destination: LorvexIntentDestination) {
    self.destination = destination
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    LorvexIntentHandoff.storeDestination(destination.sidebarSelection)
    return .result(dialog: IntentDialog(destination.openDialog))
  }
}
