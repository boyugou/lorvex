import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Which days and rows an agenda of the days ahead lists: the menu bar panel's
/// Next 7 Days and the day review's look at tomorrow.
@Suite("Agenda of the days ahead")
struct LorvexAgendaDayTests {
  private static func event(
    _ title: String, from start: String, until end: String? = nil, _ startTime: String? = "10:00",
    _ endTime: String? = "11:00", allDay: Bool = false
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: title, title: title, source: "canonical", editable: true,
      startDate: start, startTime: allDay ? nil : startTime, endDate: end ?? start,
      endTime: allDay ? nil : endTime, allDay: allDay, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  private static func task(
    _ title: String, on key: String, time: Range<Int>? = nil, status: LorvexTask.Status = .open
  ) -> LorvexTask {
    LorvexTask(
      id: title, title: title, notes: "", priority: .p2, status: status, dueDate: nil,
      plannedDate: LorvexDateFormatters.ymdUTC.date(from: key), plannedTime: time,
      estimatedMinutes: 30, tags: [])
  }

  @Test("Only the seven days after today with something on them are listed")
  func listsTheBusyDaysAfterToday() {
    let days = LorvexAgendaDay.build(
      todayKey: "2026-10-01",
      events: [
        Self.event("Today's meeting", from: "2026-10-01"),
        Self.event("Customer call", from: "2026-10-02"),
        Self.event("Far away", from: "2026-10-09"),
      ],
      tasks: [Self.task("Book the venue", on: "2026-10-05")])
    #expect(days.map(\.key) == ["2026-10-02", "2026-10-05"])
    #expect(LorvexAgendaDay.build(todayKey: "2026-10-01", events: [], tasks: []).isEmpty)
  }

  @Test("Events read all-day first, then by start; a span covers each of its days")
  func eventsOrderAndSpan() {
    let days = LorvexAgendaDay.build(
      todayKey: "2026-10-01",
      events: [
        Self.event("Late", from: "2026-10-02", "15:00", "16:00"),
        Self.event("Holiday", from: "2026-10-02", allDay: true),
        Self.event("Early", from: "2026-10-02", "08:00", "09:00"),
        Self.event("Offsite", from: "2026-10-02", until: "2026-10-03", allDay: true),
        Self.event("Overnight", from: "2026-10-03", until: "2026-10-04", "22:00", "00:00"),
      ],
      tasks: [])
    #expect(days.map(\.key) == ["2026-10-02", "2026-10-03"])
    #expect(days[0].events.map(\.title) == ["Holiday", "Offsite", "Early", "Late"])
    #expect(days[1].events.map(\.title) == ["Offsite", "Overnight"])
  }

  @Test("Timed tasks come first by start, finished tasks are left out")
  func tasksOrderAndStatus() {
    let days = LorvexAgendaDay.build(
      todayKey: "2026-10-01",
      events: [],
      tasks: [
        Self.task("Untimed", on: "2026-10-02"),
        Self.task("Afternoon", on: "2026-10-02", time: 840..<870),
        Self.task("Morning", on: "2026-10-02", time: 540..<570),
        Self.task("Finished", on: "2026-10-02", status: .completed),
      ])
    #expect(days.first?.tasks.map(\.title) == ["Morning", "Afternoon", "Untimed"])
  }

  @Test("Tomorrow is named; later days are spelled out")
  func dayTitles() {
    #expect(MenuBarCopy.dayTitle("2026-10-02", todayKey: "2026-10-01") == "Tomorrow")
    #expect(MenuBarCopy.dayTitle("2026-10-03", todayKey: "2026-10-01") != "Tomorrow")
  }

  @Test("The day after today loads as one day, empty when nothing is on it")
  func loadsTheDayAfter() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let free = try await LorvexAgendaDay.loadDay(after: "2026-04-05", from: service)
    #expect(free == LorvexAgendaDay(key: "2026-04-06", events: [], tasks: []))

    let created = try await service.createTask(title: "Call the venue", notes: "")
    _ = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: nil, dueDate: nil,
      plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-04-06"), availableFrom: nil,
      tags: [], dependsOn: [])
    let day = try await LorvexAgendaDay.loadDay(after: "2026-04-05", from: service)
    #expect(day.key == "2026-04-06")
    #expect(day.tasks.map(\.title) == ["Call the venue"])
  }
}
