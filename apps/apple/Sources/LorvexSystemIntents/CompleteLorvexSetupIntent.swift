import AppIntents

struct CompleteLorvexSetupIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.setup.complete.title", defaultValue: "Complete Lorvex Setup", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.setup.complete.description", defaultValue: "Mark Lorvex setup complete with optional defaults.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.setup.parameter.working_hours", defaultValue: "Working Hours", table: "Localizable", bundle: SystemL10n.bundle))
  var workingHours: String?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var defaultList: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.setup.parameter.timezone", defaultValue: "Timezone", table: "Localizable", bundle: SystemL10n.bundle))
  var timezone: String?

  init() {}

  init(workingHours: String? = nil, defaultList: LorvexListEntity? = nil, timezone: String? = nil) {
    self.workingHours = workingHours
    self.defaultList = defaultList
    self.timezone = timezone
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let preferences = try await LorvexTaskIntentRunner.completeSetup(
      workingHours: workingHours,
      defaultListID: defaultList?.id,
      timezone: timezone
    )
    let setupComplete = preferences.values["setup_completed"] ?? "true"
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.setup.complete.dialog", defaultValue: "Setup completed: \(setupComplete).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
