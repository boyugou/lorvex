import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func task(minutes: Int) -> LorvexTask {
  LorvexTask(
    id: UUID().uuidString, title: "Task", notes: "", priority: .p2, status: .open, dueDate: nil,
    estimatedMinutes: minutes, tags: [])
}

/// The week grid's column for today measures the same tasks Today's page does,
/// so the two never state different overruns for one day, while any other day
/// counts only the tasks scheduled on it.
@Suite("Week column load on today")
struct CalendarWeekTodayLoadTests {
  @Test("today counts Today's whole list once each, and keeps a scheduled task the list lacks")
  func todayCountsTheList() {
    let planned = task(minutes: 60)
    let dueToday = task(minutes: 90)
    let carriedOver = task(minutes: 30)
    let strayScheduled = task(minutes: 15)

    let counted = CalendarWeekGridView.loadTasks(
      scheduled: [planned, strayScheduled], todaysList: [dueToday, planned, carriedOver])

    #expect(counted.map(\.id) == [dueToday, planned, carriedOver, strayScheduled].map(\.id))
  }

  @Test("any other day counts only its scheduled tasks")
  func otherDaysCountScheduledTasks() {
    let planned = task(minutes: 60)

    let counted = CalendarWeekGridView.loadTasks(scheduled: [planned], todaysList: nil)

    #expect(counted.map(\.id) == [planned.id])
  }

  @Test("today's column states the overrun Today's overbooked decision measures")
  func columnAgreesWithTheTodayPage() throws {
    let today = "2026-09-21"
    let window = (9 * 60)..<(17 * 60)
    let planned = task(minutes: 240)
    let dueToday = task(minutes: 240)
    let carriedOver = task(minutes: 180)
    let list = [planned, dueToday, carriedOver]

    let page = LorvexCalmToday.build(
      tasks: list, events: [], doneToday: 0, nowMinutes: window.lowerBound,
      logicalDay: today, workingHours: window)
    let week = LorvexWeekLoad.build(
      days: [
        .init(
          key: today, events: [],
          tasks: CalendarWeekGridView.loadTasks(scheduled: [planned], todaysList: list))
      ],
      todayKey: today, workStart: window.lowerBound, workEnd: window.upperBound,
      nowMinutes: window.lowerBound)

    let overbooked = try #require(page.overbooked)
    #expect(week.days[0].overMinutes == overbooked.workMinutes - overbooked.freeMinutes)
    #expect(week.days[0].overMinutes == 180)
  }
}
