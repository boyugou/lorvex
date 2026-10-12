import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// What Copy as Text and Share put on the clipboard and in the share sheet for
/// a calendar event: the shared layout (``LorvexEventShareText``), worded from
/// the Mac catalog.
@Suite("Calendar event share text")
struct CalendarEventShareTextTests {
  private func event(
    title: String = "Team sync", start: String = "2026-10-02", startTime: String? = "09:00",
    end: String? = "2026-10-02", endTime: String? = "10:30", allDay: Bool = false,
    location: String? = nil, notes: String? = nil, url: String? = nil,
    attendees: [CalendarEventAttendee]? = nil, isRecurring: Bool = false,
    recurrenceSummary: String? = nil
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: "e", title: title, source: "canonical", editable: true, startDate: start,
      startTime: startTime, endDate: end, endTime: endTime, allDay: allDay, location: location,
      notes: notes, url: url, color: nil, eventType: "event", attendees: attendees,
      timezone: nil, isRecurring: isRecurring, recurrenceSummary: recurrenceSummary)
  }

  private var timeLabel: String { lorvexClockRangeLabel(start: "09:00", end: "10:30") }

  @Test("A timed event is its title and one When line with the day and the times")
  func timedEvent() {
    #expect(
      CalendarEventShare.text(for: event())
        == "Team sync\n\nWhen: Friday, October 2, \(timeLabel)")
  }

  @Test("An all-day event says so after the day, and a run of days is one range")
  func allDayEvents() {
    let one = event(startTime: nil, endTime: nil, allDay: true)
    #expect(CalendarEventShare.text(for: one) == "Team sync\n\nWhen: Friday, October 2, All day")

    let several = event(startTime: nil, end: "2026-10-04", endTime: nil, allDay: true)
    let range = several.dayRangeLabel
    #expect(range.hasPrefix("Friday, October 2") && range.hasSuffix("Sunday, October 4"))
    #expect(CalendarEventShare.text(for: several) == "Team sync\n\nWhen: \(range), All day")
  }

  @Test("A timed event that runs into the next day is written as one span")
  func timedEventAcrossMidnight() throws {
    let overnight = event(startTime: "22:00", end: "2026-10-03", endTime: "01:00")
    let span = try #require(overnight.timedSpanLabel)
    #expect(CalendarEventShare.text(for: overnight) == "Team sync\n\nWhen: \(span)")
  }

  @Test("Place, repeat rule, attendees, and link follow the time, and the notes close the text")
  func fullEvent() {
    let full = event(
      location: "Studio", notes: "Bring the roadmap.", url: "https://example.com/room",
      attendees: [
        CalendarEventAttendee(email: "sam@example.com", name: "Sam"),
        CalendarEventAttendee(email: "lee@example.com"),
      ],
      isRecurring: true, recurrenceSummary: "Every week")
    #expect(
      CalendarEventShare.text(for: full)
        == """
        Team sync

        When: Friday, October 2, \(timeLabel)
        Location: Studio
        Repeats: Every week
        Attendees: Sam, lee@example.com
        URL: https://example.com/room

        Bring the roadmap.
        """)
  }

  @Test("A blank place, note, link, or attendee list leaves no line, and a series change reads as repeating")
  func blankFieldsAreLeftOut() {
    let blank = event(location: "  ", notes: "\n", url: "", attendees: [])
    #expect(CalendarEventShare.text(for: blank) == "Team sync\n\nWhen: Friday, October 2, \(timeLabel)")

    let change = event(isRecurring: true)
    #expect(CalendarEventShare.text(for: change).contains("Repeats: Repeating event"))
  }

  @Test("A mirrored event links to Apple Calendar at its start, and an unreadable day has no link")
  func appleCalendarLink() throws {
    let timed = event()
    let url = try #require(timed.appleCalendarURL)
    let start = CalendarEventTiming(event: timed, fallbackDay: Date()).start
    #expect(url.absoluteString == "calshow:\(Int(start.timeIntervalSinceReferenceDate))")
    #expect(event(start: "not-a-day").appleCalendarURL == nil)
  }

  @Test("The When lines are the day, then the all-day words or the clock times")
  func whenLines() {
    let timed = event().whenLines(allDay: "All day")
    #expect(timed.first == "Friday, October 2")
    #expect(timed.second == timeLabel)

    let allDay = event(startTime: nil, endTime: nil, allDay: true).whenLines(allDay: "All day")
    #expect(allDay.first == "Friday, October 2")
    #expect(allDay.second == "All day")

    let overnight = event(startTime: "22:00", end: "2026-10-03", endTime: "01:00")
    #expect(overnight.whenLines(allDay: "All day").second == nil)
    #expect(overnight.whenLines(allDay: "All day").first == overnight.timedSpanLabel)
  }
}
