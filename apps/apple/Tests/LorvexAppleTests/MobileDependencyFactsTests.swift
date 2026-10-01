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
  #expect(MobileDependencyFacts(task: blocker(.open)) == nil)
  #expect(MobileDependencyFacts(task: blocker(.completed, due: dueDay(1))) == nil)

  let started = MobileDependencyFacts(task: blocker(.inProgress))
  #expect(started?.isStarted == true)
  #expect(started?.due == nil)

  let dated = MobileDependencyFacts(task: blocker(.open, due: dueDay(1)))
  #expect(dated?.isStarted == false)
  #expect(dated?.due == "tomorrow")
  #expect(dated?.isOverdue == false)
  #expect(MobileDependencyFacts(task: blocker(.open, due: dueDay(-2)))?.isOverdue == true)
}

@Test("VoiceOver names a dependency's status, then when an unfinished one is due")
func dependencyAccessibilityValueNamesStatusThenDue() {
  #expect(MobileDependencyFacts.accessibilityValue(for: blocker(.open)) == "Open")
  #expect(
    MobileDependencyFacts.accessibilityValue(for: blocker(.inProgress, due: dueDay(1)))
      == "In Progress, due tomorrow")
  #expect(MobileDependencyFacts.accessibilityValue(for: blocker(.completed, due: dueDay(1))) == "Completed")
}
