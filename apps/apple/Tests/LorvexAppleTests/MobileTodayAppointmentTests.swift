import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

private let day = "2026-11-01"

private func event(_ name: String, _ start: String?, _ end: String?, allDay: Bool = false) -> CalendarTimelineEvent {
  CalendarTimelineEvent(id: name, eventID: name, title: name, source: "canonical", editable: true,
    startDate: day, startTime: start, endDate: day, endTime: end, allDay: allDay,
    location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false)
}

private func glance(_ events: [CalendarTimelineEvent], at minute: Int, instant: Date? = nil) -> MobileTodayAppointment? {
  MobileTodayAppointment.firstGlance(in: LorvexTodayTimeline.build(
    day: day, events: events, tasks: [], times: [:], nowMinutes: minute, now: instant))
}

@Test func todayAppointmentAdvancesAtMeetingBoundaries() {
  let workshop = event("Morning workshop", "10:00", "12:00")
  let rehearsal = event("Studio rehearsal", "13:00", "15:00")
  let events = [rehearsal, workshop]
  #expect(glance(events, at: 599) == .init(event: workshop, phase: .next))
  #expect(glance(events, at: 600) == .init(event: workshop, phase: .now))
  #expect(glance(events, at: 720) == .init(event: rehearsal, phase: .next))
  #expect(glance(events, at: 780) == .init(event: rehearsal, phase: .now))
  #expect(glance(events, at: 900) == nil)
}

@Test func todayAppointmentKeepsAllDaySeparateAndSkipsCancelledOccurrences() {
  let exhibition = event("Gallery open day", nil, nil, allDay: true)
  var dropped = event("Cancelled rehearsal", "08:00", "18:00")
  dropped.occurrenceState = .cancelled
  let doors = event("Doors open", "10:00", nil)
  #expect(glance([exhibition, dropped], at: 540) == .init(event: exhibition, phase: .allDay))
  #expect(glance([doors, exhibition, dropped], at: 540) == .init(event: doors, phase: .next))
  #expect(glance([doors, exhibition, dropped], at: 601) == .init(event: exhibition, phase: .allDay))
}

@Test func todayAppointmentHandlesOvernightAndOverlappingEvents() {
  var overnight = event("Overnight session", "23:00", "02:00")
  overnight.startDate = "2026-10-31"
  let handover = event("Handover", "01:00", "01:30")
  #expect(glance([overnight, handover], at: 30) == .init(event: overnight, phase: .now))
  #expect(glance([overnight, handover], at: 65) == .init(event: handover, phase: .now))
  #expect(glance([overnight, handover], at: 95) == .init(event: overnight, phase: .now))
  #expect(glance([overnight, handover], at: 120) == nil)
}

@Test func todayAppointmentFollowsBothReadingsOfAFoldedHour() throws {
  let iso = ISO8601DateFormatter()
  func instant(_ utc: String) throws -> Date { try #require(iso.date(from: "\(day)T\(utc)Z")) }
  var first = event("First session", "01:15", "01:45")
  first.projection = .init(timezone: "America/Los_Angeles", start: try instant("08:15:00"), end: try instant("08:45:00"))
  var second = event("Second session", "01:15", "01:45")
  second.projection = .init(timezone: "America/Los_Angeles", start: try instant("09:15:00"), end: try instant("09:45:00"))
  #expect(try glance([second, first], at: 90, instant: instant("08:30:00")) == .init(event: first, phase: .now))
  #expect(try glance([second, first], at: 110, instant: instant("08:50:00")) == .init(event: second, phase: .next))
  #expect(try glance([second, first], at: 90, instant: instant("09:30:00")) == .init(event: second, phase: .now))
}

@Test func todayAppointmentCountdownReadsInHoursAndMinutes() {
  let english = Locale(identifier: "en_US")
  func countdown(_ minutes: Int, _ style: LorvexDurationFormat.Style = .compact) -> String {
    MobileTodayAppointment.countdown(minutesAway: minutes, style: style, locale: english)
  }
  #expect(countdown(45) == "In 45 min")
  #expect(countdown(60) == "In 1 hr")
  #expect(countdown(160) == "In 2 hr 40 min", "not a count of minutes past the hour")
  #expect(countdown(160, .spoken) == "In 2 hours, 40 minutes")
}
