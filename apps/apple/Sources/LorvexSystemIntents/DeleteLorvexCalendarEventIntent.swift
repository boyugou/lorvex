import AppIntents
import LorvexCore

struct DeleteLorvexCalendarEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.delete.title", defaultValue: "Delete Lorvex Calendar Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.delete.description", defaultValue: "Delete a Lorvex calendar event from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.event", defaultValue: "Calendar Event", table: "Localizable", bundle: SystemL10n.bundle))
  var event: LorvexCalendarEventEntity

  init() {
    event = LorvexCalendarEventEntity(
      id: "", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false)
  }

  init(event: LorvexCalendarEventEntity) {
    self.event = event
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    // This non-scoped intent deletes the whole current series segment. Never
    // substitute the transient rendered occurrence id; this-only and
    // this-and-following require a separate explicit scoped intent contract.
    _ = try await LorvexTaskIntentRunner.deleteCalendarEvent(id: event.eventID)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.delete.dialog",
          defaultValue: "Deleted calendar event \(event.title) from Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
