import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// A stored due date for the local calendar day `offset` days from today:
/// due dates are calendar days materialized at UTC midnight.
private func dueDay(_ offset: Int) -> Date {
  let local = Calendar.current
  let day = local.dateComponents(
    [.year, .month, .day], from: local.date(byAdding: .day, value: offset, to: Date())!)
  let key = String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
  return LorvexDateFormatters.ymdUTC.date(from: key)!
}

private func blocker(_ status: LorvexTask.Status, due: Date? = nil) -> LorvexTask {
  LorvexTask(
    id: "b", title: "Book the venue", notes: "", priority: .p1, status: status, dueDate: due,
    estimatedMinutes: nil, tags: [])
}

@MainActor
@Test("A dependency row adds only that a blocker is started and when an unfinished one is due")
func dependencyFactsNameStartedAndDueOnly() {
  #expect(MobileDependencyFacts(task: blocker(.open), timeZone: .current) == nil)
  #expect(MobileDependencyFacts(task: blocker(.completed, due: dueDay(1)), timeZone: .current) == nil)

  let started = MobileDependencyFacts(task: blocker(.inProgress), timeZone: .current)
  #expect(started?.isStarted == true)
  #expect(started?.due == nil)

  let dated = MobileDependencyFacts(task: blocker(.open, due: dueDay(1)), timeZone: .current)
  #expect(dated?.isStarted == false)
  #expect(dated?.due == "tomorrow")
  #expect(dated?.isOverdue == false)
  #expect(MobileDependencyFacts(task: blocker(.open, due: dueDay(-2)), timeZone: .current)?.isOverdue == true)
}

@Test("VoiceOver names a dependency's status, then when an unfinished one is due")
func dependencyAccessibilityValueNamesStatusThenDue() {
  #expect(taskDependencyAccessibilityValue(blocker(.open), timeZone: .current) == "Open")
  #expect(
    taskDependencyAccessibilityValue(blocker(.inProgress, due: dueDay(1)), timeZone: .current)
      == "In Progress, due tomorrow")
  #expect(taskDependencyAccessibilityValue(blocker(.completed, due: dueDay(1)), timeZone: .current) == "Completed")
}

@MainActor
@Test("The due day is counted from today in the product time zone the row passes")
func dependencyFactsCountTheDueDayInTheProductZone() throws {
  // UTC+14 and UTC-11: 25 hours apart, so never on the same day.
  let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
  let pagoPago = try #require(TimeZone(identifier: "Pacific/Pago_Pago"))
  let todayInKiritimati = PlannedDayBridge.storageDate(forLocalInstant: Date(), timeZone: kiritimati)
  let task = blocker(.open, due: todayInKiritimati)

  #expect(MobileDependencyFacts(task: task, timeZone: kiritimati)?.due == "today")
  #expect(MobileDependencyFacts(task: task, timeZone: pagoPago)?.due != "today")
}
