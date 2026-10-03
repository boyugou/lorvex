import Foundation
import LorvexCore

/// A VoiceOver label for an event's one-line pill on a calendar grid: a pill
/// in the week's all-day strip or a chip in a month cell. An all-day event
/// reads as one ("All day event Offsite"); a timed event reads with its span
/// (``calendarEventAccessibilityLabel(_:)``), so a pill too narrow to show
/// its time still says it.
func calendarPillAccessibilityLabel(_ event: CalendarTimelineEvent) -> String {
  guard event.allDay else { return calendarEventAccessibilityLabel(event) }
  return String(
    format: String(
      localized: "calendar.all_day_event.a11y",
      defaultValue: "All day event %@",
      table: "Localizable",
      bundle: LorvexL10n.bundle),
    event.title)
}

/// A VoiceOver label for a task at a time on a calendar grid, a block in the
/// week or a chip in a month cell: its title and its span on the day's clock
/// ("Task Draft the agenda, 9:45 AM to 10:45 AM"). The minutes count from
/// midnight.
func calendarTimedTaskAccessibilityLabel(title: String, startMinutes: Int, endMinutes: Int) -> String {
  String(
    format: String(
      localized: "calendar.task_block.a11y",
      defaultValue: "Task %@, %@ to %@",
      table: "Localizable",
      bundle: LorvexL10n.bundle),
    title,
    lorvexClockTimeLabel(minutes: startMinutes),
    lorvexClockTimeLabel(minutes: endMinutes))
}
