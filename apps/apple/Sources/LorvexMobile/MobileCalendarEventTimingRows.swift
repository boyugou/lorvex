import LorvexCore
import SwiftUI

/// The All Day, Start, and End rows of the calendar event forms. Start and End
/// each pick a day and, for a timed event, a clock time, so an event can run
/// overnight or across several days. Moving the start keeps the event's
/// length, and an end time earlier than the start runs the event into the next
/// day (``CalendarEventTiming``). An end that is not after the start shows a
/// warning under the rows, and the form keeps its save action off until it is
/// fixed.
struct MobileCalendarEventTimingRows: View {
  @Binding var timing: CalendarEventTiming
  /// The form's accessibility identifier prefix, such as
  /// `mobileEditCalendarEvent`.
  let idPrefix: String

  var body: some View {
    Toggle(
      String(
        localized: "calendar.field.all_day", defaultValue: "All Day", table: "Localizable",
        bundle: MobileL10n.bundle), isOn: $timing.allDay
    )
    .accessibilityIdentifier("\(idPrefix).allDay")
    DatePicker(
      String(
        localized: "calendar.field.start", defaultValue: "Start", table: "Localizable",
        bundle: MobileL10n.bundle),
      selection: Binding(
        get: { timing.start },
        set: { timing.allDay ? timing.setStartDay($0) : timing.moveStart(to: $0) }),
      displayedComponents: components
    )
    .accessibilityIdentifier("\(idPrefix).start")
    // End takes any day, as Apple Calendar's does: an end before the start is
    // reported by the warning row. A lower bound would also make the date-only
    // compact picker show its day in the short numeric style ("10/4/26") beside
    // Start's "Oct 2, 2026".
    DatePicker(
      String(
        localized: "calendar.field.end", defaultValue: "End", table: "Localizable",
        bundle: MobileL10n.bundle),
      selection: Binding(
        get: { timing.end },
        set: { timing.allDay ? timing.setEndDay($0) : timing.setEnd($0) }),
      displayedComponents: components
    )
    .accessibilityIdentifier("\(idPrefix).end")
    if !timing.isValid {
      Label(
        String(
          localized: "calendar.event.end_after_start.help",
          defaultValue: "The end time must be after the start time", table: "Localizable",
          bundle: MobileL10n.bundle),
        systemImage: "exclamationmark.triangle"
      )
      .font(.footnote)
      .foregroundStyle(LorvexDesign.Palette.warning)
      .accessibilityIdentifier("\(idPrefix).timesInvalid")
    }
  }

  /// A timed event picks a day and a clock time; an all-day event a day only.
  private var components: DatePickerComponents {
    timing.allDay ? [.date] : [.date, .hourAndMinute]
  }
}
