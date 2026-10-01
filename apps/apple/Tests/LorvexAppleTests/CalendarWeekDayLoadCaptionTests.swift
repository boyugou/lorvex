import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func task(minutes: Int) -> LorvexTask {
  LorvexTask(
    id: UUID().uuidString, title: "Task", notes: "", priority: .p2, status: .open, dueDate: nil,
    estimatedMinutes: minutes, tags: [])
}

@Test("The week header fills a bar with a day's planned share, words only an overrun, and says nothing under an empty day")
func weekHeaderCaptionNamesOnlyPlannedTime() throws {
  let load = LorvexWeekLoad.build(
    days: [
      .init(key: "2026-09-21", events: [], tasks: []),
      .init(key: "2026-09-22", events: [], tasks: [task(minutes: 90)]),
      .init(key: "2026-09-23", events: [], tasks: [task(minutes: 600)]),
    ],
    todayKey: "2026-09-20", workStart: 9 * 60, workEnd: 17 * 60)
  #expect(CalendarWeekDayLoadCaption(load.days[0]) == nil)
  let busy = try #require(CalendarWeekDayLoadCaption(load.days[1]))
  #expect(busy == .busy(minutes: 90, freeMinutes: 390))
  #expect(busy.fill == 90.0 / 480.0)
  #expect(busy.visibleText == nil)
  let over = try #require(CalendarWeekDayLoadCaption(load.days[2]))
  #expect(over == .over(minutes: 120))
  #expect(over.fill == 1)
  #expect(over.visibleText != nil)
}
