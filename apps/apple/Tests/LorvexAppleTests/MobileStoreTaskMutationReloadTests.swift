import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// A task mutation changes more than the tasks it names. These tests cover the
/// surfaces the mobile store reads again afterwards: the loaded calendar
/// window, the task cache a batch names its tasks in, and the lists' counts.
@Suite("Mobile store: task mutation reload")
@MainActor
struct MobileStoreTaskMutationReloadTests {
  /// A store whose calendar loaded the two weeks around the product day, with
  /// tasks named `titles` planned on that day.
  private struct Fixture {
    let store: MobileStore
    let core: SwiftLorvexCoreService
    let ids: [LorvexTask.ID]
    /// The product day (`yyyy-MM-dd`) the tasks are planned on.
    let today: String
    /// The first and last days of the loaded window.
    let window: (from: String, to: String)

    /// The product day `days` days from today.
    func day(_ days: Int) -> String {
      LorvexDateFormatters.ymdUTCAddingDays(today, days: days) ?? today
    }
  }

  private func fixture(planning titles: [String]) async throws -> Fixture {
    let core = try await makeSeededInMemoryCore()
    let store = MobileStore(core: core)
    await store.refresh()
    let today = store.logicalTodayString
    var ids: [LorvexTask.ID] = []
    for title in titles {
      let task = try await core.createTask(title: title, notes: "")
      try await planTask(core, task.id, on: today)
      ids.append(task.id)
    }
    await store.refresh()
    let window = (
      from: LorvexDateFormatters.ymdUTCAddingDays(today, days: -6) ?? today,
      to: LorvexDateFormatters.ymdUTCAddingDays(today, days: 7) ?? today
    )
    await store.refreshCalendarTimeline(from: window.from, to: window.to)
    return Fixture(store: store, core: core, ids: ids, today: today, window: window)
  }

  @Test("A batch complete shows each task done in the calendar window and the task cache")
  func batchCompleteUpdatesTheCalendarAndTheCache() async throws {
    let f = try await fixture(planning: ["Pack the demo", "Book the room"])
    for id in f.ids {
      #expect(f.store.calendarScheduledTasks.first { $0.id == id }?.status == .open)
    }

    #expect(await f.store.completeTasks(f.ids))

    for id in f.ids {
      #expect(f.store.calendarScheduledTasks.first { $0.id == id }?.status == .completed)
      #expect(f.store.resolveTask(id)?.status == .completed)
    }
  }

  @Test("A batch reopen and a batch defer follow into the calendar window")
  func batchReopenAndDeferUpdateTheCalendar() async throws {
    let f = try await fixture(planning: ["Pack the demo", "Book the room"])
    #expect(await f.store.completeTasks(f.ids))
    #expect(await f.store.reopenTasks(f.ids))
    for id in f.ids {
      #expect(f.store.calendarScheduledTasks.first { $0.id == id }?.status == .open)
    }

    #expect(await f.store.deferTasksToTomorrow(f.ids))

    for id in f.ids {
      let moved = try #require(f.store.calendarScheduledTasks.first { $0.id == id })
      #expect(moved.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == f.day(1))
    }
  }

  @Test("Completing a repeating task puts its next occurrence in the calendar window")
  func completingARepeatingTaskAddsItsNextOccurrence() async throws {
    let f = try await fixture(planning: ["Send the weekly status update"])
    let id = try #require(f.ids.first)
    _ = try await f.core.setTaskRecurrence(
      taskID: id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    await f.store.refreshCalendarTimeline(from: f.window.from, to: f.window.to)
    let before = Set(f.store.calendarScheduledTasks.map(\.id))

    #expect(await f.store.completeTask(id))

    let added = f.store.calendarScheduledTasks.filter { !before.contains($0.id) }
    #expect(added.count == 1)
    #expect(added.first?.title == "Send the weekly status update")
    #expect(added.first?.status == .open)
    let fromTheCore = try await f.core.getScheduledTasks(
      from: f.window.from, to: f.window.to, limit: CalendarGridModel.windowTaskLimit)
    #expect(Set(f.store.calendarScheduledTasks.map(\.id)) == Set(fromTheCore.map(\.id)))
  }

  @Test("A task whose day lies outside the loaded window does not join it")
  func aTaskOutsideTheWindowStaysOut() async throws {
    let f = try await fixture(planning: ["Pack the demo"])
    let id = try #require(f.ids.first)

    try await planTask(f.core, id, on: f.day(60))
    #expect(await f.store.refreshTaskForRoute(id))

    #expect(!f.store.calendarScheduledTasks.contains { $0.id == id })
  }

  @Test("A task moved out of the loaded window leaves it")
  func aTaskMovedOutOfTheWindowLeavesIt() async throws {
    let f = try await fixture(planning: ["Pack the demo"])
    let id = try #require(f.ids.first)
    #expect(f.store.calendarScheduledTasks.contains { $0.id == id })

    try await planTask(f.core, id, on: f.day(60))
    #expect(await f.store.refreshTaskForRoute(id))

    #expect(!f.store.calendarScheduledTasks.contains { $0.id == id })
  }

  @Test("Completing a task lowers its list's open count in the store's lists")
  func completingATaskUpdatesTheListCounts() async throws {
    let core = try await makeSeededInMemoryCore()
    let list = try await core.createList(name: "Launch", description: nil)
    let task = try await core.createTask(title: "Pack the demo", notes: "")
    _ = try await core.moveTask(id: task.id, toListID: list.id)
    let store = MobileStore(core: core)
    await store.refresh()
    let before = try #require(store.lists?.lists.first { $0.id == list.id })
    #expect(before.openCount == 1)

    #expect(await store.completeTask(task.id))

    let after = try #require(store.lists?.lists.first { $0.id == list.id })
    #expect(after.openCount == 0)
    #expect(after.completedCount == 1)
  }
}
