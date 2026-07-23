import Foundation
import LorvexCore
import LorvexMobile
import Testing

@testable import LorvexApple

/// The canonical task-section projection is shared by every read surface so the
/// "open" / "deferred" / "focus" / "scheduled" split can't drift between macOS
/// and mobile.

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
func focusSectionResolvesInPlanOrderDroppingDuplicatesAndMisses() {
  let a = makeMobileTask(id: "a", title: "a", priority: .p2)
  let b = makeMobileTask(id: "b", title: "b", priority: .p2)
  // Pool order intentionally differs from plan order to prove the result
  // follows the plan, not the pool.
  let pool = [b, a]

  let resolved = LorvexTaskSections.focus(order: ["a", "a", "missing", "b"]) { id in
    pool.first { $0.id == id }
  }

  #expect(resolved.map(\.id) == ["a", "b"])
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

@MainActor
@Test
func mobileOpenSectionMatchesMacOSAndPreservesTodaySurfacing() async throws {
  let open = makeMobileTask(id: "open", title: "open", priority: .p2)
  let planned = plannedTask(id: "planned", plannedDate: Date(timeIntervalSince1970: 1_780_000_000))
  let snapshot = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [open, planned],
    localChangeSequence: 0
  )

  // macOS surface.
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.today = snapshot

  // Mobile surface.
  let mobile = MobileHomeSnapshot(today: snapshot, currentFocus: nil, weeklyReview: nil)

  // The live bug: mobile `openTasks` used to include the planned/deferred task.
  // It now excludes it and matches the macOS split exactly.
  #expect(mobile.openTasks.map(\.id) == ["open"])
  #expect(mobile.openTasks.map(\.id) == store.openTasks.map(\.id))
  #expect(store.deferredTasks.map(\.id) == ["planned"])

  // The planned-for-today task still surfaces on the mobile Today list — the
  // `openTasks` fix must not drop it from the day view.
  #expect(mobile.todayTasks.map(\.id) == ["open", "planned"])
}
