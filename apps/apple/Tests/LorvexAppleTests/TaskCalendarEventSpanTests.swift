import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// "Add to Calendar" schedules a task at the task's own time: its planned day
// as stored, never shifted through the device timezone; its planned time, or
// the start of the working day; and an end on a later day when the event runs
// past midnight, since a same-day event cannot end before it starts.

private let plannedDay = LorvexDateFormatters.ymdUTC.date(from: "2026-06-20")!

private func span(
  time: Range<Int>? = nil, estimate: Int? = nil, workdayStart: Int = 9 * 60
) -> TaskCalendarEventSpan {
  let task = LorvexTask(
    id: "task-id", title: "Write the quarterly report", notes: "", priority: .p2,
    status: .open, dueDate: nil, plannedDate: plannedDay, plannedTime: time,
    estimatedMinutes: estimate, tags: [])
  return TaskCalendarEventSpan(task: task, plannedDay: plannedDay, workdayStartMinutes: workdayStart)
}

@Test("a timed task keeps its planned day and time")
func calendarSpanKeepsThePlannedTime() {
  let timed = span(time: 870..<930, estimate: 120)
  #expect(timed.startDate == "2026-06-20")
  #expect(timed.startTime == "14:30")
  #expect(timed.endDate == nil)
  #expect(timed.endTime == "15:30")
}

@Test("an untimed task starts with the working day and lasts its estimate")
func calendarSpanStartsAnUntimedTaskWithTheWorkingDay() {
  let untimed = span(estimate: 45, workdayStart: 8 * 60 + 30)
  #expect(untimed.startDate == "2026-06-20")
  #expect(untimed.startTime == "08:30")
  #expect(untimed.endDate == nil)
  #expect(untimed.endTime == "09:15")

  #expect(span().endTime == "10:00")
  #expect(span(estimate: 5).endTime == "09:15")
  #expect(span(time: 600..<600, estimate: 30).endTime == "10:30")
}

@Test("an event that runs past midnight ends on the next day")
func calendarSpanEndsAfterMidnightOnTheNextDay() {
  let toMidnight = span(estimate: 900)
  #expect(toMidnight.startTime == "09:00")
  #expect(toMidnight.endDate == "2026-06-21")
  #expect(toMidnight.endTime == "00:00")

  let pastMidnight = span(estimate: 1000)
  #expect(pastMidnight.endDate == "2026-06-21")
  #expect(pastMidnight.endTime == "01:40")

  let lateBlock = span(time: 1380..<1440)
  #expect(lateBlock.startTime == "23:00")
  #expect(lateBlock.endDate == "2026-06-21")
  #expect(lateBlock.endTime == "00:00")
}
