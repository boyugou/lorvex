import Foundation
import LorvexCore

public struct MobileCalendarDraft: Equatable, Sendable {
  public var title: String
  public var date: Date
  public var startTime: Date
  public var endTime: Date
  public var allDay: Bool
  public var location: String
  public var notes: String

  public init(
    title: String = "",
    date: Date = Date(),
    startTime: Date = Date(),
    endTime: Date = Date(),
    allDay: Bool = true,
    location: String = "",
    notes: String = ""
  ) {
    self.title = title
    self.date = date
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
  }

  public init(now: @Sendable () -> Date) {
    let date = now()
    self.init(date: date, startTime: date, endTime: date)
  }

  public init(event: CalendarTimelineEvent, fallbackDate: Date) {
    let date = Self.dateFormatter.date(from: event.startDate) ?? fallbackDate
    let start = event.startTime.flatMap {
      Self.time(on: date, text: $0)
    } ?? date
    let end = event.endTime.flatMap {
      Self.time(on: date, text: $0)
    } ?? start
    self.init(
      title: event.title,
      date: date,
      startTime: start,
      endTime: end,
      allDay: event.allDay,
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

  /// True when the event spans a positive duration. All-day events have no
  /// intra-day span and are always valid; otherwise the end time-of-day must be
  /// after the start, mirroring the macOS draft so a zero- or negative-duration
  /// event can't be saved from the independent Start/End pickers.
  public var timesValid: Bool {
    guard !allDay else { return true }
    let calendar = Calendar.current
    let start = calendar.dateComponents([.hour, .minute], from: startTime)
    let end = calendar.dateComponents([.hour, .minute], from: endTime)
    let startMinutes = (start.hour ?? 0) * 60 + (start.minute ?? 0)
    let endMinutes = (end.hour ?? 0) * 60 + (end.minute ?? 0)
    return endMinutes > startMinutes
  }

  public var canSubmit: Bool {
    !trimmedTitle.isEmpty && timesValid
  }

  private nonisolated static var dateFormatter: DateFormatter { LorvexDateFormatters.ymd }

  private nonisolated static var timeFormatter: DateFormatter { LorvexDateFormatters.hourMinute }

  private static func time(on date: Date, text: String) -> Date? {
    guard let parsed = timeFormatter.date(from: text) else { return nil }
    let time = Calendar.current.dateComponents([.hour, .minute], from: parsed)
    var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    components.hour = time.hour
    components.minute = time.minute
    return Calendar.current.date(from: components)
  }
}
