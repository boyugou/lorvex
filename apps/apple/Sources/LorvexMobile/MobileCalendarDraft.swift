import Foundation
import LorvexCore

/// The calendar event forms' working copy of an event: its text fields and its
/// ``CalendarEventTiming``, which holds when the event starts and ends.
public struct MobileCalendarDraft: Equatable, Sendable {
  public var title: String
  public var timing: CalendarEventTiming
  public var location: String
  public var notes: String

  public init(
    title: String = "",
    timing: CalendarEventTiming = CalendarEventTiming(start: Date(), end: Date(), allDay: true),
    location: String = "",
    notes: String = ""
  ) {
    self.title = title
    self.timing = timing
    self.location = location
    self.notes = notes
  }

  /// An empty all-day draft on the day of `now()`: the state the forms return
  /// to after a save.
  public init(now: @Sendable () -> Date) {
    let date = now()
    self.init(timing: CalendarEventTiming(start: date, end: date, allDay: true))
  }

  /// A timed one-hour draft that starts at `start`. Its end may fall on the
  /// next day, so a late start such as 23:30 runs to 00:30.
  public static func timedDefault(start: Date) -> MobileCalendarDraft {
    MobileCalendarDraft(timing: .timed(startingAt: start))
  }

  public init(event: CalendarTimelineEvent, fallbackDate: Date) {
    self.init(
      title: event.title,
      timing: CalendarEventTiming(event: event, fallbackDay: fallbackDate),
      location: event.location ?? "",
      notes: event.notes ?? ""
    )
  }

  public var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedLocation: String {
    location.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedNotes: String {
    notes.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// True when the draft can be saved: it has a title and ends after it starts.
  public var canSubmit: Bool {
    !trimmedTitle.isEmpty && timing.isValid
  }
}
