import AppIntents
import Foundation

struct CompleteLorvexSetupIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.setup.complete.title", defaultValue: "Complete Lorvex Setup", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.setup.complete.description", defaultValue: "Mark Lorvex setup complete with optional defaults.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.setup.parameter.day_start", defaultValue: "Day Hours Start", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var dayStart: Date?

  @Parameter(
    title: LocalizedStringResource("system.setup.parameter.day_end", defaultValue: "Day Hours End", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var dayEnd: Date?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var defaultList: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.setup.parameter.timezone", defaultValue: "Timezone", table: "Localizable", bundle: SystemL10n.bundle),
    optionsProvider: LorvexTimeZoneOptionsProvider())
  var timezone: String?

  init() {}

  init(
    dayStart: Date? = nil,
    dayEnd: Date? = nil,
    defaultList: LorvexListEntity? = nil,
    timezone: String? = nil
  ) {
    self.dayStart = dayStart
    self.dayEnd = dayEnd
    self.defaultList = defaultList
    self.timezone = timezone
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    // Day hours are one window, so one end without the other asks for it.
    let workingHours: String?
    switch (dayStart, dayEnd) {
    case let (start?, end?):
      workingHours = "\(IntentDateText.time(start))-\(IntentDateText.time(end))"
    case (nil, nil):
      workingHours = nil
    case (nil, _?):
      throw $dayStart.needsValueError()
    case (_?, nil):
      throw $dayEnd.needsValueError()
    }
    _ = try await LorvexTaskIntentRunner.completeSetup(
      workingHours: workingHours,
      defaultListID: defaultList?.id,
      timezone: timezone
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.setup.finished.dialog", defaultValue: "Lorvex is set up.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}

/// The time zones Lorvex can plan in — every region zone by its IANA name,
/// and UTC — with the device's zone offered first.
struct LorvexTimeZoneOptionsProvider: DynamicOptionsProvider {
  func results() async throws -> [String] {
    (TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") } + ["UTC"]).sorted()
  }

  func defaultResult() async -> String? {
    TimeZone.current.identifier
  }
}
