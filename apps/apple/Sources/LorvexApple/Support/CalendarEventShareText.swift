import AppKit
import LorvexCore

/// The plain text a calendar event is copied or shared as: the layout of
/// ``LorvexEventShareText`` worded from this app's catalog, the same text on
/// the context menu's Copy as Text, its Share, and the inspector's menu.
enum CalendarEventShare {
  static func text(for event: CalendarTimelineEvent) -> String {
    LorvexEventShareText.text(for: event, labels: labels())
  }

  /// Puts ``text(for:)`` on the general pasteboard as plain text.
  static func copy(_ event: CalendarTimelineEvent) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text(for: event), forType: .string)
  }

  private static func labels() -> LorvexEventShareLabels {
    LorvexEventShareLabels(
      field: fieldLabel,
      line: { label, value in
        String(
          localized: "share.field", defaultValue: "\(label): \(value)", table: "Localizable",
          bundle: LorvexL10n.bundle)
      },
      dayAtTime: { day, time in
        String(
          localized: "task_detail.do_on.day_time", defaultValue: "\(day), \(time)",
          table: "Localizable", bundle: LorvexL10n.bundle)
      },
      allDay: String(
        localized: "calendar.event.all_day", defaultValue: "All day", table: "Localizable",
        bundle: LorvexL10n.bundle),
      repeating: String(
        localized: "calendar.event.repeats_generic", defaultValue: "Repeating event",
        table: "Localizable", bundle: LorvexL10n.bundle))
  }

  /// The name the event inspector gives a field.
  private static func fieldLabel(_ field: LorvexEventShareField) -> String {
    switch field {
    case .when:
      String(
        localized: "calendar.event.field.when", defaultValue: "When", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .location:
      String(
        localized: "calendar.section.location", defaultValue: "Location", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .repeats:
      String(
        localized: "calendar.event.field.repeats", defaultValue: "Repeats", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .attendees:
      String(
        localized: "calendar.event.field.attendees", defaultValue: "Attendees",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .url:
      String(
        localized: "calendar.event.field.url", defaultValue: "URL", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }
}
