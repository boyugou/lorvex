import Foundation
import LorvexCore
import LorvexMobile
import Testing

@testable import LorvexApple

/// The canonical task-section projection is shared by every read surface so the
/// "open" / "deferred" / "scheduled" split can't drift between macOS and
/// mobile.

private func plannedTask(id: String, plannedDate: Date) -> LorvexTask {
  var task = makeMobileTask(id: id, title: id, priority: .p2)
  task.plannedDate = plannedDate
  return task
}

@Test
func openSectionExcludesPlannedAndDeferredSectionCarriesIt() {
  let open = makeMobileTask(id: "open", title: "open", priority: .p2)
  let planned = plannedTask(id: "planned", plannedDate: Date(timeIntervalSince1970: 1_780_000_000))
  let done = {
    var task = makeMobileTask(id: "done", title: "done", priority: .p2)
    task.status = .completed
    return task
  }()

  let tasks = [open, planned, done]

  #expect(tasks.lorvexOpenSection.map(\.id) == ["open"])
  #expect(tasks.lorvexDeferredSection.map(\.id) == ["planned"])
}

@Test
func overdueComparesTheDueDayWithTheLogicalDay() {
  var due = makeMobileTask(id: "due", title: "due", priority: .p2)
  due.dueDate = LorvexDateFormatters.ymdUTC.date(from: "2026-05-24")
  let undated = makeMobileTask(id: "undated", title: "undated", priority: .p2)

  #expect(LorvexTaskSections.isOverdue(due, logicalDay: "2026-05-25"))
  // Due today is not overdue yet.
  #expect(!LorvexTaskSections.isOverdue(due, logicalDay: "2026-05-24"))
  #expect(!LorvexTaskSections.isOverdue(undated, logicalDay: "2026-05-25"))
  // A finished task is never overdue, whatever its deadline.
  var done = due
  done.status = .completed
  #expect(!LorvexTaskSections.isOverdue(done, logicalDay: "2026-05-25"))
}

@Test
func scheduledSectionSortsByActionDateThenTitleAndDropsUndated() {
  var early = makeMobileTask(id: "early", title: "Zebra", priority: .p2)
  early.plannedDate = Date(timeIntervalSince1970: 1_000)
  var lateByDue = makeMobileTask(id: "late-due", title: "Apple", priority: .p2)
  lateByDue.dueDate = Date(timeIntervalSince1970: 5_000)
  var sameDayA = makeMobileTask(id: "same-a", title: "Apple", priority: .p2)
  sameDayA.plannedDate = Date(timeIntervalSince1970: 2_000)
  var sameDayZ = makeMobileTask(id: "same-z", title: "Zebra", priority: .p2)
  sameDayZ.plannedDate = Date(timeIntervalSince1970: 2_000)
  let undated = makeMobileTask(id: "undated", title: "Undated", priority: .p2)

  let tasks = [undated, sameDayZ, lateByDue, sameDayA, early]

  // Sorted by planned-or-due ascending; equal dates tie-break on title; the
  // task with neither date is dropped.
  #expect(tasks.lorvexScheduledSection.map(\.id) == ["early", "same-a", "same-z", "late-due"])
}
