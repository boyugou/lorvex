import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// How the calendar agenda beside the iPad day grid reads: which days it
/// lists (empty days leave the list, except today), the order of a day's
/// rows, and which events the clock has passed.
@Suite("Calendar agenda listing")
struct MobileCalendarAgendaListingTests {
  private static let week = [
    "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03",
  ]

  private static func event(
    _ title: String = "Meeting", on key: String, _ start: String? = "10:00", _ end: String? = "11:00",
    allDay: Bool = false, from startKey: String? = nil, until endKey: String? = nil
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: title, title: title, source: "canonical", editable: true,
      startDate: startKey ?? key, startTime: allDay ? nil : start, endDate: endKey ?? key,
      endTime: allDay ? nil : end, allDay: allDay, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  private static func task(_ title: String = "Task", on key: String? = nil, time: Range<Int>? = nil)
    -> LorvexTask
  {
    LorvexTask(
      id: title, title: title, notes: "", priority: .p2, status: .open, dueDate: nil,
      plannedDate: key.flatMap { LorvexDateFormatters.ymdUTC.date(from: $0) }, plannedTime: time,
      estimatedMinutes: 30, tags: [])
  }

  /// A day per key; `busy` keys get an event, `withTask` keys a task.
  private static func days(busy: Set<String>, withTask: Set<String> = []) -> [MobileCalendarAgendaDay] {
    week.enumerated().map { offset, key in
      MobileCalendarAgendaDay(
        date: Date(timeIntervalSince1970: Double(offset) * 86_400),
        key: key,
        events: busy.contains(key) ? [event(on: key)] : [],
        tasks: withTask.contains(key) ? [task()] : [])
    }
  }

  @Test("A free today keeps its section; other free days do not")
  func freeTodayStaysListed() {
    let days = Self.days(busy: ["2026-09-28", "2026-10-02"], withTask: ["2026-10-03"])
    let listed = MobileCalendarAgendaDay.listed(days, todayKey: "2026-09-29")
    #expect(listed.map(\.key) == ["2026-09-28", "2026-09-29", "2026-10-02", "2026-10-03"])
    #expect(listed[1].isEmpty)
  }

  @Test("Days without today list every day that has something on it")
  func daysWithoutTodayListEveryBusyDay() {
    let days = Self.days(busy: ["2026-09-27", "2026-10-02"], withTask: ["2026-09-30"])
    let listed = MobileCalendarAgendaDay.listed(days, todayKey: "2026-10-12")
    #expect(listed.map(\.key) == ["2026-09-27", "2026-09-30", "2026-10-02"])
    #expect(MobileCalendarAgendaDay.listed(Self.days(busy: []), todayKey: "2026-10-12").isEmpty)
  }

  @Test("A day reads all-day events, then events and timed tasks by start, then untimed tasks")
  func entriesInterleaveEventsAndTimedTasksByStart() {
    let key = "2026-09-29"
    // Events arrive as the agenda sorts them: no start time first, then by start.
    let day = MobileCalendarAgendaDay(
      date: Date(timeIntervalSince1970: 0), key: key,
      events: [
        Self.event("Holiday", on: key, allDay: true),
        Self.event("Standup", on: key, "09:00", "09:30"),
        Self.event("Offsite", on: key, "10:00", "12:00", from: "2026-09-28"),
        Self.event("One-on-one", on: key, "14:00", "14:30"),
        Self.event("Design review", on: key, "16:30", "17:30"),
      ],
      tasks: [
        Self.task("Tie", on: key, time: 540..<560),
        Self.task("Planning doc", on: key, time: 585..<630),
        Self.task("Refactor", on: key, time: 660..<750),
        Self.task("Groceries"),
      ])
    let titles = day.entries.map { entry -> String in
      switch entry {
      case .event(let event): event.title
      case .task(let task): task.title
      }
    }
    #expect(
      titles == [
        "Holiday", "Offsite", "Standup", "Tie", "Planning doc", "Refactor", "One-on-one", "Design review",
        "Groceries",
      ])
  }

  @Test("An event has passed on a day before today, or on today once it has ended")
  func eventsPassWithTheClock() {
    let today = "2026-09-29"
    let now = 11 * 60 + 20
    let yesterday = MobileCalendarAgendaDay(
      date: Date(timeIntervalSince1970: 0), key: "2026-09-28", events: [], tasks: [])
    #expect(yesterday.hasPassed(Self.event(on: "2026-09-28", allDay: true), todayKey: today, nowMinutes: now))

    let day = MobileCalendarAgendaDay(date: Date(timeIntervalSince1970: 0), key: today, events: [], tasks: [])
    #expect(day.hasPassed(Self.event(on: today, "09:00", "09:30"), todayKey: today, nowMinutes: now))
    #expect(day.hasPassed(Self.event(on: today, "10:00", "11:20"), todayKey: today, nowMinutes: now))
    #expect(!day.hasPassed(Self.event(on: today, "11:00", "12:00"), todayKey: today, nowMinutes: now))
    #expect(!day.hasPassed(Self.event(on: today, allDay: true), todayKey: today, nowMinutes: now))
    #expect(
      !day.hasPassed(Self.event(on: today, "08:00", "09:00", until: "2026-09-30"), todayKey: today, nowMinutes: now))
    #expect(!day.hasPassed(Self.event(on: today, "08:00", nil), todayKey: today, nowMinutes: now))
    #expect(!day.hasPassed(Self.event(on: today, "09:00", "09:30"), todayKey: today, nowMinutes: nil))

    let tomorrow = MobileCalendarAgendaDay(
      date: Date(timeIntervalSince1970: 0), key: "2026-09-30", events: [], tasks: [])
    #expect(!tomorrow.hasPassed(Self.event(on: "2026-09-30", "09:00", "09:30"), todayKey: today, nowMinutes: now))
  }

  @Test("An overnight event passes by its end on its last day; a day a longer event fills reads as all day")
  func overnightEventsReadByTheirPartOfTheDay() {
    let today = "2026-09-29"
    let redEye = Self.event("Red-eye", on: today, "22:30", "01:30", from: "2026-09-28")
    let trip = Self.event("Trip", on: today, "19:00", "09:00", from: "2026-09-28", until: "2026-09-30")
    let lateShow = Self.event("Late show", on: today, "21:00", "00:00", until: "2026-09-30")
    let day = MobileCalendarAgendaDay(
      date: Date(timeIntervalSince1970: 0), key: today,
      events: [redEye, trip, Self.event("Standup", on: today, "09:00", "09:30"), lateShow], tasks: [])

    let titles = day.entries.map { entry -> String in
      if case .event(let event) = entry { return event.title }
      return ""
    }
    #expect(titles == ["Trip", "Red-eye", "Standup", "Late show"])
    #expect(!day.hasPassed(redEye, todayKey: today, nowMinutes: 60), "still on at 1:00 AM")
    #expect(day.hasPassed(redEye, todayKey: today, nowMinutes: 2 * 60), "over by 2:00 AM")
    #expect(!day.hasPassed(trip, todayKey: today, nowMinutes: 23 * 60), "the trip fills the day")
    #expect(!day.hasPassed(lateShow, todayKey: today, nowMinutes: 23 * 60 + 59), "it ends at midnight")
  }
}
