import AppIntents
import LorvexCore

struct ExportLorvexCalendarICSIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.ics.export.title", defaultValue: "Export Lorvex Calendar ICS", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.ics.export.description", defaultValue: "Prepare Lorvex calendar events as ICS from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from_date", defaultValue: "From Date", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var from: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to_date", defaultValue: "To Date", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var to: Date?

  init() {
    from = nil
    to = nil
  }

  init(from: Date? = nil, to: Date? = nil) {
    self.from = from
    self.to = to
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
    let range = IntentDateText.dayRange(from: from, to: to)
    let ics = try await LorvexTaskIntentRunner.exportCalendarICS(from: range.from, to: range.to)
    let file = LorvexExportIntentFileFactory.calendarFile(content: ics)
    return .result(
      value: file,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.ics.export.dialog", defaultValue: "Prepared Lorvex calendar ICS.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
